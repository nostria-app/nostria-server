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

const presets = [
  {
    id: 'flux1-schnell',
    name: 'FLUX.1 schnell',
    modelPath: 'flux1-schnell',
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

  const authorization = request.get('authorization') || '';
  const bearer = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  const headerKey = request.get('x-api-key') || '';
  const cookieKey = getCookie(request, 'nostria_image_api_key');

  if (bearer === apiKey || headerKey === apiKey || cookieKey === apiKey) {
    next();
    return;
  }

  response.status(401).json({ error: 'Unauthorized' });
}

function getCookie(request, name) {
  const cookies = request.get('cookie') || '';
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
  const modelPath = String(options.modelPath || preset.modelPath);
  const referenceImage = options.referenceImage && typeof options.referenceImage === 'object' ? options.referenceImage : null;
  const referenceStrength = numberInRange(options.referenceStrength, 0.65, 0.05, 1);

  if (!prompt) {
    throw new Error('Prompt is required');
  }

  const workflow = {
    '1': {
      class_type: 'DiffusersLoader',
      inputs: { model_path: modelPath }
    },
    '2': {
      class_type: 'ModelSamplingFlux',
      inputs: {
        model: ['1', 0],
        max_shift: 1.15,
        base_shift: 0.5,
        width,
        height
      }
    },
    '3': {
      class_type: 'CLIPTextEncodeFlux',
      inputs: {
        clip: ['1', 1],
        clip_l: prompt,
        t5xxl: prompt,
        guidance
      }
    },
    '4': {
      class_type: 'CLIPTextEncodeFlux',
      inputs: {
        clip: ['1', 1],
        clip_l: negativePrompt,
        t5xxl: negativePrompt,
        guidance
      }
    },
    '8': {
      class_type: 'KSampler',
      inputs: {
        model: ['2', 0],
        seed,
        steps,
        cfg,
        sampler_name: String(options.sampler || preset.sampler),
        scheduler: String(options.scheduler || preset.scheduler),
        positive: ['3', 0],
        negative: ['4', 0],
        latent_image: ['5', 0],
        denoise: 1
      }
    },
    '9': {
      class_type: 'VAEDecode',
      inputs: { samples: ['8', 0], vae: ['1', 2] }
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

    workflow['5'] = {
      class_type: 'LoadImage',
      inputs: { image: imageName }
    };
    workflow['6'] = {
      class_type: 'ImageScale',
      inputs: {
        image: ['5', 0],
        upscale_method: 'lanczos',
        width,
        height,
        crop: 'center'
      }
    };
    workflow['7'] = {
      class_type: 'VAEEncode',
      inputs: { pixels: ['6', 0], vae: ['1', 2] }
    };
    workflow['8'].inputs.latent_image = ['7', 0];
    workflow['8'].inputs.denoise = referenceStrength;
  } else {
    workflow['5'] = {
      class_type: 'EmptyFlux2LatentImage',
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
  response.setHeader('Set-Cookie', 'nostria_image_api_key=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0');
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

app.use('/comfy', requireAuth, createProxyMiddleware({
  target: comfyBaseUrl,
  changeOrigin: true,
  pathRewrite: { '^/comfy': '' },
  ws: true
}));

app.listen(port, '0.0.0.0', () => {
  console.log(`AI image API gateway listening on ${port}`);
});