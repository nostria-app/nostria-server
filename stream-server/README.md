# Stream Server

This deploys a local WHIP ingest service on the current Ubuntu host using `simple-whip-server` backed by a local Janus VideoRoom instance.

The intended public hostname for this service is `stream.openresist.com`.

## What It Runs

- `openresist-stream-server`: the local WHIP HTTP service bound to `127.0.0.1:7080`
- `openresist-stream-janus`: the local Janus backend used by the WHIP server for WebRTC media handling

The WHIP server exposes one configurable ingest endpoint by default:

- `http://127.0.0.1:7080/whip/endpoint/<WHIP_ENDPOINT_ID>`

By default that becomes:

- `http://127.0.0.1:7080/whip/endpoint/live`

## Important Network Constraint

Cloudflare Tunnel can safely expose the WHIP HTTP signaling endpoint, but it does not carry the underlying WebRTC RTP/RTCP media traffic for Janus.

For live streaming to work end to end, this host must also be directly reachable on the configured Janus UDP RTP range, which defaults to `20000-20100/udp`.

If this machine is behind NAT, set one of these correctly before starting the stack:

- `JANUS_PUBLIC_IP` to the public IP that clients can reach, and forward the UDP range to this host
- `JANUS_STUN_SERVER` and `JANUS_STUN_PORT` so Janus can discover a reachable public address

If the host is behind CGNAT or otherwise cannot receive inbound UDP, the WHIP signaling endpoint will come up but media negotiation will fail.

## Files

- `docker-compose.yml`: local Janus + WHIP service definition
- `Dockerfile`: container image for the local `simple-whip-server` wrapper app
- `package.json`: Node dependencies for the WHIP wrapper app
- `src/index.mjs`: Express-based wrapper that hosts `simple-whip-server` and basic health endpoints
- `config/janus/*.template`: Janus runtime config templates rendered by bootstrap
- `.env.example`: example service configuration
- `scripts/bootstrap.sh`: renders Janus config, builds the local Node image, and starts the stack
- `scripts/status.sh`: prints compose status and current container resource use

## Data Layout

All persistent runtime data is stored under `/mnt/data/openresist/stream-server`:

- `janus/janus.jcfg`: rendered Janus core config
- `janus/janus.transport.websockets.jcfg`: rendered Janus websocket transport config
- `janus/janus.plugin.videoroom.jcfg`: rendered Janus VideoRoom config

## Start

```bash
cd /home/blockcore/src/nostria/nostria-server/stream-server
cp .env.example .env
bash ./scripts/bootstrap.sh
```

To only render the Janus runtime config without starting containers:

```bash
bash ./scripts/bootstrap.sh --render-only
```

After bootstrap, the local HTTP endpoints are:

- `GET http://127.0.0.1:7080/healthz`
- `GET http://127.0.0.1:7080/endpoints`
- `GET http://127.0.0.1:7080/watch/`
- `POST http://127.0.0.1:7080/whip/endpoint/live` by default

If you set `WHIP_ENDPOINT_TOKEN`, clients must send it as a Bearer token.

`WHIP_ICE_SERVERS` accepts either a comma-separated URI list like `stun:stun.cloudflare.com:3478,turn:turn.example.com?transport=udp` or a JSON object/array when you need usernames and credentials.

`METERED_TURN_DOMAIN` and `METERED_TURN_API_KEY` activate automatic Metered TURN credential fetching. The stream-server runtime uses the returned `iceServers` list for WHIP publishers and for the watch page, while `bootstrap.sh` also derives a Janus relay configuration from the same Metered response so Janus can advertise TURN relay candidates for public viewers.

`JANUS_ROOM_BITRATE` caps the publish video bitrate in the VideoRoom. `JANUS_ROOM_BITRATE_CAP=true` makes that cap a hard limit rather than a soft target. The current test profile sets it to `500000` bps to keep streams heavily compressed while you validate connectivity from public networks.

The built-in watch page subscribes to the first active publisher in the configured Janus VideoRoom and is available at `/watch/` on both the local origin and the public hostname.

## Cloudflare Tunnel

Point Cloudflare Tunnel at the local WHIP signaling origin:

- Hostname: `stream.openresist.com`
- Service: `http://127.0.0.1:7080`

If the ingress entry ever needs to be recreated, run:

```bash
cd /home/blockcore/src/nostria/nostria-server
sudo ./scripts/update-cloudflared-ingress.sh \
  --hostname stream.openresist.com \
  --service http://127.0.0.1:7080
```

Cloudflare Tunnel only handles the HTTP control plane here. Janus media still uses direct ICE candidates and the configured UDP range on the host.

## Operations

Show status:

```bash
bash ./scripts/status.sh
```

View logs:

```bash
docker logs -f openresist-stream-server
docker logs -f openresist-stream-janus
```

Restart the stack:

```bash
docker compose restart
```

Stop the stack:

```bash
docker compose down
```