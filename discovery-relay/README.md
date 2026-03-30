# Discovery Relay

This deploys a dedicated `strfry` discovery relay for `indexer.openresist.com` on the current Ubuntu server.

The canonical public hostname is:

- `indexer.openresist.com`

Legacy compatibility hostnames are:

- `discovery.eu.nostria.app`
- `discovery.us.nostria.app`

Those compatibility hostnames should now be handled by a Cloudflare Worker that proxies websocket and HTTP traffic to `https://indexer.openresist.com/`.

The helper scripts auto-detect whether to use `docker compose` or legacy `docker-compose`.

## What It Runs

- `strfry-relay`: the local relay process bound to `127.0.0.1:7777`

Manual and scheduled syncs reuse the `strfry-relay` service definition instead of a separate sync container definition.

The image is built locally from the workspace copy of `../../strfry`, which is expected to be checked out at Strfry `1.1.0`.

## Data Layout

All persistent data is stored under `/mnt/data/openresist/discovery-relay`:

- `db/`: LMDB database
- `log/`: relay and bootstrap logs

## Files

- `docker-compose.yml`: relay service
- `config/strfry.conf`: relay configuration
- `scripts/bootstrap.sh`: creates directories and starts the stack
- `scripts/initial-sync.sh`: optional one-time historical sync
- `scripts/start-live-sync.sh`: starts the live websocket sync supervisor in the background
- `scripts/stop-live-sync.sh`: stops the background live websocket sync supervisor
- `scripts/live-sync-status.sh`: shows relay state, live sync status, worker counts, and recent live-sync logs
- `scripts/install-sync-timer.sh`: installs a systemd timer for scheduled syncs
- `scripts/install-live-sync-service.sh`: installs a persistent systemd service for the live-sync supervisor
- `systemd/openresist-discovery-sync.service`: oneshot sync job
- `systemd/openresist-discovery-sync.timer`: daily schedule for the sync job
- `systemd/openresist-discovery-live-sync.service`: persistent live-sync supervisor

## Start

```bash
cd /home/blockcore/src/nostria/nostria-server/discovery-relay
./scripts/bootstrap.sh
```

This will:

1. Create `/mnt/data/openresist/discovery-relay/{db,log}` if missing
2. Build the local `strfry` `1.1.0` image
3. Start the relay container

## Initial Historical Sync

For a fresh deployment, run the initial sync once:

```bash
cd /home/blockcore/src/nostria/nostria-server/discovery-relay
./scripts/initial-sync.sh
```

This imports discovery relay history as kinds `3` and `10002` only from the configured discovery relays. It also pulls kind `10002` from Coracle as an extra relay-list source.

Current upstreams:

- `wss://purplepag.es/`
- `wss://indexer.coracle.social/`
- `wss://relay.damus.io/`
- `wss://relay.primal.net/`
- `wss://discovery.af.nostria.app/`

This is a multi-relay historical sync job, but discovery relay imports are limited to kinds `3` and `10002`. Expect it to run for a long time and use substantial network, CPU, and disk I/O.

The old targeted `sync-discovery-eu.sh` and `sync-discovery-us.sh` backfill scripts were removed after those compatibility hostnames were migrated to the local server.

## Scheduled Sync Job

Install the systemd timer:

```bash
cd /home/blockcore/src/nostria/nostria-server/discovery-relay
sudo ./scripts/install-sync-timer.sh
```

The default schedule is daily at `03:15`. Adjust `OnCalendar` in `systemd/openresist-discovery-sync.timer` if you want a different cadence.

## Cloudflare Tunnel

No local TLS is configured here.

Point Cloudflare Tunnel at the local origin for the canonical hostname only:

- Hostname: `indexer.openresist.com`
- Service: `http://127.0.0.1:7777`

WebSockets and NIP-11 responses are both served by `strfry` on that port.

Keep `discovery.eu.nostria.app` and `discovery.us.nostria.app` on the Cloudflare side as compatibility hostnames handled by a Worker that proxies to `indexer.openresist.com`. They should not be treated as redirects because websocket clients may not follow them correctly.

To update `/etc/cloudflared/config.yml` on this server for the canonical hostname, run:

```bash
cd /home/blockcore/src/nostria/nostria-server
sudo ./scripts/update-cloudflared-ingress.sh
```

If the ingress entry ever needs to be recreated explicitly, use:

```bash
sudo ./scripts/update-cloudflared-ingress.sh \
	--hostname indexer.openresist.com \
	--service http://127.0.0.1:7777
```

## Operations

Start or rebuild:

```bash
./scripts/bootstrap.sh
```

Start continuous live sync while keeping the local relay online:

```bash
./scripts/start-live-sync.sh
```

This runs websocket-only sync workers so the local relay stays online and no second process opens the LMDB database directly.

While the live-sync supervisor is running, it also checks that the `strfry-relay` container stays up and will restart it automatically if it is stopped.

Live stream rules:

- local relay to `indexer.coracle.social`: `strfry download --follow ws://strfry-relay:7777 --filter '{"since":...}' | strfry upload wss://indexer.coracle.social/`
- local relay to `purplepag.es`: `strfry download --follow ws://strfry-relay:7777 --filter '{"since":...}' | strfry upload wss://purplepag.es/`
- `relay.primal.net` to local relay: `strfry download --follow --filter '{"kinds":[10002],"since":...}' | strfry upload ws://strfry-relay:7777`
- `relay.damus.io` to local relay: same as above

That means local writes are mirrored upstream to Coracle and Purple Pages without a kind filter, while Primal and Damus are only followed for new kind-`10002` events. The previous live sync loops for `discovery.eu.nostria.app` and `discovery.us.nostria.app` were removed after those compatibility hostnames were migrated to the local server.

Stop the background live sync supervisor:

```bash
./scripts/stop-live-sync.sh
```

View logs:

```bash
docker-compose logs -f strfry-relay
tail -f /mnt/data/openresist/discovery-relay/log/live-sync.log
```

Check live sync status:

```bash
bash ./scripts/live-sync-status.sh
```

Install persistent live-sync supervision with systemd:

```bash
sudo bash ./scripts/install-live-sync-service.sh
systemctl status openresist-discovery-live-sync.service
journalctl -u openresist-discovery-live-sync.service -n 100
```

Check discovery data counts:

```bash
docker-compose exec -T strfry-relay /app/strfry --config /etc/strfry.conf scan '{"kinds":[3]}' | wc -l
docker-compose exec -T strfry-relay /app/strfry --config /etc/strfry.conf scan '{"kinds":[10002]}' | wc -l
docker-compose exec -T strfry-relay /app/strfry --config /etc/strfry.conf scan '{}' | wc -l
```

Check the timer:

```bash
systemctl status openresist-discovery-sync.timer
systemctl list-timers openresist-discovery-sync.timer
journalctl -u openresist-discovery-sync.service -n 100
```

Stop the stack:

```bash
docker-compose down
```