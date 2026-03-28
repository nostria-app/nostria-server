# Nostria Server

Setup for self-hosted Nostria infrastructure services on a physical Ubuntu server.

## Discovery Relay

The discovery relay deployment for `indexer.openresist.com` lives in `discovery-relay/`.

It builds the Docker image locally from the sibling `strfry/` workspace folder and stores all persistent data under `/mnt/data/openresist/discovery-relay` by default.

Quick start:

```bash
cd discovery-relay
./scripts/bootstrap.sh
./scripts/initial-sync.sh
```

`initial-sync.sh` is configured for a full historical sync from upstream relays and can take a long time to complete.

The relay listens locally on `127.0.0.1:7777` and is intended to be exposed externally through Cloudflare Tunnel.

To update the local Cloudflare Tunnel ingress config for the relay, run:

```bash
sudo ./scripts/update-cloudflared-ingress.sh
```

See `discovery-relay/README.md` for the full setup and operations guide.

## OpenResist Relay

The account relay deployment for `relay.openresist.com` lives in `openresist-relay/`.

It builds from the sibling `strfry/` workspace folder and stores persistent data under `/mnt/data/openresist/relay`.

Quick start:

```bash
cd openresist-relay
./scripts/bootstrap.sh
nohup ./scripts/start-cutover-sync.sh >> /mnt/data/openresist/relay/log/cutover-sync.log 2>&1 &
```

The relay listens locally on `127.0.0.1:7778` and the Cloudflare Tunnel hostname `relay.openresist.com` should point at that origin.

See `openresist-relay/README.md` for the full setup, sync, and operations guide.
