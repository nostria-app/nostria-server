#!/usr/bin/env node

const DEFAULT_RETRIES = 5;

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

async function requestJson(url, authHeader) {
  let lastError;

  for (let attempt = 1; attempt <= DEFAULT_RETRIES; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: {
          Accept: "application/json",
          Authorization: authHeader,
        },
      });

      if (!response.ok) {
        throw new Error(`Request failed for ${url.toString()} with status ${response.status}`);
      }

      return await response.json();
    } catch (error) {
      lastError = error;
      if (attempt === DEFAULT_RETRIES) {
        break;
      }

      const delayMs = attempt * 1000;
      console.error(`[${new Date().toISOString()}] retrying ${url.toString()} attempt=${attempt + 1} delayMs=${delayMs}`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  throw lastError;
}

function normalizeBaseUrl(value) {
  const url = new URL(value);
  return url.origin;
}

function buildUsersUrl(baseUrl) {
  const url = new URL("/api/users", baseUrl);
  url.searchParams.set("sort", JSON.stringify(["pubkey", "ASC"]));
  return url;
}

async function fetchAllUsers(source) {
  const authHeader = basicAuth(source.username, source.password);
  const users = new Map();
  const body = await requestJson(buildUsersUrl(source.baseUrl), authHeader);
  if (!Array.isArray(body)) {
    throw new Error(`Unexpected user list response for ${source.name}`);
  }

  console.error(`[${new Date().toISOString()}] ${source.name} users=${body.length}`);

  for (const user of body) {
    const refs = Array.isArray(user.blobs) ? user.blobs.filter((value) => typeof value === "string" && value.length > 0) : [];
    const unique = [...new Set(refs)].sort();
    users.set(user.pubkey, {
      pubkey: user.pubkey,
      refsTotal: refs.length,
      refsUnique: unique.length,
      duplicateRefs: refs.length - unique.length,
      blobs: unique,
    });
  }

  return users;
}

function setDifference(left, right) {
  return left.filter((value) => !right.has(value));
}

function unionSorted(values) {
  return [...new Set(values)].sort();
}

function buildUserAudit(pubkey, localUser, euUser, usUser) {
  const localSet = new Set(localUser?.blobs ?? []);
  const euSet = new Set(euUser?.blobs ?? []);
  const usSet = new Set(usUser?.blobs ?? []);
  const remoteUnion = unionSorted([...(euUser?.blobs ?? []), ...(usUser?.blobs ?? [])]);
  const remoteSet = new Set(remoteUnion);

  const missingOnLocal = setDifference(remoteUnion, localSet);
  const extraOnLocal = setDifference(localUser?.blobs ?? [], remoteSet);

  return {
    pubkey,
    local: {
      refsTotal: localUser?.refsTotal ?? 0,
      refsUnique: localUser?.refsUnique ?? 0,
      duplicateRefs: localUser?.duplicateRefs ?? 0,
    },
    eu: {
      refsTotal: euUser?.refsTotal ?? 0,
      refsUnique: euUser?.refsUnique ?? 0,
      duplicateRefs: euUser?.duplicateRefs ?? 0,
    },
    us: {
      refsTotal: usUser?.refsTotal ?? 0,
      refsUnique: usUser?.refsUnique ?? 0,
      duplicateRefs: usUser?.duplicateRefs ?? 0,
    },
    remoteUnique: remoteUnion.length,
    missingOnLocal,
    extraOnLocal,
    inSync: missingOnLocal.length === 0 && extraOnLocal.length === 0,
  };
}

function summarizeAudit(entries) {
  const withRemoteData = entries.filter((entry) => entry.remoteUnique > 0);
  const missingOnLocal = entries.filter((entry) => entry.missingOnLocal.length > 0);
  const extraOnLocal = entries.filter((entry) => entry.extraOnLocal.length > 0);
  const remoteDuplicateRefs = entries.filter((entry) => entry.eu.duplicateRefs > 0 || entry.us.duplicateRefs > 0);

  return {
    usersAudited: entries.length,
    usersWithRemoteData: withRemoteData.length,
    usersInSync: entries.filter((entry) => entry.inSync).length,
    usersMissingOnLocal: missingOnLocal.length,
    usersExtraOnLocal: extraOnLocal.length,
    usersWithRemoteDuplicateRefs: remoteDuplicateRefs.length,
    missingBlobCount: missingOnLocal.reduce((total, entry) => total + entry.missingOnLocal.length, 0),
    extraBlobCount: extraOnLocal.reduce((total, entry) => total + entry.extraOnLocal.length, 0),
  };
}

async function main() {
  const options = parseArgs(process.argv);

  const sources = [
    {
      name: "local",
      baseUrl: normalizeBaseUrl(options.localUrl ?? "http://127.0.0.1:3000"),
      username: options.localUsername ?? "admin",
      password: options.localPassword,
    },
    {
      name: "eu",
      baseUrl: normalizeBaseUrl(options.euUrl ?? "https://mibo.nostria.app"),
      username: options.remoteUsername ?? "admin",
      password: options.remotePassword,
    },
    {
      name: "us",
      baseUrl: normalizeBaseUrl(options.usUrl ?? "https://milo.nostria.app"),
      username: options.remoteUsername ?? "admin",
      password: options.remotePassword,
    },
  ];

  for (const source of sources) {
    if (!source.password) {
      throw new Error(`Missing password for ${source.name}`);
    }
  }

  const localUsers = await fetchAllUsers(sources[0]);
  const euUsers = await fetchAllUsers(sources[1]);
  const usUsers = await fetchAllUsers(sources[2]);

  const pubkeys = unionSorted([
    ...localUsers.keys(),
    ...euUsers.keys(),
    ...usUsers.keys(),
  ]);

  const entries = pubkeys.map((pubkey) => buildUserAudit(pubkey, localUsers.get(pubkey), euUsers.get(pubkey), usUsers.get(pubkey)));
  const summary = summarizeAudit(entries);

  const result = {
    generatedAt: new Date().toISOString(),
    sources: {
      localUsers: localUsers.size,
      euUsers: euUsers.size,
      usUsers: usUsers.size,
    },
    summary,
    usersMissingOnLocal: entries.filter((entry) => entry.missingOnLocal.length > 0),
    usersExtraOnLocal: entries.filter((entry) => entry.extraOnLocal.length > 0),
    usersWithRemoteDuplicateRefs: entries.filter((entry) => entry.eu.duplicateRefs > 0 || entry.us.duplicateRefs > 0),
  };

  console.log(JSON.stringify(result, null, 2));
}

await main();