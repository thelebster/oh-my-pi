#!/bin/bash
# Configure Cloudflare Tunnel ingress rules and DNS records.
# Usage: cloudflare-tunnel-configure.sh
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

# Build ingress rules
INGRESS="[]"

if [[ -n "${CF_TUNNEL_HTTP_HOST:-}" ]]; then
  FQDN="${CF_TUNNEL_HTTP_HOST}.${ZONE_NAME}"
  INGRESS=$(echo "$INGRESS" | jq --arg h "$FQDN" '. + [{"hostname": $h, "service": "http://localhost:80", "originRequest": {}}]')
  echo "Route: ${FQDN} -> http://localhost:80"
  INGRESS=$(echo "$INGRESS" | jq --arg h "$FQDN" '. + [{"hostname": $h, "service": "https://localhost:443", "originRequest": {"noTLSVerify": true}}]')
  echo "Route: ${FQDN} -> https://localhost:443"
fi

if [[ -n "${CF_TUNNEL_SSH_HOST:-}" ]]; then
  FQDN="${CF_TUNNEL_SSH_HOST}.${ZONE_NAME}"
  INGRESS=$(echo "$INGRESS" | jq --arg h "$FQDN" '. + [{"hostname": $h, "service": "ssh://localhost:22", "originRequest": {}}]')
  echo "Route: ${FQDN} -> ssh://localhost:22"
fi

# Catch-all rule (required)
INGRESS=$(echo "$INGRESS" | jq '. + [{"service": "http_status:404"}]')

PAYLOAD=$(jq -n --argjson ingress "$INGRESS" '{"config": {"ingress": $ingress}}')

RESULT=$(curl -s -X PUT \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations")

if echo "$RESULT" | jq -e '.success' > /dev/null 2>&1; then
  echo "Tunnel ingress configured"
else
  echo "Error configuring ingress: $(echo "$RESULT" | jq -r '.errors')" >&2
  exit 1
fi

# Create DNS CNAME records
CF_DNS_API="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records"
TUNNEL_TARGET="${TUNNEL_ID}.cfargotunnel.com"

for SUBDOMAIN in "${CF_TUNNEL_HTTP_HOST:-}" "${CF_TUNNEL_SSH_HOST:-}"; do
  [[ -z "$SUBDOMAIN" ]] && continue
  FQDN="${SUBDOMAIN}.${ZONE_NAME}"

  EXISTING=$(curl -s -H "Authorization: Bearer ${CF_API_TOKEN}" \
    "${CF_DNS_API}?type=CNAME&name=${FQDN}" | jq -r '.result[0].id // empty')

  if [[ -n "$EXISTING" ]]; then
    echo "DNS: ${FQDN} already exists"
  else
    RESULT=$(curl -s -X POST -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"type\":\"CNAME\",\"name\":\"${SUBDOMAIN}\",\"content\":\"${TUNNEL_TARGET}\",\"proxied\":true}" \
      "${CF_DNS_API}")
    if echo "$RESULT" | jq -e '.success' > /dev/null 2>&1; then
      echo "DNS: created ${FQDN} -> ${TUNNEL_TARGET}"
    else
      echo "Error creating DNS ${FQDN}: $(echo "$RESULT" | jq -r '.errors[0].message // .errors')" >&2
      exit 1
    fi
  fi
done
