#!/bin/sh

# Add dependencies
apk add --no-cache curl jq

echo "Starting Proxmox Sync Service..."

while true; do
  # 1. Fetch bans from CrowdSec
  CS_BANS=$(curl -s -H "X-Api-Key: $BOUNCER_KEY" "http://localhost:${CROWDSEC_PORT:-8080}/v1/decisions" | jq -r '.[].value // empty' | sort)

  # 2. Fetch current Proxmox IP Set
  PVE_BANS=$(curl -s -k -H "Authorization: PVEAPIToken=$PVE_TOKEN_ID=$PVE_TOKEN_SECRET" \
    "https://localhost:${PVE_PORT:-8006}/api2/json/cluster/firewall/ipset/crowdsec_bans" | jq -r '.data[].cidr // empty' | sort)

  # 3. Add new bans
  for ip in $CS_BANS; do
    if ! echo "$PVE_BANS" | grep -q "$ip"; then
      echo "Adding $ip to Proxmox..."
      curl -s -k -X POST -H "Authorization: PVEAPIToken=$PVE_TOKEN_ID=$PVE_TOKEN_SECRET" \
        -d "cidr=$ip" "https://localhost:${PVE_PORT:-8006}/api2/json/cluster/firewall/ipset/crowdsec_bans" > /dev/null
    fi
  done

  # 4. Remove expired bans
  for ip in $PVE_BANS; do
    if ! echo "$CS_BANS" | grep -q "$ip"; then
      echo "Removing $ip from Proxmox..."
      curl -s -k -X DELETE -H "Authorization: PVEAPIToken=$PVE_TOKEN_ID=$PVE_TOKEN_SECRET" \
        "https://localhost:${PVE_PORT:-8006}/api2/json/cluster/firewall/ipset/crowdsec_bans/$ip" > /dev/null
    fi
  done

  sleep 300
done
