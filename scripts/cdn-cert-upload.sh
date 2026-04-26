#!/usr/bin/env bash
# cdn-cert-upload.sh — upload the current certificate to DigitalOcean CDN
#
# Usage:
#   In container:  /scripts/cdn-cert-upload.sh
#   Deploy hook:   certbot calls this automatically after each successful renewal.
#
# When called by certbot as a deploy hook, RENEWED_DOMAINS is set by certbot.
# The script skips execution if RENEWED_DOMAINS is set but doesn't include CDN_DOMAIN.

set -euo pipefail

# When running as a certbot deploy hook, skip if this domain wasn't renewed.
if [[ -n "${RENEWED_DOMAINS:-}" ]]; then
    if ! echo "$RENEWED_DOMAINS" | grep -qw "$CDN_DOMAIN"; then
        echo "Skipping: $CDN_DOMAIN not in RENEWED_DOMAINS ($RENEWED_DOMAINS)"
        exit 0
    fi
fi

CERT_DIR="/etc/letsencrypt/live/${CDN_DOMAIN}"
CERT_NAME="${CDN_DOMAIN//./-}-$(date +%Y%m%d%H%M%S)"
DO_API="https://api.digitalocean.com/v2"

# ── read certificate files ────────────────────────────────────────────────────

if [[ ! -f "${CERT_DIR}/privkey.pem" ]]; then
    echo "Error: cert files not found in ${CERT_DIR}" >&2
    exit 1
fi

PRIVATE_KEY=$(cat "${CERT_DIR}/privkey.pem")
LEAF_CERT=$(cat "${CERT_DIR}/cert.pem")
CERT_CHAIN=$(cat "${CERT_DIR}/chain.pem")

# ── find the old certificate ID before we replace it ─────────────────────────

echo "Fetching current CDN endpoint..."
ENDPOINT_RESPONSE=$(curl -sf \
    -H "Authorization: Bearer ${DO_API_TOKEN}" \
    "${DO_API}/cdn/endpoints/${DO_CDN_ENDPOINT_ID}")

OLD_CERT_ID=$(echo "$ENDPOINT_RESPONSE" | jq -r '.endpoint.certificate_id // empty')

# ── create new certificate in DigitalOcean ────────────────────────────────────

echo "Creating certificate '${CERT_NAME}' in DigitalOcean..."
CERT_PAYLOAD=$(jq -n \
    --arg name    "$CERT_NAME" \
    --arg pk      "$PRIVATE_KEY" \
    --arg lc      "$LEAF_CERT" \
    --arg cc      "$CERT_CHAIN" \
    '{name: $name, type: "custom", private_key: $pk, leaf_certificate: $lc, certificate_chain: $cc}')

CERT_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer ${DO_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$CERT_PAYLOAD" \
    "${DO_API}/certificates")

NEW_CERT_ID=$(echo "$CERT_RESPONSE" | jq -r '.certificate.id // empty')

if [[ -z "$NEW_CERT_ID" ]]; then
    echo "Error: failed to create certificate." >&2
    echo "$CERT_RESPONSE" >&2
    exit 1
fi

echo "Created certificate: ${NEW_CERT_ID}"

# ── update CDN endpoint ───────────────────────────────────────────────────────

echo "Updating CDN endpoint ${DO_CDN_ENDPOINT_ID}..."
UPDATE_PAYLOAD=$(jq -n \
    --arg domain  "$CDN_DOMAIN" \
    --arg cert_id "$NEW_CERT_ID" \
    '{custom_domain: $domain, certificate_id: $cert_id}')

UPDATE_RESPONSE=$(curl -s -X PUT \
    -H "Authorization: Bearer ${DO_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$UPDATE_PAYLOAD" \
    "${DO_API}/cdn/endpoints/${DO_CDN_ENDPOINT_ID}")

if ! echo "$UPDATE_RESPONSE" | jq -e '.endpoint.id' &>/dev/null; then
    echo "Error: failed to update CDN endpoint." >&2
    echo "$UPDATE_RESPONSE" >&2
    echo "Note: new certificate ${NEW_CERT_ID} was created but not attached — delete it manually if needed." >&2
    exit 1
fi

echo "CDN endpoint updated."

# ── delete old certificate ────────────────────────────────────────────────────

if [[ -n "$OLD_CERT_ID" ]]; then
    echo "Deleting old certificate: ${OLD_CERT_ID}"
    curl -sf -X DELETE \
        -H "Authorization: Bearer ${DO_API_TOKEN}" \
        "${DO_API}/certificates/${OLD_CERT_ID}" || \
        echo "Warning: could not delete old certificate ${OLD_CERT_ID} — remove it manually." >&2
fi

echo "Done. CDN endpoint ${DO_CDN_ENDPOINT_ID} now uses certificate ${NEW_CERT_ID} for ${CDN_DOMAIN}."
