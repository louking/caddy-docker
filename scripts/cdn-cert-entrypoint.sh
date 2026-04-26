#!/usr/bin/env bash
# cdn-cert-entrypoint.sh — certbot container entrypoint
#
# On first start: obtains the certificate and uploads it to DigitalOcean.
# Then loops every 12 hours, renewing when within 30 days of expiry and re-uploading.
#
# Set CERTBOT_STAGING=true in .env to use the Let's Encrypt staging server
# when testing — same DNS challenge, no rate limits, issues an untrusted test cert.

set -euo pipefail

CF_CREDS="/etc/letsencrypt/cloudflare.ini"

for var in CLOUDFLARE_API_TOKEN DO_API_TOKEN DO_CDN_ENDPOINT_ID CDN_DOMAIN LETSENCRYPT_EMAIL; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: $var is not set. Add it to .env." >&2
        exit 1
    fi
done

# ── write Cloudflare credentials (persisted in the letsencrypt volume) ────────

if [[ ! -f "$CF_CREDS" ]]; then
    echo "Writing Cloudflare credentials to $CF_CREDS"
    cat > "$CF_CREDS" <<EOF
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOF
    chmod 600 "$CF_CREDS"
fi

# ── obtain certificate on first start ─────────────────────────────────────────

CERT_DIR="/etc/letsencrypt/live/${CDN_DOMAIN}"

STAGING_FLAG=""
if [[ "${CERTBOT_STAGING:-false}" == "true" ]]; then
    echo "WARNING: staging mode — cert will be issued by Let's Encrypt staging CA (untrusted)"
    STAGING_FLAG="--staging"
fi

if [[ ! -f "${CERT_DIR}/fullchain.pem" ]]; then
    echo "No certificate found — obtaining initial certificate for ${CDN_DOMAIN}..."
    certbot certonly \
        --non-interactive \
        --agree-tos \
        --email "$LETSENCRYPT_EMAIL" \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$CF_CREDS" \
        --dns-cloudflare-propagation-seconds 30 \
        $STAGING_FLAG \
        -d "$CDN_DOMAIN"

    echo "Uploading initial certificate to DigitalOcean..."
    /scripts/cdn-cert-upload.sh
fi

# ── renewal loop ──────────────────────────────────────────────────────────────
# Runs certbot renew immediately (no-op if not due), then waits 12 hours.
# The deploy hook re-uploads to DigitalOcean only when a renewal actually occurs.

echo "Entering renewal loop (checks every 12 hours)..."
while true; do
    certbot renew --quiet $STAGING_FLAG --deploy-hook /scripts/cdn-cert-upload.sh
    sleep 12h
done
