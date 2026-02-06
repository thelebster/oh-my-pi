#!/bin/bash
# Remove Cloudflare Tunnel ingress rules (reset to catch-all only).
# Usage: cloudflare-tunnel-deconfigure.sh
#
# Requires: CF_API_TOKEN, CF_ZONE_ID, CF_TUNNEL_TOKEN, CF_TUNNEL_SSH_HOST, CF_TUNNEL_HTTP_HOST

set -euo pipefail

if [[ -z "${CF_API_TOKEN:-}" || -z "${CF_ZONE_ID:-}" || -z "${CF_TUNNEL_TOKEN:-}" ]]; then
  echo "Error: CF_API_TOKEN, CF_ZONE_ID, and CF_TUNNEL_TOKEN must be set" >&2
  exit 1
fi

ACCOUNT_ID=$(echo "$CF_TUNNEL_TOKEN" | base64 -d 2>/dev/null | jq -r '.a')
TUNNEL_ID=$(echo "$CF_TUNNEL_TOKEN" | base64 -d 2>/dev/null | jq -r '.t')

if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "null" || -z "$TUNNEL_ID" || "$TUNNEL_ID" == "null" ]]; then
  echo "Error: could not extract account/tunnel ID from CF_TUNNEL_TOKEN" >&2
  exit 1
fi

ZONE_NAME=$(curl -s -H "Authorization: Bearer ${CF_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}" | jq -r '.result.name')

if [[ -z "$ZONE_NAME" || "$ZONE_NAME" == "null" ]]; then
  echo "Error: could not get zone name from CF_ZONE_ID" >&2
  exit 1
fi

# Clear ingress rules (catch-all only)
PAYLOAD='{"config": {"ingress": [{"service": "http_status:404"}]}}'

RESULT=$(curl -s -X PUT \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations")

if echo "$RESULT" | jq -e '.success' > /dev/null 2>&1; then
  echo "Tunnel ingress rules cleared"
else
  echo "Error: $(echo "$RESULT" | jq -r '.errors')" >&2
  exit 1
fi

# Remove DNS records
CF_DNS_API="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records"

for SUBDOMAIN in "${CF_TUNNEL_SSH_HOST:-}" "${CF_TUNNEL_HTTP_HOST:-}"; do
  [[ -z "$SUBDOMAIN" ]] && continue
  FQDN="${SUBDOMAIN}.${ZONE_NAME}"

  RECORD_ID=$(curl -s -H "Authorization: Bearer ${CF_API_TOKEN}" \
    "${CF_DNS_API}?type=CNAME&name=${FQDN}" | jq -r '.result[0].id // empty')

  if [[ -n "$RECORD_ID" ]]; then
    curl -s -X DELETE -H "Authorization: Bearer ${CF_API_TOKEN}" \
      "${CF_DNS_API}/${RECORD_ID}" > /dev/null
    echo "Removed DNS: ${FQDN}"
  fi
done
