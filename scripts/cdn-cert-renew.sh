#!/usr/bin/env bash
# cdn-cert-renew.sh — trigger an immediate renewal check
#
# Normally not needed — the certbot container checks every 12 hours automatically.
# Use this to force an immediate check after a failure, or to re-upload the cert.
#
# To force renewal even if not yet due (e.g. to test the full flow):
#   docker compose exec certbot certbot renew --force-renewal \
#       --deploy-hook /scripts/cdn-cert-upload.sh

set -euo pipefail

echo "Restarting certbot container (triggers immediate renewal check on startup)..."
docker compose restart certbot

echo "Follow logs: docker compose logs -f certbot"
