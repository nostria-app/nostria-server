# OpenResist Relay

This deploys a dedicated local `strfry` account relay for `relay.openresist.com` on the current Ubuntu server.

It is also intended to answer on these alias hostnames through the same Cloudflare Tunnel origin:

- `ribo.eu.nostria.app`
- `ribo.us.nostria.app`

The image is built locally from the workspace copy of `../../strfry`, which is expected to be checked out at Strfry `1.1.0`.

## What It Runs

- `openresist-relay`: the local account relay process bound to `127.0.0.1:7778`

This relay is intended to replace the previous split relay topology and later sync with:

- `wss://ribo.us.nostria.app/`
- `wss://ribo.eu.nostria.app/`

The Cloudflare Tunnel hostnames `relay.openresist.com`, `ribo.eu.nostria.app`, and `ribo.us.nostria.app` now map to `http://127.0.0.1:7778` on this server.

Sync is staged in two phases:

1. Full catch-up from EU, then US
2. Continuous down-sync from both old relays until DNS/domain cutover is complete

Important: `strfry sync` and `strfry router` need exclusive write access to the LMDB database in this setup. During catch-up and live replication, the local relay process is stopped. When cutover is ready, stop the live router sync and start the relay again.

## Data Layout

All persistent data is stored under `/mnt/data/openresist/relay`:

- `db/`: LMDB database
- `log/`: relay logs

## Start

```bash
cd /home/blockcore/src/nostria/nostria-server/openresist-relay
./scripts/bootstrap.sh
```

This will:

1. Create `/mnt/data/openresist/relay/{db,log}` if missing
2. Build the local `strfry` `1.1.0` image
3. Start the relay container

## Cloudflare Tunnel

Point Cloudflare Tunnel at the local origin:

- Hostname: `relay.openresist.com`
- Hostname: `ribo.eu.nostria.app`
- Hostname: `ribo.us.nostria.app`
- Service: `http://127.0.0.1:7778`

If the ingress entry ever needs to be recreated, run:

```bash
cd /home/blockcore/src/nostria/nostria-server
sudo ./scripts/update-cloudflared-ingress.sh --hostname relay.openresist.com --service http://127.0.0.1:7778
sudo ./scripts/update-cloudflared-ingress.sh --hostname ribo.eu.nostria.app --service http://127.0.0.1:7778
sudo ./scripts/update-cloudflared-ingress.sh --hostname ribo.us.nostria.app --service http://127.0.0.1:7778
```

## Operations

Run the full catch-up from EU only:

```bash
./scripts/full-sync.sh eu
```

By default, full sync now requests `500` events per DOWN batch instead of Strfry's built-in default of `50`. You can override that for testing:

```bash
SYNC_DOWN_BATCH_SIZE=1000 ./scripts/full-sync.sh eu
```

Run the full catch-up from US only:

```bash
./scripts/full-sync.sh us
```

Start continuous live replication after catch-up:

```bash
./scripts/start-live-sync.sh
```

This starts a single `strfry router` process that keeps down-sync connections open to both old relays and keeps the local relay container stopped while replication is active.

Stop live router sync:

```bash
./scripts/stop-live-sync.sh
```

Bring the local relay back up after stopping live router sync:

```bash
./scripts/bootstrap.sh
```

Run the full cutover workflow in order: EU full sync, US full sync, then continuous sync:

```bash
nohup ./scripts/start-cutover-sync.sh >> /mnt/data/openresist/relay/log/cutover-sync.log 2>&1 &
```

View logs:

```bash
docker-compose logs -f openresist-relay
tail -f /mnt/data/openresist/relay/log/cutover-sync.log
tail -f /mnt/data/openresist/relay/log/live-sync-router.log
```

Check current sync status:

```bash
./scripts/sync-status.sh
```

Check total event count:

```bash
docker-compose exec -T openresist-relay /app/strfry --config /etc/strfry.conf scan '{}' | wc -l
```

Stop the stack:

```bash
docker-compose down
```