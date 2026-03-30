#!/usr/bin/env node

import db, { blobDB } from "/app/build/db/db.js";
import { addFromUpload } from "/app/build/storage/index.js";
import { removeUpload, saveFromResponse } from "/app/build/storage/upload.js";
import { makeHTTPRequest } from "/app/build/transport/http.js";

function parseArgs(argv) {
  const options = {};

  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      throw new Error(`Unexpected argument: ${arg}`);
    }

    const key = arg.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for --${key}`);
    }

    options[key] = value;
    index += 1;
  }

  return options;
}

function basicAuth(username, password) {
  return "Basic " + Buffer.from(`${username}:${password}`).toString("base64");
}

async function readText(response) {
  const chunks = [];
  for await (const chunk of response) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function readJson(response) {
  return JSON.parse(await readText(response));
}

async function requestJson(url, authHeader) {
  const response = await makeHTTPRequest(url, {
    headers: {
      Accept: "application/json",
      Authorization: authHeader,
    },
  });

  if (!response.statusCode || response.statusCode < 200 || response.statusCode >= 300) {
    throw new Error(`Request failed for ${url.toString()} with status ${response.statusCode ?? "unknown"}`);
  }

  return readJson(response);
}

function normalizeOrigin(value) {
  const remote = new URL(value);
  return new URL(remote.origin);
}

function buildUserLookupUrl(remoteOrigin, pubkey) {
  const url = new URL("/api/users", remoteOrigin);
  url.searchParams.set("filter", JSON.stringify({ pubkey }));
  url.searchParams.set("range", JSON.stringify([0, 1]));
  return url;
}

function buildBlobLookupUrl(remoteOrigin, sha256) {
  return new URL(`/api/blobs/${sha256}`, remoteOrigin);
}

function resolveBlobUrl(remoteOrigin, blob) {
  if (blob.url) {
    return new URL(blob.url, remoteOrigin).toString();
  }

  return new URL(`/${blob.sha256}`, remoteOrigin).toString();
}

function syncBlobOwners(blob) {
  let ownersAdded = 0;

  for (const owner of blob.owners ?? []) {
    if (typeof owner !== "string" || owner.length === 0) {
      continue;
    }

    if (blobDB.hasOwner(blob.sha256, owner)) {
      continue;
    }

    blobDB.addOwner(blob.sha256, owner);
    ownersAdded += 1;
  }

  return ownersAdded;
}

async function syncBlob(remoteOrigin, blob) {
  if (blobDB.hasBlob(blob.sha256)) {
    return {
      synced: false,
      ownersAdded: syncBlobOwners(blob),
    };
  }

  let upload;
  try {
    const response = await makeHTTPRequest(resolveBlobUrl(remoteOrigin, blob));
    upload = await saveFromResponse(response);

    if (upload.sha256 !== blob.sha256) {
      throw new Error(`Downloaded blob hash mismatch for ${blob.sha256}`);
    }

    await addFromUpload(upload, blob.type, { uploaded: blob.uploaded });

    return {
      synced: true,
      ownersAdded: syncBlobOwners(blob),
    };
  } catch (error) {
    if (upload) {
      await removeUpload(upload);
    }
    throw error;
  }
}

async function main() {
  const options = parseArgs(process.argv);
  const remoteOrigin = normalizeOrigin(options.remoteUrl);
  const authHeader = basicAuth(options.remoteUsername ?? "admin", options.remotePassword);
  const pubkey = options.pubkey;

  if (!pubkey) {
    throw new Error("Missing --pubkey");
  }

  const users = await requestJson(buildUserLookupUrl(remoteOrigin, pubkey), authHeader);
  const user = Array.isArray(users) ? users[0] : null;
  const blobIds = Array.isArray(user?.blobs) ? user.blobs : [];
  const uniqueBlobIds = [...new Set(blobIds)];

  const summary = {
    source: remoteOrigin.toString(),
    pubkey,
    requested: uniqueBlobIds.length,
    requestedTotal: blobIds.length,
    duplicateRefs: blobIds.length - uniqueBlobIds.length,
    synced: 0,
    skipped: 0,
    ownersAdded: 0,
    failed: 0,
    failures: [],
  };

  for (const sha256 of uniqueBlobIds) {
    try {
      const blob = await requestJson(buildBlobLookupUrl(remoteOrigin, sha256), authHeader);
      const result = await syncBlob(remoteOrigin, blob);
      if (result.synced) {
        summary.synced += 1;
      } else {
        summary.skipped += 1;
      }
      summary.ownersAdded += result.ownersAdded;
    } catch (error) {
      summary.failed += 1;
      summary.failures.push({ sha256, reason: error instanceof Error ? error.message : String(error) });
    }
  }

  console.log(JSON.stringify(summary, null, 2));
}

try {
  await main();
} finally {
  db.close();
}
