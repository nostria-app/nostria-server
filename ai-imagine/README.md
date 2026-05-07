# AI Imagine

This service runs [`stable-diffusion.cpp`](https://github.com/leejet/stable-diffusion.cpp) as the local/LAN image generation backend for Nostria. It replaces the previous ComfyUI-based container stack and uses `sd-server`, which is similar in spirit to `llama.cpp`: a small C/C++ server with an embedded web UI and image-generation APIs.

The service is intentionally not exposed through Cloudflare. It binds to `0.0.0.0:8090` by default so it is available locally and on the LAN at:

```text
http://127.0.0.1:8090/
http://192.168.1.211:8090/
```

## Files

- `Dockerfile`: builds a CPU `sd-cli`/`sd-server` image from `leejet/stable-diffusion.cpp`
- `docker-compose.yml`: runs the local image with `/sd-server`
- `public/index.html`: LAN UI for portrait edits, text-to-image, image editing, references, masks, high-res options, LoRA, and async jobs
- `public/model-presets.json`: model catalog source mirrored by the embedded UI preset list
- `.env.example`: host bind, image tag, and default model/runtime arguments
- `scripts/bootstrap.sh`: creates the persistent data tree, imports existing FLUX.1 weights when present, pulls the image, and starts the service
- `scripts/download-model.sh`: downloads supported image and edit model presets, or a custom Hugging Face repo
- `scripts/switch-model.sh`: updates `.env` to a downloaded model preset and restarts `sd-server`
- `scripts/status.sh`: prints Compose status, resource usage, and local UI headers

## Data Layout

Persistent data lives under `/mnt/data/openresist/ai-imagine`:

- `models/`: model, VAE, text encoder, and GGUF files
- `output/`: generated outputs, when the server writes files
- `cache/huggingface/`: Hugging Face download cache

On first bootstrap, the script links reusable FLUX.1 schnell files from `/mnt/data/openresist/ai-image-server/models` if they exist. The Compose file mounts that legacy model tree read-only so those links resolve inside the container without duplicating large model files.

## Start

```bash
cd /home/blockcore/src/nostria/nostria-server/ai-imagine
bash ./scripts/bootstrap.sh
```

Then open:

```text
http://192.168.1.211:8090/
```

The server exposes:

- Nostria Imagine UI at `/`
- Native async API under `/sdcpp/v1/...`
- OpenAI-compatible image API under `/v1/...`
- Stable Diffusion WebUI-compatible API under `/sdapi/v1/...`

The UI uses the native async `/sdcpp/v1/img_gen` endpoint. It can submit normal text-to-image requests, image-to-image edits through `init_image`, reference images through `ref_images`, masks through `mask_image`, and control images through `control_image` when the loaded model supports those paths.

The Portrait mode is a simplified one-photo workflow for head-shot and full-body identity-guided generation. It shows a photo upload, prompt field, and compact model picker. The uploaded photo is sent as a reference image rather than as the source canvas, so compatible edit/reference models can create a new photo guided by the person's face instead of simply repainting the same input. Hidden defaults use a portrait aspect ratio, one PNG output, realistic-photo prompting, identity-preserving negative prompting, and no mask/control/high-res/LoRA inputs.

Selecting a model in Portrait mode changes the UI defaults and shows the matching switch command. The website intentionally cannot execute the switch directly: allowing a LAN browser page to restart containers or rewrite `.env` would be a broad host-control surface. The running `sd-server` model changes only after running `scripts/switch-model.sh <preset>` on the host, because `stable-diffusion.cpp` loads models at startup.

## Default Model

The default `.env.example` points at FLUX.1 schnell:

```text
--diffusion-model /models/diffusion_models/flux1-schnell.safetensors
--vae /models/vae/ae.safetensors
--clip_l /models/text_encoders/clip_l.safetensors
--t5xxl /models/text_encoders/t5xxl_fp8_e4m3fn.safetensors
```

It also uses CPU-friendly defaults:

```text
--threads 10 --mmap --clip-on-cpu --vae-on-cpu --offload-to-cpu --lora-model-dir /models/loras --hires-upscalers-dir /models/upscalers
--cfg-scale 1.0 --sampling-method euler --steps 4 -W 1024 -H 1024 -v
```

Edit `.env` and rerun `docker compose up -d stable-diffusion-cpp` to change models or tuning. Change `SDCPP_REF` before `bootstrap.sh` if you want to pin a specific upstream commit, branch, or tag.

## Download Models

Download FLUX.1 schnell assets:

```bash
bash ./scripts/download-model.sh flux1-schnell
```

Common additional presets:

```bash
bash ./scripts/download-model.sh flux1-schnell-gguf
bash ./scripts/download-model.sh flux1-dev-gguf
bash ./scripts/download-model.sh flux1-kontext-dev
bash ./scripts/download-model.sh z-image-turbo
bash ./scripts/download-model.sh z-image-base
bash ./scripts/download-model.sh flux2-dev
bash ./scripts/download-model.sh flux2-klein-4b
bash ./scripts/download-model.sh flux2-klein-base-4b
bash ./scripts/download-model.sh qwen-image
bash ./scripts/download-model.sh qwen-image-edit
bash ./scripts/download-model.sh qwen-image-edit-2509
bash ./scripts/download-model.sh chroma
bash ./scripts/download-model.sh ernie-image-turbo
bash ./scripts/download-model.sh sdxl-base
bash ./scripts/download-model.sh sd15
```

Some repositories are gated. Set `HF_TOKEN` in the shell or in `.env` before running downloads.

For GGUF repositories, the optional second argument is passed as a Hugging Face `--include` pattern:

```bash
bash ./scripts/download-model.sh z-image-turbo '*Q3_K*.gguf'
bash ./scripts/download-model.sh flux2-klein-4b '*Q4_K_M*.gguf'
```

## Switch Models

`stable-diffusion.cpp` loads the model at server startup, so changing model presets requires a container restart. The UI shows preset commands, and the host script applies them:

```bash
bash ./scripts/switch-model.sh z-image-turbo
bash ./scripts/switch-model.sh flux1-kontext-dev
bash ./scripts/switch-model.sh qwen-image-edit-2509
```

The script updates `SDCPP_MODEL_PRESET`, `SDCPP_MODEL_ARGS`, `SDCPP_DEFAULT_ARGS`, and `SDCPP_EXTRA_ARGS` in `.env`, then restarts the Compose service.

Qwen Image, Qwen Image Edit, and Qwen Image Edit 2509 are currently blocked by `scripts/switch-model.sh` on this host. The downloaded Qwen VAE loads with a tensor namespace mismatch in the current `stable-diffusion.cpp` backend (`first_stage_model.*` tensors are expected but not found), which otherwise puts the container into a crash loop. Use `flux1-kontext-dev` for photo/reference editing until a compatible Qwen VAE/binary combination is available.

Model presets currently exposed by the UI mirror `public/model-presets.json`. `sd-server` only serves the configured HTML file, so the page uses an embedded copy of the same catalog. The UI can apply client-side defaults immediately, but the running backend only changes after `scripts/switch-model.sh` restarts `sd-server` with the selected preset.

## Stop

```bash
docker compose down
```

## Cloudflare

No Cloudflare tunnel route should point at this service while it is LAN-only. The public image hostnames should remain disabled or return 404.