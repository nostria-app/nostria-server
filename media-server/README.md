# Media Server

This deploys the local Nostria media server on the current Ubuntu host, replacing the cloud-hosted media instances with the same base Blossom configuration used in `nostria-infrastructure`.

The intended public hostnames for this local replacement are `media.openresist.com`, `mibo.nostria.app`, and `milo.nostria.app`. Returned media URLs follow the hostname used on the incoming upload request.

The container image follows the current infrastructure choice:

- `ghcr.io/nostria-app/nostria-media:latest`

The service listens locally on `127.0.0.1:3000` and stores persistent data under `/mnt/data/openresist/media`.

## Files

- `docker-compose.yml`: local media service definition
- `config/config.yml`: tracked config template mirrored from infrastructure, with request-host-based media URLs
- `.env.example`: dashboard password example
- `scripts/bootstrap.sh`: creates data dirs, installs config, pulls the current image, and starts the service
- `scripts/status.sh`: prints compose status and current container resource use
- `scripts/sync-pubkey.mjs`: targeted no-delete importer for a single owner pubkey from a remote media server
- `scripts/full-sync.mjs`: direct no-delete full sync importer for a remote media server

## Data Layout

All persistent media data lives under `/mnt/data/openresist/media`:

- `config.yml`: runtime Blossom config copied from the tracked template on first bootstrap
- `data/sqlite.db`: metadata database
- `data/blobs/`: local blob storage

Keep `publicDomain` unset in the runtime config if you want the media server to return URLs on the same hostname the client used for the upload request.

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

To expose the local media server through the same cloudflared helper used by the relay services, point the public media hostnames at `http://127.0.0.1:3000`.

Example:

```bash
cd /home/blockcore/src/nostria/nostria-server
sudo ./scripts/update-cloudflared-ingress.sh \
  --hostname media.openresist.com \
  --hostname mibo.nostria.app \
  --hostname milo.nostria.app \
  --service http://127.0.0.1:3000
```

Legacy two-level hostnames such as `mibo.eu.nostria.app` and `mibo.us.nostria.app` cannot be preserved through this tunnel if Cloudflare will not allow those exact hostnames or a matching wildcard on the tunnel. Handle those legacy names with redirect rules on the `nostria.app` side instead:

- `mibo.eu.nostria.app` -> `https://mibo.nostria.app`
- `mibo.us.nostria.app` -> `https://milo.nostria.app`
