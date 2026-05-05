# AI Server

This deploys a local CPU-only llama.cpp API server for `ai.nostria.app` using `llama-server` and GGUF models. It exposes an OpenAI-compatible API locally on `127.0.0.1:8088` by default and stores all persistent data under `/mnt/data/openresist/ai-server`.

The setup is designed to keep only one large model loaded at a time. On a 128 GB RAM host, Llama 4 Scout is the safer first test. MiniMax-M2.7 at roughly 108 GB on disk may fit only when other containers and the OS leave enough headroom, especially at larger context sizes.

## Files

- `Dockerfile`: wraps the llama.cpp server image with a small startup script
- `docker-compose.yml`: local AI API service definition
- `.env.example`: runtime defaults and model download settings
- `config/start-llama-server.sh`: container entrypoint that validates the selected model and starts `llama-server`
- `scripts/bootstrap.sh`: creates data dirs, creates `.env`, builds the image, and starts the service
- `scripts/download-model.sh`: downloads selected GGUF files from Hugging Face
- `scripts/select-model.sh`: updates `.env` to point at a downloaded GGUF
- `scripts/status.sh`: prints Compose status, resource use, and the local health endpoint

## Data Layout

All persistent AI data lives under `/mnt/data/openresist/ai-server`:

- `models/`: downloaded GGUF model files
- `cache/huggingface/`: Hugging Face download cache
- `logs/`: reserved for local operational logs

## Start With Llama 4 Scout

Create the environment and data directories:

```bash
cd /home/blockcore/src/nostria/nostria-server/ai-server
bash ./scripts/bootstrap.sh
```

The first bootstrap will stop with a clear missing-model message. Download Scout, select the GGUF file that was downloaded, then start again:

```bash
bash ./scripts/download-model.sh scout
bash ./scripts/select-model.sh llama-4-scout/<downloaded-file>.gguf llama-4-scout
bash ./scripts/bootstrap.sh
```

If the Hugging Face repository or exact quant filename differs, override the defaults in `.env` or pass the repository directly:

```bash
bash ./scripts/download-model.sh owner/repo-name '*Q4*.gguf'
```

If the upstream llama.cpp container tag changes, update `LLAMA_CPP_IMAGE` in `.env` and rerun `bash ./scripts/bootstrap.sh`.

## Test MiniMax-M2.7

MiniMax is much tighter on a 128 GB machine. Stop other memory-heavy containers first, keep `LLAMA_CTX_SIZE` modest, and watch memory during load.

```bash
bash ./scripts/download-model.sh minimax
bash ./scripts/select-model.sh minimax-m2.7/<downloaded-file>.gguf minimax-m2.7
bash ./scripts/bootstrap.sh
bash ./scripts/status.sh
```

If the process is killed by the kernel or the machine starts swapping hard, switch back to Scout or use a smaller quant. For MiniMax, start with `LLAMA_CTX_SIZE=4096`, `LLAMA_PARALLEL=1`, and the q4 KV cache settings already present in `.env`.

## API Usage

The server is OpenAI-compatible. Use the generated `LLAMA_API_KEY` from `.env` as a bearer token.

Health check:

```bash
curl http://127.0.0.1:8088/health
```

Chat completion:

```bash
curl http://127.0.0.1:8088/v1/chat/completions \
  -H "Authorization: Bearer $LLAMA_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "llama-4-scout",
    "messages": [{"role": "user", "content": "Say hello from Nostria."}],
    "temperature": 0.7,
    "max_tokens": 128
  }'
```

## Cloudflare Tunnel

Expose the local origin through the existing Cloudflare helper:

```bash
cd /home/blockcore/src/nostria/nostria-server
sudo ./scripts/update-cloudflared-ingress.sh \
  --hostname ai.nostria.app \
  --service http://127.0.0.1:8088
```

Keep the API key enabled before exposing the service publicly. The public base URL will be:

```text
https://ai.nostria.app/v1
```

## Operations

Show status:

```bash
bash ./scripts/status.sh
```

View logs:

```bash
docker logs -f openresist-ai-server
```

Restart after changing `.env`:

```bash
docker compose up -d --build ai-server
```

Stop the service:

```bash
docker compose down
```

## Memory Notes

- Scout Q4-sized GGUFs should be the practical baseline on this machine.
- MiniMax-M2.7 around 108 GB can run out of RAM once the OS, other containers, KV cache, and request concurrency are included.
- `LLAMA_CTX_SIZE`, `LLAMA_PARALLEL`, and KV cache type have direct RAM impact.
- Keep `LLAMA_NO_MMAP=false` for large CPU models unless you need to force non-mmap loading.
