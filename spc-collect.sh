#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "$( realpath "${BASH_SOURCE[0]}" )" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/spc-helpers.sh"
cd "$PROJECT_ROOT" || exit 1

LOG_INFO "Collecting Tasmota energy totals..."

sqlite3 "$DB_FILE" "SELECT name FROM devices;" | while read -r dev; do
    LOG_INFO "Processing device: $dev"

    # update ipv4 by MAC
    ip=$(find_and_update_ip_by_mac "$dev")
    if [[ -z "$ip" ]]; then
        LOG_WARN "$dev offline. Skipping."
        continue
    fi

    # HTTP request to Tasmota
    json=$(curl -s --max-time 5 "http://$ip/cm?cmnd=Status%208")

    if [[ -z "$json" ]]; then
        LOG_WARN "No response for $dev"
        continue
    fi

    # Extract total energy
    energy=$(echo "$json" | jq '.StatusSNS.ENERGY.Total // empty')

    if [[ -z "$energy" ]]; then
        LOG_WARN "Failed to parse energy for $dev"
        continue
    fi

    LOG_DEBUG "Energy total for $dev = $energy"
- this query is compatible with your sqlite3 version
    sqlite3 "$DB_FILE" \
      "INSERT INTO measurements(device_id, energy_total)
       VALUES((SELECT id FROM devices WHERE name = '$dev'), $energy);"

    LOG_INFO "Recorded measurement for $dev"
done

LOG_INFO "Collection complete."