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
`config/Caddyfile.example` — production template with anonymized domain names and Cloudflare TLS.

The Caddyfile mounts into the container at `/etc/caddy`. To apply config changes without rebuilding: `docker compose restart` or use Caddy's API reload.

**Note:** The production Caddyfile on the server (`~/caddy-prod/config/Caddyfile`) has diverged significantly from `Caddyfile.example` — it hosts many additional domains (loutilities.com, steeplechasers.org, scoretility.com, etc.) and is managed directly on the server, not deployed from this repo.

`protocols h1 h2` is set explicitly in the global `servers` block to disable HTTP/3 (QUIC). Caddy enables HTTP/3 by default and advertises it via `Alt-Svc` headers; if a client's UDP/443 is blocked, this causes `ERR_QUIC_PROTOCOL_ERROR` on subsequent page loads even when the initial response succeeds. Cloudflare handles HTTP/3 at its own edge, so Caddy doesn't need it.

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
- `fsrc-tech.localhost` serves the `fsrc-tech` wiki as static files (`file_server` on `/var/www/fsrc-tech/site`), not proxied — `FSRC_TECH_WWW_HOST` in `.env` bind-mounts that sibling repo's working directory straight into the container at `/var/www/fsrc-tech`.
- Logs are rotated at 10 MB, keeping 2 files for up to 7 days, written to `./logs/` on the host.
- The container runs as the `caddy` user (not root); `entrypoint.sh` uses `su-exec` to drop privileges after fixing ownership of `/var/log/caddy` and `/data`.
- The Dockerfile's `RUN chmod +x ./entrypoint.sh` (after `COPY ./entrypoint.sh ./`) is load-bearing, not redundant: `entrypoint.sh` is git-tracked as mode `100644` (likely committed from Windows, where `core.filemode` defaults off), and a build run in a Windows-filesystem context tolerates the missing exec bit on `COPY` — but a build run against a Linux filesystem (e.g. from WSL) does not, and fails at container start with `exec: "./entrypoint.sh": permission denied`.
