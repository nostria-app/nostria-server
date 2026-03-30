# Nostria Server

Setup for self-hosted Nostria infrastructure services on a physical Ubuntu server.

## Discovery Relay

The discovery relay deployment for `indexer.openresist.com` lives in `discovery-relay/`.

The canonical public hostname is `indexer.openresist.com`.

Legacy discovery hostnames `discovery.eu.nostria.app` and `discovery.us.nostria.app` should now be treated as compatibility hostnames handled by a Cloudflare Worker that proxies websocket and HTTP traffic to `indexer.openresist.com`.

It builds the Docker image locally from the sibling `strfry/` workspace folder and stores all persistent data under `/mnt/data/openresist/discovery-relay` by default.

Quick start:

```bash
cd discovery-relay
./scripts/bootstrap.sh
./scripts/initial-sync.sh
```

`initial-sync.sh` is configured for a full historical sync from upstream relays and can take a long time to complete.

The relay listens locally on `127.0.0.1:7777` and is intended to be exposed externally through Cloudflare Tunnel.

The local tunnel only needs the canonical hostname:

- `indexer.openresist.com` -> `http://127.0.0.1:7777`

The compatibility hostnames `discovery.eu.nostria.app` and `discovery.us.nostria.app` should not be added to local tunnel ingress when Cloudflare is handling them with a Worker.

To update the local Cloudflare Tunnel ingress config for the canonical relay hostname, run:

```bash
sudo ./scripts/update-cloudflared-ingress.sh
```

See `discovery-relay/README.md` for the full setup and operations guide.

## OpenResist Relay

The account relay deployment for `relay.openresist.com` lives in `openresist-relay/`.

It is also exposed on `ribo.eu.nostria.app`, `ribo.us.nostria.app`, `ribo.nostria.app`, and `rilo.nostria.app` through the same local origin.

It builds from the sibling `strfry/` workspace folder and stores persistent data under `/mnt/data/openresist/relay`.

Quick start:

```bash
cd openresist-relay
./scripts/bootstrap.sh
nohup ./scripts/start-cutover-sync.sh >> /mnt/data/openresist/relay/log/cutover-sync.log 2>&1 &
```

The relay listens locally on `127.0.0.1:7778` and the Cloudflare Tunnel hostnames `relay.openresist.com`, `ribo.eu.nostria.app`, `ribo.us.nostria.app`, `ribo.nostria.app`, and `rilo.nostria.app` should point at that origin.

Legacy relay names `ribo.eu.nostria.app` and `ribo.us.nostria.app` should be treated as compatibility hostnames, not redirects. They should remain proxied through Cloudflare Tunnel to the same relay origin so third-party WebSocket clients continue to work while clients migrate to `wss://ribo.nostria.app/` and `wss://rilo.nostria.app/`.

See `openresist-relay/README.md` for the full setup, sync, and operations guide.

## Media Server

The local media server deployment lives in `media-server/`.

It mirrors the tracked Blossom configuration from `nostria-infrastructure/config/media/config.yml`, uses the current upstream image `ghcr.io/nostria-app/nostria-media:latest`, listens locally on `127.0.0.1:3000`, and stores persistent data under `/mnt/data/openresist/media`.

The intended public hostnames for this service are `media.openresist.com`, `mibo.nostria.app`, and `milo.nostria.app`.

Quick start:

```bash
cd media-server
cp .env.example .env
bash ./scripts/bootstrap.sh
```

Route `media.openresist.com`, `mibo.nostria.app`, and `milo.nostria.app` through Cloudflare Tunnel to `http://127.0.0.1:3000` using `scripts/update-cloudflared-ingress.sh`.

Legacy hostnames `mibo.eu.nostria.app` and `mibo.us.nostria.app` should be handled with HTTP redirects on the `nostria.app` side to `https://mibo.nostria.app` and `https://milo.nostria.app` respectively.

See `media-server/README.md` for the full setup and operations guide.
