#!/bin/bash
# Apply pre-defined Cloudflare Tunnel ingress config and create DNS records.
# Reads ingress rules from CF_TUNNEL_INGRESS (JSON array).
#
# Requires: CF_API_TOKEN, CF_ZONE_ID, CF_TUNNEL_TOKEN, CF_TUNNEL_INGRESS

set -euo pipefail

if [[ -z "${CF_API_TOKEN:-}" || -z "${CF_ZONE_ID:-}" || -z "${CF_TUNNEL_TOKEN:-}" ]]; then
  echo "Error: CF_API_TOKEN, CF_ZONE_ID, and CF_TUNNEL_TOKEN must be set" >&2
  exit 1
fi

if [[ -z "${CF_TUNNEL_INGRESS:-}" ]]; then
  echo "Error: CF_TUNNEL_INGRESS must be set (JSON array of ingress rules)" >&2
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

# Resolve bare subdomains to FQDNs and ensure defaults
INGRESS=$(echo "$CF_TUNNEL_INGRESS" | jq --arg zone "$ZONE_NAME" '
  [.[] |
    # Resolve bare subdomains (no dot) to FQDNs
    if .hostname and (.hostname | contains(".") | not) then
      .hostname = .hostname + "." + $zone
    else . end |
    # Default originRequest to {} for rules with a hostname
    if .hostname and (has("originRequest") | not) then
      .originRequest = {}
    else . end
  ]
')

# Ensure catch-all exists as last rule
HAS_CATCHALL=$(echo "$INGRESS" | jq '.[length-1] | has("hostname") | not')
if [[ "$HAS_CATCHALL" != "true" ]]; then
  INGRESS=$(echo "$INGRESS" | jq '. + [{"service": "http_status:404"}]')
fi

# Log routes
echo "$INGRESS" | jq -r '.[] | select(.hostname) | "Route: \(.hostname) -> \(.service)"'

# Push ingress config
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

# Create DNS CNAME records for all unique hostnames
CF_DNS_API="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records"
TUNNEL_TARGET="${TUNNEL_ID}.cfargotunnel.com"

HOSTNAMES=$(echo "$INGRESS" | jq -r '[.[] | select(.hostname) | .hostname] | unique | .[]')

while IFS= read -r FQDN; do
  [[ -z "$FQDN" ]] && continue
  SUBDOMAIN="${FQDN%.${ZONE_NAME}}"

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
done <<< "$HOSTNAMES"
