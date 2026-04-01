import express from 'express';
import http from 'http';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import httpProxy from 'http-proxy';
import { JanusWhipServer } from 'janus-whip-server';
import { verifyEvent } from 'nostr-tools';

function normalizeIceServer(entry) {
  if (typeof entry === 'string') {
    return { uri: entry, urls: entry };
  }

  const normalized = { ...entry };
  const urls = normalized.urls || normalized.url || normalized.uri;

  if (urls && !normalized.urls) {
    normalized.urls = urls;
  }

  if (!normalized.uri) {
    normalized.uri = Array.isArray(urls) ? urls[0] : urls;
  }

  return normalized;
}

function parseBoolean(value, defaultValue) {
  if (value === undefined || value === null || value === '') {
    return defaultValue;
  }

  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
}

function parseIceServers(value) {
  if (!value) {
    return [];
  }

  const trimmedValue = value.trim();

  if (!trimmedValue.startsWith('[') && !trimmedValue.startsWith('{')) {
    return trimmedValue
      .split(',')
      .map(uri => uri.trim())
      .filter(Boolean)
      .map(uri => normalizeIceServer(uri));
  }

  try {
    const parsed = JSON.parse(trimmedValue);
    return (Array.isArray(parsed) ? parsed : [parsed]).map(normalizeIceServer);
  } catch (error) {
    throw new Error(`Invalid WHIP_ICE_SERVERS JSON: ${error.message}`);
  }
}

function dedupeIceServers(iceServers) {
  const seen = new Set();

  return iceServers.filter(entry => {
    const urls = Array.isArray(entry.urls) ? entry.urls.join(',') : entry.urls || entry.uri || '';
    const key = JSON.stringify({
      urls,
      username: entry.username || '',
      credential: entry.credential || ''
    });

    if (seen.has(key)) {
      return false;
    }

    seen.add(key);
    return true;
  });
}

async function fetchMeteredIceServers() {
  const domain = process.env.METERED_TURN_DOMAIN;
  const apiKey = process.env.METERED_TURN_API_KEY;

  if (!domain || !apiKey) {
    return [];
  }

  const endpoint = new URL(`https://${domain}/api/v1/turn/credentials`);
  endpoint.searchParams.set('apiKey', apiKey);

  const response = await fetch(endpoint, {
    signal: AbortSignal.timeout(10000)
  });

  if (!response.ok) {
    throw new Error(`Metered TURN API returned ${response.status}`);
  }

  const payload = await response.json();
  if (!Array.isArray(payload)) {
    throw new Error('Metered TURN API returned a non-array response');
  }

  return payload.map(normalizeIceServer);
}

function parseRoomId(value) {
  const roomId = Number.parseInt(value, 10);
  if (!Number.isInteger(roomId) || roomId <= 0) {
    throw new Error('WHIP_ROOM_ID must be a positive integer');
  }

  return roomId;
}

function getBearerToken(req) {
  const header = req.headers.authorization || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

function getNostrAuthorization(req) {
  const header = req.headers.authorization || '';
  const match = header.match(/^Nostr\s+(.+)$/i);
  return match ? match[1] : null;
}

function findTagValue(event, tagName) {
  const match = Array.isArray(event.tags)
    ? event.tags.find(tag => Array.isArray(tag) && tag[0] === tagName)
    : null;
  return match ? match[1] : undefined;
}

function decodeBase64Json(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
  const decoded = Buffer.from(padded, 'base64').toString('utf8');
  return JSON.parse(decoded);
}

function getAbsoluteRequestUrl(req) {
  return `${req.protocol}://${req.get('host')}${req.originalUrl}`;
}

function parseAllowedOrigins(value) {
  if (!value) {
    return [
      'http://localhost:4200',
      'http://127.0.0.1:4200',
      'https://stream.openresist.com',
      'https://nostria.app'
    ];
  }

  return value
    .split(',')
    .map(origin => origin.trim())
    .filter(Boolean);
}

function applyCorsHeaders(req, res, allowedOrigins) {
  const origin = req.get('origin');
  if (!origin || !allowedOrigins.includes(origin)) {
    return false;
  }

  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS,DELETE,PATCH');
  return true;
}

async function fetchSubscriptionStatus(pubkey, accountApiBase) {
  const endpoint = new URL(`${pubkey}`, accountApiBase.endsWith('/') ? accountApiBase : `${accountApiBase}/`);
  const response = await fetch(endpoint, {
    signal: AbortSignal.timeout(10000)
  });

  if (!response.ok) {
    throw new Error(`Subscription API returned ${response.status}`);
  }

  return response.json();
}

async function main() {
  const app = express();
  app.set('trust proxy', true);
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  const publicDir = path.join(__dirname, '..', 'public');
  const httpPort = Number.parseInt(process.env.WHIP_PORT || '7080', 10);
  const basePath = process.env.WHIP_BASE_PATH || '/whip';
  const endpointId = process.env.WHIP_ENDPOINT_ID || 'live';
  const endpointLabel = process.env.WHIP_ENDPOINT_LABEL || 'OpenResist Live';
  const browserEndpointId = process.env.WHIP_BROWSER_ENDPOINT_ID || 'browser';
  const browserEndpointLabel = process.env.WHIP_BROWSER_ENDPOINT_LABEL || 'OpenResist Browser';
  const endpointToken = process.env.WHIP_ENDPOINT_TOKEN || undefined;
  const adminToken = process.env.STREAM_ADMIN_TOKEN || process.env.JANUS_ADMIN_SECRET || undefined;
  const roomId = parseRoomId(process.env.WHIP_ROOM_ID || '1234');
  const nostrAuthWindowSeconds = Number.parseInt(process.env.NIP98_AUTH_WINDOW_SECONDS || '60', 10);
  const dynamicEndpointTtlSeconds = Number.parseInt(process.env.DYNAMIC_ENDPOINT_TTL_SECONDS || '900', 10);
  const accountApiBase = process.env.NOSTRIA_ACCOUNT_API_BASE || 'https://api.nostria.app/api/account';
  const allowedOrigins = parseAllowedOrigins(process.env.CORS_ALLOWED_ORIGINS);
  const janusWsUrl = process.env.JANUS_WS_URL || 'ws://janus:8188';
  const janusHttpUrl = process.env.JANUS_HTTP_URL || 'http://janus:8088/janus';
  const debugLevel = process.env.WHIP_DEBUG_LEVEL || 'info';
  const staticIceServers = parseIceServers(process.env.WHIP_ICE_SERVERS || '[]');
  let meteredIceServers = [];
  let meteredTurnError = null;
  const dynamicEndpoints = new Map();

  try {
    meteredIceServers = await fetchMeteredIceServers();
  } catch (error) {
    meteredTurnError = error.message;
    console.error(`Failed to fetch Metered TURN credentials: ${error.message}`);
  }

  const iceServers = dedupeIceServers([...staticIceServers, ...meteredIceServers]);
  const janusProxy = httpProxy.createProxyServer({
    target: janusHttpUrl,
    changeOrigin: true,
    xfwd: true
  });

  let whipServer;
  const endpointDefinitions = [
    { id: endpointId, label: endpointLabel },
    { id: browserEndpointId, label: browserEndpointLabel }
  ].filter((entry, index, list) => list.findIndex(candidate => candidate.id === entry.id) === index);

  function bindEndpointEvents(endpoint) {
    endpoint.on('endpoint-active', function onEndpointActive() {
      console.log(`[${this.id}] publisher connected`);
    });

    endpoint.on('endpoint-inactive', function onEndpointInactive() {
      console.log(`[${this.id}] publisher disconnected`);
    });

    return endpoint;
  }

  function createManagedEndpoint(definition) {
    return bindEndpointEvents(whipServer.createEndpoint({
      id: definition.id,
      room: roomId,
      label: definition.label,
      token: endpointToken
    }));
  }

  async function resetManagedEndpoint(id) {
    const definition = endpointDefinitions.find(entry => entry.id === id);
    if (definition) {
      await whipServer.destroyEndpoint({ id });
      return createManagedEndpoint(definition);
    }

    if (dynamicEndpoints.has(id)) {
      await whipServer.destroyEndpoint({ id });
      clearTimeout(dynamicEndpoints.get(id).expiresTimer);
      dynamicEndpoints.delete(id);
      return { id, dynamic: true };
    }

    return null;
  }

  function buildDynamicEndpointResponse(req, dynamicEndpoint) {
    const origin = `${req.protocol}://${req.get('host')}`;
    return {
      id: dynamicEndpoint.id,
      url: `${origin}${basePath}/endpoint/${dynamicEndpoint.id}`,
      token: dynamicEndpoint.token,
      authorization: {
        scheme: 'Bearer',
        token: dynamicEndpoint.token
      },
      createdAt: dynamicEndpoint.createdAt,
      expiresAt: dynamicEndpoint.expiresAt,
      roomId
    };
  }

  async function destroyDynamicEndpoint(id) {
    const endpointState = dynamicEndpoints.get(id);
    if (!endpointState) {
      return;
    }

    clearTimeout(endpointState.expiresTimer);
    dynamicEndpoints.delete(id);
    try {
      await whipServer.destroyEndpoint({ id });
      console.log(`[${id}] destroyed dynamic WHIP endpoint`);
    } catch (error) {
      console.error(`Failed to destroy dynamic endpoint ${id}:`, error);
    }
  }

  function scheduleDynamicEndpointExpiry(id, ttlMs) {
    return setTimeout(() => {
      void destroyDynamicEndpoint(id);
    }, ttlMs);
  }

  function createDynamicEndpoint(pubkey) {
    const id = crypto.randomBytes(12).toString('hex');
    const token = crypto.randomBytes(24).toString('hex');
    const createdAt = new Date().toISOString();
    const expiresAt = new Date(Date.now() + dynamicEndpointTtlSeconds * 1000).toISOString();
    const endpoint = whipServer.createEndpoint({
      id,
      room: roomId,
      label: 'OpenResist Premium Stream',
      token
    });

    const state = {
      id,
      pubkey,
      token,
      createdAt,
      expiresAt,
      expiresTimer: scheduleDynamicEndpointExpiry(id, dynamicEndpointTtlSeconds * 1000)
    };

    endpoint.on('endpoint-active', function onEndpointActive() {
      console.log(`[${this.id}] dynamic publisher connected`);
    });

    endpoint.on('endpoint-inactive', function onEndpointInactive() {
      console.log(`[${this.id}] dynamic publisher disconnected`);
      void destroyDynamicEndpoint(this.id);
    });

    dynamicEndpoints.set(id, state);
    return state;
  }

  async function verifyNip98Request(req) {
    const encodedEvent = getNostrAuthorization(req);
    if (!encodedEvent) {
      return { ok: false, status: 401, error: 'Missing Nostr authorization header' };
    }

    let event;
    try {
      event = decodeBase64Json(encodedEvent);
    } catch {
      return { ok: false, status: 401, error: 'Invalid Nostr authorization payload' };
    }

    if (event.kind !== 27235) {
      return { ok: false, status: 401, error: 'Invalid NIP-98 event kind' };
    }

    if (!verifyEvent(event)) {
      return { ok: false, status: 401, error: 'Invalid Nostr event signature' };
    }

    const now = Math.floor(Date.now() / 1000);
    if (Math.abs(now - event.created_at) > nostrAuthWindowSeconds) {
      return { ok: false, status: 401, error: 'Expired NIP-98 authorization event' };
    }

    const expectedUrl = getAbsoluteRequestUrl(req);
    if (findTagValue(event, 'u') !== expectedUrl) {
      return { ok: false, status: 401, error: 'NIP-98 URL tag mismatch' };
    }

    if (findTagValue(event, 'method') !== req.method.toUpperCase()) {
      return { ok: false, status: 401, error: 'NIP-98 method tag mismatch' };
    }

    return { ok: true, event };
  }

  function requireAdmin(req, res, next) {
    if (!adminToken) {
      res.status(503).json({ error: 'Admin routes disabled: no admin token configured' });
      return;
    }

    if (getBearerToken(req) !== adminToken) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    next();
  }

  janusProxy.on('error', (error, req, res) => {
    console.error('Janus proxy error:', error.message);
    if (res && typeof res.writeHead === 'function' && !res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Janus proxy unavailable' }));
      return;
    }

    if (res && typeof res.destroy === 'function') {
      res.destroy();
    }
  });

  app.get('/', (_req, res) => {
    res.redirect('/watch/');
  });

  app.use((req, res, next) => {
    applyCorsHeaders(req, res, allowedOrigins);

    if (req.method === 'OPTIONS') {
      res.status(204).end();
      return;
    }

    next();
  });

  app.get('/watch/config.json', (_req, res) => {
    const protocol = process.env.PUBLIC_JANUS_PROTOCOL || 'auto';
    const janusPath = '/janus';
    res.json({
      roomId,
      endpointId,
      endpointLabel,
      browserEndpointId,
      janusPath,
      janusProtocol: protocol,
      janusHttpUrl: janusPath,
      iceServers,
      meteredTurnEnabled: meteredIceServers.length > 0
    });
  });

  app.use('/watch', express.static(publicDir, { extensions: ['html'] }));

  app.use('/janus', (req, res) => {
    janusProxy.web(req, res);
  });

  app.get('/healthz', (_req, res) => {
    res.json({
      status: 'ok',
      janusWsUrl,
      basePath,
      endpointId,
      browserEndpointId,
      roomId,
      iceServersCount: iceServers.length,
      meteredTurnEnabled: meteredIceServers.length > 0,
      meteredTurnError,
      endpoints: whipServer ? whipServer.listEndpoints() : []
    });
  });

  app.get('/endpoints', (_req, res) => {
    res.json(whipServer ? whipServer.listEndpoints() : []);
  });

  app.get('/admin/endpoints', requireAdmin, (_req, res) => {
    res.json({
      basePath,
      endpoints: whipServer ? whipServer.listEndpoints() : [],
      dynamicEndpoints: Array.from(dynamicEndpoints.values()).map(endpoint => ({
        id: endpoint.id,
        createdAt: endpoint.createdAt,
        expiresAt: endpoint.expiresAt
      }))
    });
  });

  app.post('/admin/endpoints/:id/reset', requireAdmin, async (req, res) => {
    try {
      const endpoint = await resetManagedEndpoint(req.params.id);
      if (!endpoint) {
        res.status(404).json({ error: 'Unknown endpoint id' });
        return;
      }

      res.json({
        status: 'reset',
        id: req.params.id,
        endpoints: whipServer.listEndpoints()
      });
    } catch (error) {
      console.error(`Failed to reset endpoint ${req.params.id}:`, error);
      res.status(500).json({ error: 'Endpoint reset failed' });
    }
  });

  app.post('/api/streams', async (req, res) => {
    applyCorsHeaders(req, res, allowedOrigins);

    const authResult = await verifyNip98Request(req);
    if (!authResult.ok) {
      res.status(authResult.status).json({ success: false, message: authResult.error });
      return;
    }

    let subscription;
    try {
      subscription = await fetchSubscriptionStatus(authResult.event.pubkey, accountApiBase);
    } catch (error) {
      console.error('Subscription lookup failed:', error);
      res.status(502).json({ success: false, message: 'Subscription lookup failed' });
      return;
    }

    const subscriptionTier = String(subscription?.result?.tier || '').toLowerCase();
    if (!subscription?.success || !subscription?.result?.isActive || !subscriptionTier.startsWith('premium')) {
      res.status(403).json({ success: false, message: 'Active premium subscription required' });
      return;
    }

    const dynamicEndpoint = createDynamicEndpoint(authResult.event.pubkey);
    res.status(201).json({
      success: true,
      result: {
        pubkey: authResult.event.pubkey,
        subscriptionTier: subscription.result.tier,
        stream: buildDynamicEndpointResponse(req, dynamicEndpoint)
      }
    });
  });

  const httpServer = http.createServer({}, app);

  whipServer = new JanusWhipServer({
    janus: {
      address: janusWsUrl
    },
    rest: {
      app,
      basePath
    },
    allowTrickle: parseBoolean(process.env.WHIP_ALLOW_TRICKLE, true),
    strictETags: parseBoolean(process.env.WHIP_STRICT_ETAGS, false),
    iceServers,
    debug: debugLevel
  });

  whipServer.on('janus-disconnected', () => {
    console.log('WHIP server lost connection to Janus');
  });
  whipServer.on('janus-reconnected', () => {
    console.log('WHIP server reconnected to Janus');
  });
  whipServer.on('endpoint-active', id => {
    console.log(`[${id}] endpoint active`);
  });
  whipServer.on('endpoint-inactive', id => {
    console.log(`[${id}] endpoint inactive`);
  });

  await whipServer.start();

  console.log(`Resolved ${iceServers.length} ICE server entries for WHIP and watch clients`);

  endpointDefinitions.forEach(createManagedEndpoint);

  await new Promise((resolve, reject) => {
    httpServer.once('error', reject);
    httpServer.listen(httpPort, '0.0.0.0', resolve);
  });

  console.log(`WHIP server listening on http://0.0.0.0:${httpPort}${basePath}/endpoint/${endpointId}`);
  console.log(`Browser WHIP endpoint listening on http://0.0.0.0:${httpPort}${basePath}/endpoint/${browserEndpointId}`);

  const shutdown = async signal => {
    console.log(`Received ${signal}, shutting down`);
    httpServer.close();
    await whipServer.destroy().catch(error => {
      console.error('Error while stopping WHIP server:', error);
    });
    process.exit(0);
  };

  process.on('SIGINT', () => {
    void shutdown('SIGINT');
  });
  process.on('SIGTERM', () => {
    void shutdown('SIGTERM');
  });
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});