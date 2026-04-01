import express from 'express';
import http from 'http';
import { JanusWhipServer } from 'janus-whip-server';

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
      .map(uri => ({ uri }));
  }

  try {
    const parsed = JSON.parse(trimmedValue);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch (error) {
    throw new Error(`Invalid WHIP_ICE_SERVERS JSON: ${error.message}`);
  }
}

function parseRoomId(value) {
  const roomId = Number.parseInt(value, 10);
  if (!Number.isInteger(roomId) || roomId <= 0) {
    throw new Error('WHIP_ROOM_ID must be a positive integer');
  }

  return roomId;
}

async function main() {
  const app = express();
  const httpPort = Number.parseInt(process.env.WHIP_PORT || '7080', 10);
  const basePath = process.env.WHIP_BASE_PATH || '/whip';
  const endpointId = process.env.WHIP_ENDPOINT_ID || 'live';
  const endpointLabel = process.env.WHIP_ENDPOINT_LABEL || 'OpenResist Live';
  const endpointToken = process.env.WHIP_ENDPOINT_TOKEN || undefined;
  const roomId = parseRoomId(process.env.WHIP_ROOM_ID || '1234');
  const janusWsUrl = process.env.JANUS_WS_URL || 'ws://janus:8188';
  const debugLevel = process.env.WHIP_DEBUG_LEVEL || 'info';
  const iceServers = parseIceServers(process.env.WHIP_ICE_SERVERS || '[]');

  let whipServer;

  app.get('/healthz', (_req, res) => {
    res.json({
      status: 'ok',
      janusWsUrl,
      basePath,
      endpointId,
      roomId,
      endpoints: whipServer ? whipServer.listEndpoints() : []
    });
  });

  app.get('/endpoints', (_req, res) => {
    res.json(whipServer ? whipServer.listEndpoints() : []);
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

  const endpoint = whipServer.createEndpoint({
    id: endpointId,
    room: roomId,
    label: endpointLabel,
    token: endpointToken
  });

  endpoint.on('endpoint-active', function onEndpointActive() {
    console.log(`[${this.id}] publisher connected`);
  });

  endpoint.on('endpoint-inactive', function onEndpointInactive() {
    console.log(`[${this.id}] publisher disconnected`);
  });

  await new Promise((resolve, reject) => {
    httpServer.once('error', reject);
    httpServer.listen(httpPort, '0.0.0.0', resolve);
  });

  console.log(`WHIP server listening on http://0.0.0.0:${httpPort}${basePath}/endpoint/${endpointId}`);

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