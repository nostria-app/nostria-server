const state = {
  apiKey: localStorage.getItem('nostria.imageApiKey') || '',
  currentPromptId: '',
  pollTimer: 0,
  presets: []
};

const elements = {
  apiKey: document.querySelector('#apiKey'),
  saveKeyButton: document.querySelector('#saveKeyButton'),
  clearKeyButton: document.querySelector('#clearKeyButton'),
  healthBadge: document.querySelector('#healthBadge'),
  modelFiles: document.querySelector('#modelFiles'),
  model: document.querySelector('#model'),
  size: document.querySelector('#size'),
  prompt: document.querySelector('#prompt'),
  negativePrompt: document.querySelector('#negativePrompt'),
  steps: document.querySelector('#steps'),
  guidance: document.querySelector('#guidance'),
  cfg: document.querySelector('#cfg'),
  seed: document.querySelector('#seed'),
  referenceImage: document.querySelector('#referenceImage'),
  referenceStrength: document.querySelector('#referenceStrength'),
  referencePreview: document.querySelector('#referencePreview'),
  clearReferenceButton: document.querySelector('#clearReferenceButton'),
  generatorForm: document.querySelector('#generatorForm'),
  generateButton: document.querySelector('#generateButton'),
  randomSeedButton: document.querySelector('#randomSeedButton'),
  jobStatus: document.querySelector('#jobStatus'),
  gallery: document.querySelector('#gallery'),
  refreshButton: document.querySelector('#refreshButton'),
  workflowJson: document.querySelector('#workflowJson'),
  submitWorkflowButton: document.querySelector('#submitWorkflowButton'),
  clearWorkflowButton: document.querySelector('#clearWorkflowButton')
};

function setStatus(message) {
  elements.jobStatus.textContent = message;
}

async function uploadReferenceImage() {
  const file = elements.referenceImage.files?.[0];
  if (!file) {
    return null;
  }

  const formData = new FormData();
  formData.append('image', file);
  formData.append('type', 'input');
  formData.append('overwrite', 'true');

  return apiFetch('/comfy/upload/image', {
    method: 'POST',
    body: formData
  });
}

function updateReferencePreview() {
  const file = elements.referenceImage.files?.[0];
  if (!file) {
    elements.referencePreview.removeAttribute('src');
    elements.referencePreview.alt = '';
    return;
  }

  elements.referencePreview.src = URL.createObjectURL(file);
  elements.referencePreview.alt = file.name;
}

function authHeaders() {
  return state.apiKey ? { Authorization: `Bearer ${state.apiKey}` } : {};
}

async function apiFetch(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      ...authHeaders(),
      ...(options.headers || {})
    }
  });

  const contentType = response.headers.get('content-type') || '';
  const body = contentType.includes('application/json') ? await response.json() : await response.text();
  if (!response.ok) {
    const message = typeof body === 'object'
      ? typeof body.error === 'string' ? body.error : JSON.stringify(body.error || body)
      : body;
    throw new Error(message || `Request failed with ${response.status}`);
  }

  return body;
}

function formatBytes(bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  let value = Number(bytes) || 0;
  let index = 0;
  while (value > 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  return `${value.toFixed(index === 0 ? 0 : 1)} ${units[index]}`;
}

function renderModels(files) {
  if (!files.length) {
    elements.modelFiles.textContent = 'No model files found yet.';
    return;
  }

  elements.modelFiles.replaceChildren(...files.slice(0, 18).map((file) => {
    const row = document.createElement('div');
    row.className = 'file-row';
    const name = document.createElement('strong');
    name.textContent = file.path;
    const size = document.createElement('span');
    size.textContent = formatBytes(file.bytes);
    row.append(name, size);
    return row;
  }));
}

function renderPresets(presets) {
  state.presets = presets;
  elements.model.replaceChildren(...presets.map((preset) => {
    const option = document.createElement('option');
    option.value = preset.id;
    option.textContent = preset.available === false ? `${preset.name} (Advanced Workflow)` : preset.name;
    option.disabled = preset.available === false;
    option.title = preset.unavailableReason || '';
    return option;
  }));

  if (state.presets.every((preset) => preset.id !== elements.model.value || preset.available === false)) {
    const firstAvailable = state.presets.find((preset) => preset.available !== false);
    if (firstAvailable) {
      elements.model.value = firstAvailable.id;
    }
  }

  applyPreset();
}

function applyPreset() {
  const preset = state.presets.find((item) => item.id === elements.model.value);
  if (!preset) {
    return;
  }

  elements.steps.value = preset.steps;
  elements.guidance.value = preset.guidance;
  elements.cfg.value = preset.cfg;
  elements.size.value = `${preset.width}x${preset.height}`;
  elements.generateButton.disabled = preset.available === false;
  if (preset.available === false) {
    setStatus(preset.unavailableReason || 'Use Advanced Workflow for this model');
  }
}

async function loadConfig() {
  if (!state.apiKey) {
    renderPresets([
      { id: 'flux1-schnell', name: 'FLUX.1 schnell', width: 1024, height: 1024, steps: 4, guidance: 3.5, cfg: 1 },
      { id: 'flux2-klein', name: 'FLUX.2 klein 4B', available: false, width: 1024, height: 1024, steps: 8, guidance: 3.5, cfg: 1 },
      { id: 'z-image-turbo', name: 'Z-Image-Turbo', available: false, width: 1024, height: 1024, steps: 8, guidance: 3.5, cfg: 1 }
    ]);
    return;
  }

  const config = await apiFetch('/v1/ui-config');
  renderPresets(config.presets || []);
}

async function loadModels() {
  if (!state.apiKey) {
    elements.modelFiles.textContent = 'Add the API key to load model files.';
    return;
  }

  const data = await apiFetch('/v1/models');
  renderModels(data.data || data.models || []);
}

async function checkHealth() {
  try {
    const health = await apiFetch('/health');
    elements.healthBadge.textContent = health.ok ? 'Ready' : 'ComfyUI issue';
    elements.healthBadge.className = `badge ${health.ok ? 'ok' : 'error'}`;
  } catch (error) {
    elements.healthBadge.textContent = 'Offline';
    elements.healthBadge.className = 'badge error';
  }
}

function imageUrl(image) {
  const query = new URLSearchParams({
    filename: image.filename,
    subfolder: image.subfolder || '',
    type: image.type || 'output'
  });
  return `/v1/view?${query}`;
}

function extractImages(history) {
  const images = [];
  for (const entry of Object.values(history || {})) {
    for (const output of Object.values(entry.outputs || {})) {
      for (const image of output.images || []) {
        images.push(image);
      }
    }
  }
  return images;
}

function renderGallery(images) {
  if (!images.length) {
    elements.gallery.className = 'gallery empty-state';
    elements.gallery.textContent = 'No images for this job yet.';
    return;
  }

  elements.gallery.className = 'gallery';
  elements.gallery.replaceChildren(...images.map((image) => {
    const card = document.createElement('article');
    card.className = 'image-card';
    const img = document.createElement('img');
    const url = imageUrl(image);
    img.src = url;
    img.alt = image.filename;
    const link = document.createElement('a');
    link.href = url;
    link.target = '_blank';
    link.rel = 'noreferrer';
    link.textContent = image.filename;
    card.append(img, link);
    return card;
  }));
}

async function refreshCurrentJob() {
  if (!state.currentPromptId) {
    setStatus('Idle');
    return;
  }

  const history = await apiFetch(`/v1/history/${encodeURIComponent(state.currentPromptId)}`);
  const images = extractImages(history);
  renderGallery(images);
  if (images.length) {
    window.clearInterval(state.pollTimer);
    state.pollTimer = 0;
    setStatus('Complete');
  } else {
    setStatus('Running');
  }
}

function startPolling() {
  window.clearInterval(state.pollTimer);
  state.pollTimer = window.setInterval(() => {
    refreshCurrentJob().catch((error) => setStatus(error.message));
  }, 4000);
}

async function submitGenerate(event) {
  event.preventDefault();
  if (!state.apiKey) {
    setStatus('Add API key first');
    elements.apiKey.focus();
    return;
  }

  elements.generateButton.disabled = true;
  try {
    const [width, height] = elements.size.value.split('x').map(Number);
    setStatus(elements.referenceImage.files?.[0] ? 'Uploading reference' : 'Submitting');
    const referenceImage = await uploadReferenceImage();
    const body = {
      model: elements.model.value,
      prompt: elements.prompt.value,
      negativePrompt: elements.negativePrompt.value,
      width,
      height,
      steps: Number(elements.steps.value),
      guidance: Number(elements.guidance.value),
      cfg: Number(elements.cfg.value),
      seed: elements.seed.value ? Number(elements.seed.value) : undefined,
      referenceImage,
      referenceStrength: Number(elements.referenceStrength.value)
    };

    setStatus('Submitting');
    const result = await apiFetch('/v1/generate', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body)
    });
    state.currentPromptId = result.prompt_id || result.promptId || '';
    elements.seed.value = result.seed || '';
    elements.workflowJson.value = JSON.stringify(result.workflow || {}, null, 2);
    setStatus(state.currentPromptId ? 'Queued' : 'Submitted');
    await refreshCurrentJob();
    startPolling();
  } catch (error) {
    setStatus(error.message);
  } finally {
    elements.generateButton.disabled = false;
  }
}

async function submitWorkflow() {
  if (!state.apiKey) {
    setStatus('Add API key first');
    return;
  }

  let prompt;
  try {
    prompt = JSON.parse(elements.workflowJson.value);
  } catch (error) {
    setStatus('Workflow JSON is invalid');
    return;
  }

  setStatus('Submitting workflow');
  try {
    const result = await apiFetch('/v1/prompt', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ prompt })
    });
    state.currentPromptId = result.prompt_id || '';
    await refreshCurrentJob();
    startPolling();
  } catch (error) {
    setStatus(error.message);
  }
}

function saveKey() {
  state.apiKey = elements.apiKey.value.trim();
  if (state.apiKey) {
    localStorage.setItem('nostria.imageApiKey', state.apiKey);
  }
  apiFetch('/v1/session', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ apiKey: state.apiKey })
  })
    .then(() => initializeAuthedData())
    .catch((error) => setStatus(error.message));
}

function clearKey() {
  state.apiKey = '';
  elements.apiKey.value = '';
  localStorage.removeItem('nostria.imageApiKey');
  fetch('/v1/session', { method: 'DELETE' }).catch(() => {});
  elements.modelFiles.textContent = 'Add the API key to load model files.';
  setStatus('Key cleared');
}

async function initializeAuthedData() {
  try {
    await loadConfig();
    await loadModels();
    setStatus(state.apiKey ? 'Ready' : 'Add API key');
  } catch (error) {
    setStatus(error.message);
  }
}

elements.apiKey.value = state.apiKey;
elements.saveKeyButton.addEventListener('click', saveKey);
elements.clearKeyButton.addEventListener('click', clearKey);
elements.generatorForm.addEventListener('submit', submitGenerate);
elements.model.addEventListener('change', applyPreset);
elements.randomSeedButton.addEventListener('click', () => {
  elements.seed.value = Math.floor(Math.random() * 1000000000000);
});
elements.referenceImage.addEventListener('change', updateReferencePreview);
elements.clearReferenceButton.addEventListener('click', () => {
  elements.referenceImage.value = '';
  updateReferencePreview();
});
elements.refreshButton.addEventListener('click', () => refreshCurrentJob().catch((error) => setStatus(error.message)));
elements.submitWorkflowButton.addEventListener('click', submitWorkflow);
elements.clearWorkflowButton.addEventListener('click', () => {
  elements.workflowJson.value = '';
});

checkHealth();
if (state.apiKey) {
  saveKey();
} else {
  initializeAuthedData();
}