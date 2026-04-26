# caddy-docker

Dockerized [Caddy](https://caddyserver.com/) reverse proxy with automatic TLS, Cloudflare integration, and DigitalOcean CDN certificate management.

## Stack

### caddy

Custom Caddy build (via `xcaddy`) with three additional modules:

- [`transform-encoder`](https://github.com/caddyserver/transform-encoder) — structured log formatting
- [`caddy-dns/cloudflare`](https://github.com/caddy-dns/cloudflare) — DNS-01 TLS challenge for wildcard/non-HTTP certs
- [`caddy-cloudflare-ip`](https://github.com/WeidiDeng/caddy-cloudflare-ip) — auto-refreshed Cloudflare IP ranges for `trusted_proxies`

Runs as a non-root user (UID/GID set via `.env`). Logs are rotated at 10 MB, keeping 2 files for 7 days, written to `./logs/` on the host.

### certbot

Container (based on `certbot/certbot`) that obtains and renews a Let's Encrypt certificate for the DigitalOcean CDN custom domain using a Cloudflare DNS-01 challenge. On first start it acquires the certificate and uploads it to the DigitalOcean CDN via their API. It then checks for renewal every 12 hours; when a renewal occurs the new certificate is automatically uploaded and the old one deleted.

## Environment variables

`.env` is not committed to the repository. Create it in the project directory using the template below.

### caddy service

| Variable | Description |
|---|---|
| `APP_VER` | Image tag, e.g. `1.0.0` |
| `CF_API_TOKEN` | Cloudflare API token — needs `Zone:Read` + `DNS:Edit` for all zones served by Caddy. Also reused by the certbot service for the CDN DNS challenge. Create at [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens) |
| `CADDY_UID` | UID the caddy process runs as |
| `CADDY_GID` | GID the caddy process runs as |
| `CADDY_DATA_HOST` | Host path for Caddy's persistent data (certs, OCSP, etc.) |
| `CADDY_CONFIG_HOST` | Host path for Caddy's runtime config cache |
| `CADDY_LOG_HOST` | Host path for log files |
| `DEBUG` | Set `true` to run `tail -f /dev/null` instead of Caddy (allows exec into the container to inspect the environment) |

### certbot service

| Variable | Description |
|---|---|
| `DO_API_TOKEN` | DigitalOcean API token with scoped access: `cdn` (create, read, update, delete) and `certificate` (create, read, delete). Create at [cloud.digitalocean.com/account/api/tokens](https://cloud.digitalocean.com/account/api/tokens) |
| `DO_CDN_ENDPOINT_ID` | DigitalOcean CDN endpoint ID. Find it with: `curl -s -H "Authorization: Bearer $DO_API_TOKEN" https://api.digitalocean.com/v2/cdn/endpoints \| jq '.endpoints[] \| {id, origin, custom_domain}'` |
| `CDN_DOMAIN` | Custom domain configured on the CDN, e.g. `cdn.example.com` |
| `LETSENCRYPT_EMAIL` | Email address for Let's Encrypt expiry notifications |
| `CERTBOT_STAGING` | Set `true` to use the Let's Encrypt staging CA (untrusted cert, no rate limits). Use when testing. |

### `.env` template

```
COMPOSE_FILE=docker-compose.yml
DEBUG=false

APP_VER=1.0.0
CF_API_TOKEN=

CADDY_DATA_HOST=./caddy_data
CADDY_CONFIG_HOST=./caddy_config
CADDY_LOG_HOST=./logs

CADDY_UID=985
CADDY_GID=985

# CDN certificate management
# CF_API_TOKEN (above) is reused for the Cloudflare DNS challenge
DO_API_TOKEN=
DO_CDN_ENDPOINT_ID=
CDN_DOMAIN=cdn.example.com
LETSENCRYPT_EMAIL=you@example.com
CERTBOT_STAGING=false
```

## Build and run

The external Docker network must exist before starting:

```bash
docker network create caddy-backend-network
```

```bash
# Build images
docker compose build

# Start (detached)
docker compose up -d

# Stop
docker compose down
```

## CDN certificate setup (first time)

```bash
# Watch the container obtain the initial certificate
docker compose logs -f certbot
```

To force an immediate renewal check: `bash scripts/cdn-cert-renew.sh`

## Deployment

Uses [Fabric](https://www.fabfile.org/). Install dependencies with `pip install -r requirements.txt`, then:

```bash
# Deploy to production from main branch
fab -H <server-hostname> deploy prod

# Deploy from a specific branch
fab -H <server-hostname> deploy prod --branchname=<branch>
```

The deploy task pulls `docker-compose.yml` from GitHub, then runs `docker compose pull && docker compose up -d` on the remote host. The `.env` file must already exist on the server.

## Caddyfile

`config/Caddyfile` — active configuration (used in development).  
`config/Caddyfile.example` — production template with real domain names and Cloudflare TLS.

To apply Caddyfile changes without rebuilding: `docker compose restart caddy`.
