#!/bin/bash
# Create or update a Cloudflare Cache Rule for HLS streaming.
# Tells Cloudflare edge to cache .ts/.m3u8 files, respecting origin Cache-Control headers.
#
# Requires: CF_API_TOKEN, CF_ZONE_ID, CF_CACHE_HOSTNAME (FQDN, e.g. cam.example.com)

set -euo pipefail

if [[ -z "${CF_API_TOKEN:-}" || -z "${CF_ZONE_ID:-}" || -z "${CF_CACHE_HOSTNAME:-}" ]]; then
  echo "Error: CF_API_TOKEN, CF_ZONE_ID, and CF_CACHE_HOSTNAME must be set" >&2
  exit 1
fi

CF_API="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/rulesets/phases/http_request_cache_settings/entrypoint"
RULE_DESC="Cache HLS stream: ${CF_CACHE_HOSTNAME}"

# Get existing ruleset (may not exist yet)
EXISTING=$(curl -s -H "Authorization: Bearer ${CF_API_TOKEN}" "$CF_API")

if echo "$EXISTING" | jq -e '.success' > /dev/null 2>&1; then
  # Remove existing rule with same description (if any) so we can recreate it
  EXISTING_RULES=$(echo "$EXISTING" | jq --arg desc "$RULE_DESC" '.result.rules // [] | map(select(.description != $desc))')
else
  EXISTING_RULES="[]"
fi

NEW_RULE=$(jq -n --arg hostname "$CF_CACHE_HOSTNAME" --arg desc "$RULE_DESC" '{
  expression: "(http.host eq \"\($hostname)\")",
  action: "set_cache_settings",
  action_parameters: {
    cache: true,
    edge_ttl: {
      mode: "respect_origin"
    },
    browser_ttl: {
      mode: "override_origin",
      default: 10
    }
  },
  description: $desc
}')

ALL_RULES=$(echo "$EXISTING_RULES" | jq --argjson rule "$NEW_RULE" '. + [$rule]')
PAYLOAD=$(jq -n --argjson rules "$ALL_RULES" '{"rules": $rules}')

RESULT=$(curl -s -X PUT \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$CF_API")

if echo "$RESULT" | jq -e '.success' > /dev/null 2>&1; then
  echo "Cache rule created for ${CF_CACHE_HOSTNAME}"
else
  echo "Error creating cache rule: $(echo "$RESULT" | jq -r '.errors[0].message // .errors')" >&2
  exit 1
fi
