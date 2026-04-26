# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A Dockerized Caddy web server with custom modules compiled in. It acts as a reverse proxy for multiple backend services, with Cloudflare integration for DNS-based TLS certificates and trusted proxy IP resolution. A second service (`certbot`) manages TLS certificates for a DigitalOcean CDN custom domain.

Custom modules compiled via `xcaddy`:
- `transform-encoder` — structured log formatting
- `caddy-dns/cloudflare` — DNS challenge for TLS certs
- `caddy-cloudflare-ip` — Cloudflare IP range trust for `trusted_proxies`

## Build & Run

```bash
# Build image
docker compose build

# Start (detached)
docker compose up -d

# Stop
docker compose down
```

The caddy image is tagged `louking/caddy:${APP_VER}` (version in `.env`). The certbot image is `louking/caddy-certbot:latest` (built from `Dockerfile.certbot`). UID/GID for the `caddy` process are set via `CADDY_UID`/`CADDY_GID` in `.env` (currently 985).

**Prerequisite**: The external Docker network `caddy-backend-network` must exist before starting:
```bash
docker network create caddy-backend-network
```

## Remote Deployment (Fabric)

```bash
pip install -r requirements.txt

# Deploy to production from main branch
fab -H <server-hostname> deploy prod

# Deploy from a specific branch
fab -H <server-hostname> deploy prod --branchname=<branch>
```

Fabric connects as `appuser` using the SSH key path in `fabric.json`. The deploy task pulls `docker-compose.yml` from GitHub, then runs `docker compose pull && docker compose up -d` on the remote host.

## Configuration

`config/Caddyfile` — active configuration (used in development; proxies to `*.localhost` addresses).  
`config/Caddyfile.example` — production template with real domain names and Cloudflare TLS.

The Caddyfile mounts into the container at `/etc/caddy`. To apply config changes without rebuilding: `docker compose restart` or use Caddy's API reload.

## Debug Mode

Set `DEBUG=true` in `.env` to make the container run `tail -f /dev/null` instead of Caddy, allowing you to exec in and inspect the environment:
```bash
docker compose up -d
docker compose exec caddy sh
```

## CDN Certificate Management

The `certbot` service handles TLS certificates for the DigitalOcean CDN custom domain (`cdn.steeplechasers.org`). Scripts live in `caddy-docker/scripts/` and are baked into the certbot image — only `.env` needs to exist on the server.

- `scripts/cdn-cert-entrypoint.sh` — container entrypoint: obtains cert on first start, then loops every 12h running `certbot renew`
- `scripts/cdn-cert-upload.sh` — uploads the current cert to DigitalOcean via API (also used as certbot's deploy hook)
- `scripts/cdn-cert-renew.sh` — local helper: restarts the certbot container to trigger an immediate renewal check
- `scripts/cdn-cert.env.example` — reference listing the required `.env` variables

`CF_API_TOKEN` (used by Caddy for DNS-based TLS) is reused by the certbot service for the CDN DNS challenge — no separate Cloudflare token is needed. The `letsencrypt` named Docker volume persists certificates across container restarts and deploys.

First-time setup: `bash scripts/cdn-cert-init.sh` (run locally after filling in `.env`).  
Set `CERTBOT_STAGING=true` in `.env` to test without hitting Let's Encrypt rate limits.

## Architecture Notes

- Backend services are reached via `host.docker.internal` (mapped to host gateway). The dev Caddyfile routes `members.localhost → :8002`, `routes.localhost → :8005`, `scores.localhost → :8004`, `contracts.localhost → :8003`, `tmsim.localhost → :8080`, `logmon.localhost → :8100`.
- Logs are rotated at 10 MB, keeping 2 files for up to 7 days, written to `./logs/` on the host.
- The container runs as the `caddy` user (not root); `entrypoint.sh` uses `su-exec` to drop privileges after fixing ownership of `/var/log/caddy` and `/data`.
