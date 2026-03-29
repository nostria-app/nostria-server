# Media Server

This deploys the local Nostria media server on the current Ubuntu host, replacing the cloud-hosted media instances with the same base Blossom configuration used in `nostria-infrastructure`.

The intended public hostname for this local replacement is `media.openresist.com`.

The container image follows the current infrastructure choice:

- `ghcr.io/nostria-app/nostria-media:latest`

The service listens locally on `127.0.0.1:3000` and stores persistent data under `/mnt/data/openresist/media`.

## Files

- `docker-compose.yml`: local media service definition
- `config/config.yml`: tracked config template mirrored from infrastructure
- `.env.example`: dashboard password example
- `scripts/bootstrap.sh`: creates data dirs, installs config, pulls the current image, and starts the service
- `scripts/status.sh`: prints compose status and current container resource use

## Data Layout

All persistent media data lives under `/mnt/data/openresist/media`:

- `config.yml`: runtime Blossom config copied from the tracked template on first bootstrap
- `data/sqlite.db`: metadata database
- `data/blobs/`: local blob storage

## Start

```bash
cd /home/blockcore/src/nostria/nostria-server/media-server
cp .env.example .env
bash ./scripts/bootstrap.sh
```

If `.env` is omitted, the server can still start, but the dashboard password may not be stable across restarts.

## Operations

Show status:

```bash
bash ./scripts/status.sh
```

View logs:

```bash
docker logs -f openresist-media-server
```

Restart the service:

```bash
docker compose restart media-server
```

Stop the service:

```bash
docker compose down
```

## Cloudflare Tunnel

To expose the local media server through the same cloudflared helper used by the relay services, point hostnames at `http://127.0.0.1:3000`.

Example:

```bash
cd /home/blockcore/src/nostria/nostria-server
sudo ./scripts/update-cloudflared-ingress.sh \
  --hostname media.openresist.com \
  --service http://127.0.0.1:3000
```
