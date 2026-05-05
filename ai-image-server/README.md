# AI Image Server

This deploys a local image-generation API for `ai-image.nostria.app` using ComfyUI behind a small API-key gateway. ComfyUI is a good fit for this server because model choice is part of the submitted workflow JSON, so clients can switch between Z-Image-Turbo, FLUX.2 klein, FLUX.1 schnell, and later models without restarting the container.

The local public-facing gateway listens on `127.0.0.1:8090` by default. ComfyUI itself is only exposed on the Docker network. Persistent data lives under `/mnt/data/openresist/ai-image-server`.

## Reality Check

Image diffusion models are much less friendly to CPU-only hosting than text GGUF models. Z-Image-Turbo and FLUX-sized models are best run with a CUDA GPU. CPU execution may work for some workflows, but it is usually very slow and can consume a lot of RAM.

FLUX.1 schnell and FLUX.2 klein on Hugging Face are gated and require accepting the model terms plus setting `HF_TOKEN` in `.env`. The default FLUX.2 target is `black-forest-labs/FLUX.2-klein-4B`.

## Files

- `docker-compose.yml`: ComfyUI plus API gateway service definition
- `Dockerfile.comfyui`: ComfyUI runtime image
- `Dockerfile.api`: API-key gateway image
- `.env.example`: runtime defaults and Hugging Face repo settings
- `api/server.mjs`: API-key gateway for ComfyUI REST endpoints
- `scripts/bootstrap.sh`: creates data dirs, creates `.env`, builds, and starts the service
- `scripts/download-model.sh`: downloads configured model files from Hugging Face
- `scripts/status.sh`: prints Compose status, resource use, disk use, and health

## Data Layout

All persistent data lives under `/mnt/data/openresist/ai-image-server`:

- `models/`: ComfyUI models directory
- `models/diffusers/`: downloaded diffusers-layout model repositories
- `models/diffusion_models/`, `models/text_encoders/`, `models/vae/`, `models/checkpoints/`: native ComfyUI model folders
- `input/`: uploaded or staged input images
- `output/`: generated images
- `user/`: ComfyUI user/workflow data
- `custom_nodes/`: custom ComfyUI nodes
- `cache/`: Hugging Face and Python model caches

## Bootstrap

Create the environment and data directories without building the large containers:

```bash
cd /home/blockcore/src/nostria/nostria-server/ai-image-server
bash ./scripts/bootstrap.sh --no-start
```

Start the service after you are ready:

```bash
bash ./scripts/bootstrap.sh
```

If this host has an NVIDIA GPU, install NVIDIA Container Toolkit and uncomment `gpus: all` in `docker-compose.yml` before starting.

## Download Models

Dry-run first so you can see the exact file count and size:

```bash
bash ./scripts/download-model.sh --dry-run z-image-turbo
```

Download Z-Image-Turbo:

```bash
bash ./scripts/download-model.sh z-image-turbo
```

Download FLUX.1 schnell after approving access on Hugging Face and setting `HF_TOKEN` in `.env`:

```bash
bash ./scripts/download-model.sh --dry-run flux1-schnell
bash ./scripts/download-model.sh flux1-schnell
```

Download FLUX.2 klein 4B after approving access on Hugging Face:

```bash
bash ./scripts/download-model.sh --dry-run flux2-klein
bash ./scripts/download-model.sh flux2-klein
```

## API Usage

The gateway requires the generated `IMAGE_API_KEY` from `.env` for all API routes except `/health`.

Health check:

```bash
curl http://127.0.0.1:8090/health
```

List downloaded model files:

```bash
curl http://127.0.0.1:8090/v1/models \
  -H "Authorization: Bearer $IMAGE_API_KEY"
```

Submit a ComfyUI workflow prompt:

```bash
curl http://127.0.0.1:8090/v1/prompt \
  -H "Authorization: Bearer $IMAGE_API_KEY" \
  -H 'Content-Type: application/json' \
  -d @workflow.json
```

Fetch prompt history:

```bash
curl http://127.0.0.1:8090/v1/history/<prompt-id> \
  -H "Authorization: Bearer $IMAGE_API_KEY"
```

Fetch an output image using the filename/subfolder/type returned by ComfyUI history:

```bash
curl "http://127.0.0.1:8090/v1/view?filename=<file>&subfolder=<subfolder>&type=output" \
  -H "Authorization: Bearer $IMAGE_API_KEY" \
  --output image.png
```

Advanced clients can proxy directly to ComfyUI through `/comfy/*` with the same API key.

## Model Switching

Yes, model switching is possible through the API. In ComfyUI, the selected model is part of the workflow graph. A client can submit one workflow that references Z-Image-Turbo files and another workflow that references FLUX.1 schnell files. The server does not need to restart; ComfyUI loads and unloads models according to the workflow and available memory.

This also means the API does not have a single global `current model` setting. Store tested workflow JSON files per model and submit the one you want for each request.

## Cloudflare Tunnel

Expose the local gateway through the existing Cloudflare helper:

```bash
cd /home/blockcore/src/nostria/nostria-server
sudo ./scripts/update-cloudflared-ingress.sh \
  --hostname ai-image.nostria.app \
  --service http://127.0.0.1:8090
```

Keep `IMAGE_API_KEY` enabled before exposing this publicly. For browser-based ComfyUI access, prefer Cloudflare Access as an additional gate.

## Operations

Show status:

```bash
bash ./scripts/status.sh
```

View logs:

```bash
docker logs -f openresist-ai-image-api
docker logs -f openresist-ai-image-comfyui
```

Restart after changing `.env`:

```bash
docker compose up -d --build
```

Stop the service:

```bash
docker compose down
```