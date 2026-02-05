#!/bin/bash
# Update Cloudflare DNS A record with current public IP
set -euo pipefail

[ -f /etc/cloudflare-ddns.env ] && source /etc/cloudflare-ddns.env

CURRENT_IP=$(curl -s ifconfig.me)
DNS_IP=$(dig +short "$CF_DOMAIN" @1.1.1.1)

if [ "$CURRENT_IP" = "$DNS_IP" ]; then
  exit 0
fi

RECORD_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=$CF_DOMAIN&type=A" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  | jq -r '.result[0].id')

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" = "null" ]; then
  logger "cloudflare-ddns: ERROR - Could not find A record for $CF_DOMAIN"
  exit 1
fi

curl -s -X PUT \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"$CF_DOMAIN\",\"content\":\"$CURRENT_IP\",\"ttl\":300}" \
  > /dev/null

logger "cloudflare-ddns: Updated $CF_DOMAIN from $DNS_IP to $CURRENT_IP"
