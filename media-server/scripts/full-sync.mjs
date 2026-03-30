#!/usr/bin/env node

import db, { blobDB } from "/app/build/db/db.js";
import { addFromUpload } from "/app/build/storage/index.js";
import { removeUpload, saveFromResponse } from "/app/build/storage/upload.js";
import { makeHTTPRequest } from "/app/build/transport/http.js";

const DEFAULT_PAGE_SIZE = 100;

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

function normalizeOrigin(value) {
  const remote = new URL(value);
  return new URL(remote.origin);
}

function buildBlobPageUrl(remoteOrigin, offset, pageSize) {
  const url = new URL("/api/blobs", remoteOrigin);
  url.searchParams.set("sort", JSON.stringify(["uploaded", "ASC"]));
  url.searchParams.set("range", JSON.stringify([offset, offset + pageSize]));
  return url;
}

function resolveBlobUrl(remoteOrigin, blob) {
  if (blob.url) {
    return new URL(blob.url, remoteOrigin).toString();
  }

  return new URL(`/${blob.sha256}`, remoteOrigin).toString();
}

async function fetchRemoteBlobPage(remoteOrigin, authHeader, offset, pageSize) {
  const response = await makeHTTPRequest(buildBlobPageUrl(remoteOrigin, offset, pageSize), {
    headers: {
      Accept: "application/json",
      Authorization: authHeader,
    },
  });

  if (!response.statusCode || response.statusCode < 200 || response.statusCode >= 300) {
    throw new Error(`Failed to list remote blobs at offset ${offset}: status ${response.statusCode ?? "unknown"}`);
  }

  const body = await readJson(response);
  if (!Array.isArray(body)) {
    throw new Error("Remote blob list response was not an array");
  }

  return body;
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

async function syncRemoteBlob(remoteOrigin, blob) {
  if (!blob.sha256) {
    throw new Error("Remote blob is missing sha256");
  }

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
  const remoteUrl = options.remoteUrl;
  const remoteUsername = options.remoteUsername ?? "admin";
  const remotePassword = options.remotePassword;
  const pageSize = Number.parseInt(options.pageSize ?? String(DEFAULT_PAGE_SIZE), 10);

  if (!remoteUrl) {
    throw new Error("Missing --remoteUrl");
  }
  if (!remotePassword) {
    throw new Error("Missing --remotePassword");
  }
  if (!Number.isFinite(pageSize) || pageSize <= 0) {
    throw new Error("Invalid --pageSize");
  }

  const remoteOrigin = normalizeOrigin(remoteUrl);
  const authHeader = basicAuth(remoteUsername, remotePassword);

  const summary = {
    source: remoteOrigin.toString(),
    synced: 0,
    skipped: 0,
    ownersAdded: 0,
    failed: 0,
    failures: [],
  };

  let offset = 0;
  let page = 0;

  while (true) {
    const blobs = await fetchRemoteBlobPage(remoteOrigin, authHeader, offset, pageSize);
    if (blobs.length === 0) {
      break;
    }

    page += 1;
    console.error(`[${new Date().toISOString()}] page=${page} offset=${offset} count=${blobs.length}`);

    for (const blob of blobs) {
      try {
        const result = await syncRemoteBlob(remoteOrigin, blob);
        if (result.synced) {
          summary.synced += 1;
        } else {
          summary.skipped += 1;
        }
        summary.ownersAdded += result.ownersAdded;
      } catch (error) {
        summary.failed += 1;
        summary.failures.push({
          sha256: blob.sha256,
          url: resolveBlobUrl(remoteOrigin, blob),
          reason: error instanceof Error ? error.message : String(error),
        });
      }
    }

    if (blobs.length < pageSize) {
      break;
    }

    offset += blobs.length;
  }

  console.log(JSON.stringify(summary, null, 2));
}

try {
  await main();
} finally {
  db.close();
}
