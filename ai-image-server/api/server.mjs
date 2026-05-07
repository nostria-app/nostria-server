import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const app = express();
const port = Number(process.env.PORT || 8090);
const apiKey = process.env.IMAGE_API_KEY || '';
const comfyBaseUrl = process.env.COMFYUI_BASE_URL || 'http://comfyui:8188';
const modelRoot = process.env.MODEL_ROOT || '/models';
const publicDir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'public');
const comfyHostnames = new Set(
  String(process.env.COMFYUI_HOSTNAMES || 'comfy.nostria.app')
    .split(',')
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean)
);

const comfyProxy = createProxyMiddleware({
  target: comfyBaseUrl,
  changeOrigin: true,
  ws: true,
  xfwd: true
});

const comfyPrefixedProxy = createProxyMiddleware({
  target: comfyBaseUrl,
  changeOrigin: true,
  pathRewrite: { '^/comfy': '' },
  ws: true,
  xfwd: true
});

const comfyRootPaths = [
  '/api',
  '/assets',
  '/customnode',
  '/embeddings',
  '/extensions',
  '/history',
  '/internal',
  '/interrupt',
  '/manager',
  '/models',
  '/object_info',
  '/prompt',
  '/queue',
  '/settings',
  '/system_stats',
  '/upload',
  '/user',
  '/userdata',
  '/view',
  '/workflow_templates',
  '/ws'
];

const presets = [
  {
    id: 'flux1-schnell',
    name: 'FLUX.1 schnell',
    available: true,
    workflowType: 'native-flux',
    unetName: 'flux1-schnell.safetensors',
    clipName1: 'clip_l.safetensors',
    clipName2: 't5xxl_fp8_e4m3fn.safetensors',
    vaeName: 'ae.safetensors',
    width: 1024,
    height: 1024,
    steps: 4,
    cfg: 1,
    guidance: 3.5,
    sampler: 'euler',
    scheduler: 'simple'
  },
  {
    id: 'flux2-klein',
    name: 'FLUX.2 klein 4B',
    available: false,
    unavailableReason: 'FLUX.2 klein uses a newer transformer layout that needs a dedicated ComfyUI workflow. Use Advanced Workflow for now.',
    modelPath: 'flux2-klein',
    width: 1024,
    height: 1024,
    steps: 8,
    cfg: 1,
    guidance: 3.5,
    sampler: 'euler',
    scheduler: 'simple'
  },
  {
    id: 'z-image-turbo',
    name: 'Z-Image-Turbo',
    available: false,
    unavailableReason: 'Z-Image-Turbo is downloaded, but this ComfyUI stack cannot run it through the deprecated DiffusersLoader. Use Advanced Workflow after adding a Z-Image-native graph.',
    modelPath: 'z-image-turbo',
    width: 1024,
    height: 1024,
    steps: 8,
    cfg: 1,
    guidance: 3.5,
    sampler: 'euler',
    scheduler: 'simple'
  }
];

function requireAuth(request, response, next) {
  if (!apiKey) {
    response.status(503).json({ error: 'IMAGE_API_KEY is not configured' });
    return;
  }

  if (isAuthorized(request)) {
    next();
    return;
  }

  response.status(401).json({ error: 'Unauthorized' });
}

function isAuthorized(request) {
  const authorization = getHeader(request, 'authorization');
  const bearer = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  const headerKey = getHeader(request, 'x-api-key');
  const cookieKey = getCookie(request, 'nostria_image_api_key');

  return Boolean(apiKey) && (bearer === apiKey || headerKey === apiKey || cookieKey === apiKey);
}

function getHeader(request, name) {
  if (typeof request.get === 'function') {
    return request.get(name) || '';
  }

  return String(request.headers?.[name.toLowerCase()] || '');
}

function getCookie(request, name) {
  const cookies = getHeader(request, 'cookie');
  for (const cookie of cookies.split(';')) {
    const [rawKey, ...rawValue] = cookie.trim().split('=');
    if (rawKey === name) {
      return decodeURIComponent(rawValue.join('='));
    }
  }

  return '';
}

function setSessionCookie(request, response, value) {
  const secure = request.secure || request.get('x-forwarded-proto') === 'https';
  const cookie = [
    `nostria_image_api_key=${encodeURIComponent(value)}`,
    'Path=/',
    'HttpOnly',
    'SameSite=Lax',
    'Max-Age=2592000'
  ];

  if (secure) {
    cookie.push('Secure');
  }

  response.setHeader('Set-Cookie', cookie.join('; '));
}

function clearSessionCookie(response) {
  response.setHeader('Set-Cookie', 'nostria_image_api_key=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0');
}

function sanitizeRedirect(value, fallback = '/comfy') {
  const redirect = String(value || fallback);
  if (!redirect.startsWith('/') || redirect.startsWith('//')) {
    return fallback;
  }

  return redirect;
}

function renderComfyLogin(response, redirect = '/comfy', error = '') {
  response.setHeader('Cache-Control', 'no-store');
  response.status(error ? 401 : 200).type('html').send(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Nostria ComfyUI Access</title>
  <style>
    :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #101310; color: #eef2eb; }
    body { min-height: 100vh; display: grid; place-items: center; margin: 0; padding: 24px; }
    main { width: min(420px, 100%); display: grid; gap: 18px; }
    h1 { margin: 0; font-size: 1.45rem; font-weight: 700; }
    p { margin: 0; color: #b7c0b2; line-height: 1.5; }
    form { display: grid; gap: 12px; }
    label { display: grid; gap: 8px; color: #dbe5d6; font-size: .92rem; }
    input { border: 1px solid #394334; border-radius: 6px; padding: 12px; background: #171c16; color: #eef2eb; font: inherit; }
    button { border: 0; border-radius: 6px; padding: 12px 14px; background: #91d66f; color: #10200a; font: inherit; font-weight: 700; cursor: pointer; }
    .error { color: #ffb0a2; }
  </style>
</head>
<body>
  <main>
    <h1>Nostria ComfyUI Access</h1>
    <p>Enter the image API key to open ComfyUI and view generated images.</p>
    ${error ? `<p class="error">${error}</p>` : ''}
    <form method="post" action="/comfy/session">
      <input type="hidden" name="redirect" value="${redirect.replaceAll('&', '&amp;').replaceAll('"', '&quot;')}">
      <label>
        API key
        <input name="apiKey" type="password" autocomplete="current-password" autofocus required>
      </label>
      <button type="submit">Continue</button>
    </form>
  </main>
</body>
</html>`);
}

function requireComfyAuth(request, response, next) {
  if (isAuthorized(request)) {
    response.setHeader('Cache-Control', 'no-store');
    next();
    return;
  }

  const queryKey = String(request.query.api_key || request.query.key || '');
  if (apiKey && queryKey === apiKey) {
    const redirectUrl = new URL(request.originalUrl, 'http://localhost');
    redirectUrl.searchParams.delete('api_key');
    redirectUrl.searchParams.delete('key');
    setSessionCookie(request, response, queryKey);
    response.redirect(303, sanitizeRedirect(`${redirectUrl.pathname}${redirectUrl.search}`));
    return;
  }

  const acceptsHtml = request.method === 'GET' && (request.accepts(['html', 'json', 'text']) === 'html');
  const isDocumentRequest = acceptsHtml && (!request.get('sec-fetch-dest') || request.get('sec-fetch-dest') === 'document');
  if (isDocumentRequest && (request.path === '/' || request.path === '/comfy' || request.path === '/comfy/')) {
    renderComfyLogin(response, sanitizeRedirect(request.originalUrl));
    return;
  }

  if (isDocumentRequest) {
    response.redirect(303, `/comfy/access?redirect=${encodeURIComponent(sanitizeRedirect(request.originalUrl))}`);
    return;
  }

  response.status(401).type('text').send('Unauthorized');
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

function numberInRange(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return fallback;
  }

  return Math.min(max, Math.max(min, number));
}

function safeSeed(value) {
  const number = Number(value);
  if (Number.isSafeInteger(number) && number >= 0) {
    return number;
  }

  return Math.floor(Math.random() * 1000000000000);
}

function buildFluxWorkflow(options) {
  const preset = presets.find((item) => item.id === options.model) || presets[0];
  const width = numberInRange(options.width, preset.width, 256, 2048);
  const height = numberInRange(options.height, preset.height, 256, 2048);
  const steps = numberInRange(options.steps, preset.steps, 1, 80);
  const cfg = numberInRange(options.cfg, preset.cfg, 0, 20);
  const guidance = numberInRange(options.guidance, preset.guidance, 0, 20);
  const seed = safeSeed(options.seed);
  const prompt = String(options.prompt || '').trim();
  const negativePrompt = String(options.negativePrompt || '').trim();
  const referenceImage = options.referenceImage && typeof options.referenceImage === 'object' ? options.referenceImage : null;
  const referenceStrength = numberInRange(options.referenceStrength, 0.65, 0.05, 1);

  if (!preset.available) {
    throw new Error(preset.unavailableReason || `${preset.name} is not available for one-click generation yet.`);
  }

  if (!prompt) {
    throw new Error('Prompt is required');
  }

  const workflow = {
    '1': {
      class_type: 'UNETLoader',
      inputs: {
        unet_name: preset.unetName,
        weight_dtype: 'default'
      }
    },
    '2': {
      class_type: 'DualCLIPLoader',
      inputs: {
        clip_name1: preset.clipName1,
        clip_name2: preset.clipName2,
        type: 'flux',
        device: 'default'
      }
    },
    '3': {
      class_type: 'VAELoader',
      inputs: { vae_name: preset.vaeName }
    },
    '4': {
      class_type: 'ModelSamplingFlux',
      inputs: {
        model: ['1', 0],
        max_shift: 1.15,
        base_shift: 0.5,
        width,
        height
      }
    },
    '5': {
      class_type: 'CLIPTextEncodeFlux',
      inputs: {
        clip: ['2', 0],
        clip_l: prompt,
        t5xxl: prompt,
        guidance
      }
    },
    '6': {
      class_type: 'CLIPTextEncodeFlux',
      inputs: {
        clip: ['2', 0],
        clip_l: negativePrompt,
        t5xxl: negativePrompt,
        guidance
      }
    },
    '8': {
      class_type: 'KSampler',
      inputs: {
        model: ['4', 0],
        seed,
        steps,
        cfg,
        sampler_name: String(options.sampler || preset.sampler),
        scheduler: String(options.scheduler || preset.scheduler),
        positive: ['5', 0],
        negative: ['6', 0],
        latent_image: ['7', 0],
        denoise: 1
      }
    },
    '9': {
      class_type: 'VAEDecode',
      inputs: { samples: ['8', 0], vae: ['3', 0] }
    },
    '10': {
      class_type: 'SaveImage',
      inputs: { images: ['9', 0], filename_prefix: 'nostria' }
    }
  };

  if (referenceImage?.filename || referenceImage?.name) {
    const filename = String(referenceImage.filename || referenceImage.name);
    const subfolder = String(referenceImage.subfolder || '').replace(/^\/+|\/+$/g, '');
    const imageName = subfolder ? `${subfolder}/${filename}` : filename;

    workflow['7'] = {
      class_type: 'LoadImage',
      inputs: { image: imageName }
    };
    workflow['11'] = {
      class_type: 'ImageScale',
      inputs: {
        image: ['7', 0],
        upscale_method: 'lanczos',
        width,
        height,
        crop: 'center'
      }
    };
    workflow['12'] = {
      class_type: 'VAEEncode',
      inputs: { pixels: ['11', 0], vae: ['3', 0] }
    };
    workflow['8'].inputs.latent_image = ['12', 0];
    workflow['8'].inputs.denoise = referenceStrength;
  } else {
    workflow['7'] = {
      class_type: 'EmptyLatentImage',
      inputs: { width, height, batch_size: 1 }
    };
  }

  return {
    workflow,
    seed,
    preset,
    referenceImage: referenceImage || undefined,
    referenceStrength: referenceImage ? referenceStrength : undefined
  };
}

async function submitPrompt(workflow) {
  const upstream = await fetch(`${comfyBaseUrl}/prompt`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ prompt: workflow })
  });

  const body = await upstream.json().catch(async () => ({ error: await upstream.text() }));
  return { status: upstream.status, body };
}

function isComfyHost(request) {
  const host = String(request.hostname || getHeader(request, 'host')).split(':')[0].toLowerCase();
  return comfyHostnames.has(host);
}

function requestPath(request) {
  return new URL(request.url || '/', 'http://localhost').pathname;
}

function isComfyRootPath(requestPath) {
  return comfyRootPaths.some((rootPath) => requestPath === rootPath || requestPath.startsWith(`${rootPath}/`));
}

function rejectWebSocket(socket, statusCode = 401, message = 'Unauthorized') {
  socket.write([
    `HTTP/1.1 ${statusCode} ${message}`,
    'Connection: close',
    'Content-Type: text/plain; charset=utf-8',
    `Content-Length: ${Buffer.byteLength(message)}`,
    '',
    message
  ].join('\r\n'));
  socket.destroy();
}

function disableWebSocketCompression(request) {
  delete request.headers['sec-websocket-extensions'];
}

function handleComfyUpgrade(request, socket, head) {
  const pathName = requestPath(request);
  const isPrefixedComfy = pathName === '/comfy/ws' || pathName.startsWith('/comfy/ws/');
  const isRootComfy = isComfyHost(request) || pathName === '/ws' || pathName.startsWith('/ws/');

  if (!isPrefixedComfy && !isRootComfy) {
    socket.destroy();
    return;
  }

  if (!isAuthorized(request)) {
    rejectWebSocket(socket);
    return;
  }

  disableWebSocketCompression(request);

  if (isPrefixedComfy) {
    request.url = request.url.replace(/^\/comfy(?=\/|$)/, '') || '/';
    comfyPrefixedProxy.upgrade(request, socket, head);
    return;
  }

  comfyProxy.upgrade(request, socket, head);
}

app.post('/comfy/session', express.urlencoded({ extended: false, limit: '10kb' }), (request, response) => {
  const submittedKey = String(request.body?.apiKey || '');
  if (!apiKey || submittedKey !== apiKey) {
    renderComfyLogin(response, sanitizeRedirect(request.body?.redirect), 'Invalid API key');
    return;
  }

  setSessionCookie(request, response, submittedKey);
  response.redirect(303, sanitizeRedirect(request.body?.redirect));
});

app.get('/comfy/access', (request, response) => {
  renderComfyLogin(response, sanitizeRedirect(request.query.redirect));
});

app.get('/comfy/logout', (_request, response) => {
  clearSessionCookie(response);
  response.redirect(303, '/comfy/access');
});

app.use((request, response, next) => {
  if (isComfyHost(request) && !request.path.startsWith('/v1/') && request.path !== '/health') {
    requireComfyAuth(request, response, () => comfyProxy(request, response, next));
    return;
  }

  next();
});

app.use((request, response, next) => {
  if (isComfyRootPath(request.path)) {
    requireComfyAuth(request, response, () => comfyProxy(request, response, next));
    return;
  }

  next();
});

app.use('/comfy', requireComfyAuth, comfyPrefixedProxy);

app.use(express.static(publicDir, { extensions: ['html'] }));

app.get('/health', async (_request, response) => {
  try {
    const upstream = await fetch(`${comfyBaseUrl}/system_stats`);
    response.status(upstream.ok ? 200 : 502).json({ ok: upstream.ok, comfyui: upstream.status });
  } catch (error) {
    response.status(502).json({ ok: false, error: error.message });
  }
});

app.post('/v1/session', express.json({ limit: '10kb' }), (request, response) => {
  const submittedKey = String(request.body?.apiKey || '');
  if (!apiKey || submittedKey !== apiKey) {
    response.status(401).json({ error: 'Unauthorized' });
    return;
  }

  setSessionCookie(request, response, submittedKey);
  response.json({ ok: true });
});

app.delete('/v1/session', (_request, response) => {
  clearSessionCookie(response);
  response.json({ ok: true });
});

app.get('/v1/ui-config', requireAuth, async (_request, response) => {
  response.json({ presets });
});

app.get('/v1/models', requireAuth, async (_request, response) => {
  try {
    const files = await listFiles(modelRoot);
    response.json({ object: 'list', data: files });
  } catch (error) {
    response.status(500).json({ error: error.message });
  }
});

app.post('/v1/generate', requireAuth, express.json({ limit: '1mb' }), async (request, response) => {
  try {
    const { workflow, seed, preset, referenceImage, referenceStrength } = buildFluxWorkflow(request.body || {});
    const upstream = await submitPrompt(workflow);
    response.status(upstream.status).json({ ...upstream.body, seed, preset: preset.id, referenceImage, referenceStrength, workflow });
  } catch (error) {
    response.status(400).json({ error: error.message });
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

const server = app.listen(port, '0.0.0.0', () => {
  console.log(`AI image API gateway listening on ${port}`);
});

server.on('upgrade', handleComfyUpgrade);