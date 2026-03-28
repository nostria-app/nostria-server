# Discovery Relay

This deploys a dedicated `strfry` discovery relay for `indexer.openresist.com` on the current Ubuntu server.

It is also intended to answer on these alias hostnames through the same Cloudflare Tunnel origin:

- `discovery.eu.nostria.app`
- `discovery.us.nostria.app`

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
- `scripts/sync-discovery-eu.sh`: targeted full down-sync from `discovery.eu.nostria.app`, with retry-until-stalled behavior
- `scripts/sync-discovery-us.sh`: targeted full down-sync from `discovery.us.nostria.app`, with retry-until-stalled behavior
- `config/strfry-router.conf`: live router streams for Coracle, Purple Pages, Primal, and Damus
- `scripts/start-live-sync.sh`: starts the live router loop in the background
- `scripts/stop-live-sync.sh`: stops the background live router loop
- `scripts/install-sync-timer.sh`: installs a systemd timer for scheduled syncs
- `systemd/openresist-discovery-sync.service`: oneshot sync job
- `systemd/openresist-discovery-sync.timer`: daily schedule for the sync job

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

This imports full event history from the configured upstream relays where available. It also pulls kind `10002` from Coracle as an extra relay-list source.

Current upstreams:

- `wss://purplepag.es/`
- `wss://indexer.coracle.social/`
- `wss://relay.damus.io/`
- `wss://relay.primal.net/`
- `wss://discovery.eu.nostria.app/`
- `wss://discovery.us.nostria.app/`
- `wss://discovery.af.nostria.app/`

This is a full sync job, not a discovery-only sync. Expect it to run for a long time and use substantial network, CPU, and disk I/O.

For a targeted EU relay backfill, run:

```bash
cd /home/blockcore/src/nostria/nostria-server/discovery-relay
./scripts/sync-discovery-eu.sh
```

That script prints total-event and kind-`10002` counts before and after the run, stops the live relay during sync, and restores it on exit.

By default it keeps retrying the EU down-sync after disconnects until it sees no new events for 2 consecutive attempts. You can tune that with:

```bash
SYNC_DOWN_BATCH_SIZE=500 EU_SYNC_MAX_NO_PROGRESS=3 EU_SYNC_RETRY_SLEEP_SECONDS=10 ./scripts/sync-discovery-eu.sh
```

To capture wrapper progress as well as the inner `strfry sync` logs, run it in the background and tail the dedicated log file instead of only watching Docker output:

```bash
nohup ./scripts/sync-discovery-eu.sh >> /mnt/data/openresist/discovery-relay/log/sync-discovery-eu.log 2>&1 &
tail -f /mnt/data/openresist/discovery-relay/log/sync-discovery-eu.log
```

For a targeted US relay backfill, run:

```bash
cd /home/blockcore/src/nostria/nostria-server/discovery-relay
./scripts/sync-discovery-us.sh
```

That script uses the same retry-until-stalled logic for `wss://discovery.us.nostria.app/`.

```bash
SYNC_DOWN_BATCH_SIZE=500 US_SYNC_MAX_NO_PROGRESS=3 US_SYNC_RETRY_SLEEP_SECONDS=10 ./scripts/sync-discovery-us.sh
```

For background execution with wrapper-level progress logging:

```bash
nohup ./scripts/sync-discovery-us.sh >> /mnt/data/openresist/discovery-relay/log/sync-discovery-us.log 2>&1 &
tail -f /mnt/data/openresist/discovery-relay/log/sync-discovery-us.log
```

## Scheduled Sync Job

Install the systemd timer:

```bash
cd /home/blockcore/src/nostria/nostria-server/discovery-relay
sudo ./scripts/install-sync-timer.sh
```

The default schedule is daily at `03:15`. Adjust `OnCalendar` in `systemd/openresist-discovery-sync.timer` if you want a different cadence.

## Cloudflare Tunnel

No local TLS is configured here.

Point Cloudflare Tunnel at the local origin:

- Hostname: `indexer.openresist.com`
- Hostname: `discovery.eu.nostria.app`
- Hostname: `discovery.us.nostria.app`
- Service: `http://127.0.0.1:7777`

WebSockets and NIP-11 responses are both served by `strfry` on that port.

To update `/etc/cloudflared/config.yml` on this server, run:

```bash
cd /home/blockcore/src/nostria/nostria-server
sudo ./scripts/update-cloudflared-ingress.sh
```

Optional overrides:

```bash
sudo ./scripts/update-cloudflared-ingress.sh \
	--hostname indexer.openresist.com \
	--hostname discovery.eu.nostria.app \
	--hostname discovery.us.nostria.app \
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

This runs `strfry router` with these live stream rules:

- `indexer.coracle.social`: `dir = both`
- `purplepag.es`: `dir = both`
- `relay.primal.net`: `dir = down`, filtered to kind `10002`
- `relay.damus.io`: `dir = down`, filtered to kind `10002`

That means local writes are mirrored upstream to Coracle and Purple Pages, while Primal and Damus are only subscribed for new kind-`10002` events.

Stop the background live router loop:

```bash
./scripts/stop-live-sync.sh
```

View logs:

```bash
docker-compose logs -f strfry-relay
tail -f /mnt/data/openresist/discovery-relay/log/live-sync-router.log
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