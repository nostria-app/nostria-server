import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { readdir, stat } from 'node:fs/promises';
import path from 'node:path';

const app = express();
const port = Number(process.env.PORT || 8090);
const apiKey = process.env.IMAGE_API_KEY || '';
const comfyBaseUrl = process.env.COMFYUI_BASE_URL || 'http://comfyui:8188';
const modelRoot = process.env.MODEL_ROOT || '/models';

function requireAuth(request, response, next) {
  if (!apiKey) {
    response.status(503).json({ error: 'IMAGE_API_KEY is not configured' });
    return;
  }

  const authorization = request.get('authorization') || '';
  const bearer = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  const headerKey = request.get('x-api-key') || '';

  if (bearer === apiKey || headerKey === apiKey) {
    next();
    return;
  }

  response.status(401).json({ error: 'Unauthorized' });
}

async function listFiles(directory, baseDirectory = directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    if (entry.name.startsWith('.')) {
      continue;
    }

    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await listFiles(fullPath, baseDirectory));
      continue;
    }

    if (!['.safetensors', '.gguf', '.pt', '.bin', '.ckpt'].includes(path.extname(entry.name))) {
      continue;
    }

    const info = await stat(fullPath);
    files.push({
      path: path.relative(baseDirectory, fullPath),
      bytes: info.size
    });
  }

  return files;
}

async function forwardJson(request, response, targetPath) {
  const upstream = await fetch(`${comfyBaseUrl}${targetPath}`, {
    method: request.method,
    headers: { 'content-type': 'application/json' },
    body: request.method === 'GET' ? undefined : JSON.stringify(request.body || {})
  });

  response.status(upstream.status);
  response.type(upstream.headers.get('content-type') || 'application/json');
  response.send(Buffer.from(await upstream.arrayBuffer()));
}

app.get('/health', async (_request, response) => {
  try {
    const upstream = await fetch(`${comfyBaseUrl}/system_stats`);
    response.status(upstream.ok ? 200 : 502).json({ ok: upstream.ok, comfyui: upstream.status });
  } catch (error) {
    response.status(502).json({ ok: false, error: error.message });
  }
});

app.get('/v1/models', requireAuth, async (_request, response) => {
  try {
    const files = await listFiles(modelRoot);
    response.json({ object: 'list', data: files });
  } catch (error) {
    response.status(500).json({ error: error.message });
  }
});

app.post('/v1/prompt', requireAuth, express.json({ limit: '50mb' }), async (request, response) => {
  await forwardJson(request, response, '/prompt');
});

async function forwardHistory(request, response) {
  const suffix = request.params.promptId ? `/${encodeURIComponent(request.params.promptId)}` : '';
  const upstream = await fetch(`${comfyBaseUrl}/history${suffix}`);
  response.status(upstream.status);
  response.type(upstream.headers.get('content-type') || 'application/json');
  response.send(Buffer.from(await upstream.arrayBuffer()));
}

app.get('/v1/history', requireAuth, forwardHistory);
app.get('/v1/history/:promptId', requireAuth, forwardHistory);

app.get('/v1/view', requireAuth, async (request, response) => {
  const query = new URLSearchParams(request.query).toString();
  const upstream = await fetch(`${comfyBaseUrl}/view?${query}`);
  response.status(upstream.status);
  response.type(upstream.headers.get('content-type') || 'application/octet-stream');
  response.send(Buffer.from(await upstream.arrayBuffer()));
});

app.use('/comfy', requireAuth, createProxyMiddleware({
  target: comfyBaseUrl,
  changeOrigin: true,
  pathRewrite: { '^/comfy': '' },
  ws: true
}));

app.listen(port, '0.0.0.0', () => {
  console.log(`AI image API gateway listening on ${port}`);
});