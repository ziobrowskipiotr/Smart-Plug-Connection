#!/bin/bash
# Script for retrieving full status and energy data from a Tasmota device.

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the helpers script
source "$SCRIPT_DIR/spc-helpers.sh"

# Function to display usage information
show_usage() {
  cat <<EOF
Usage: $0 (--name <device_name> | --ip <ip_address>)
  Retrieves full status (state, power, voltage, etc.) from a device
  and returns it in JSON format.

Required Arguments:
  - An identifier for the device:
      --name <device_name>   Specify the device by its name.
      --ip <ip_address>       Specify the device by its IP address.

Other Options:
  -h, --help              Display this help message and exit.

Examples:
    $0 --name kitchen_plug
    $0 --ip 192.168.1.105
EOF
}

# --- Argument Parsing ---
# Using the helper function to parse --name and --ip
process_arguments "$@"
NAME="$PARSED_NAME"
IP="$PARSED_IP"

# --- Validation of inputs ---
if [[ -z "$NAME" && -z "$IP" ]]; then
  LOG_ERROR "You must identify the device using --name or --ip." >&2
  show_usage
  exit 1
fi

# --- Resolve Device IP ---
# Use the helper to get the definitive IP address.
# This relies on the corrected spc-helpers.sh file!
TARGET_IP=$(resolve_device_ip "$NAME" "$IP")
if [[ -z "$TARGET_IP" ]]; then
    # resolve_device_ip logs its own errors, so we just exit if it failed.
    exit 1
fi

LOG_DEBUG "Querying device at IP: $TARGET_IP"

# --- Main Logic: Get Data from Device ---
# Send a single request for 'Status 8', which contains all the energy data.
response=$(curl -s --connect-timeout 3 "http://$TARGET_IP/cm?cmnd=Status%208")

if [[ -z "$response" ]]; then
    LOG_FATAL "No response from device at $TARGET_IP. It might be offline."
fi

# Additionally, get the power state from a separate command
power_state=$(check_state "$TARGET_IP")

# --- Parse and Construct JSON ---
# Use jq to extract all required fields from the response and build a new JSON object.
# The '-n' flag creates a new JSON object from scratch.
# The '--arg' flags safely pass shell variables into the jq script.
json_output=$(jq -n \
  --arg name "$(sqlite3 "$DB_FILE" "SELECT name FROM devices WHERE ipv4 = '$TARGET_IP';")" \
  --arg ip "$TARGET_IP" \
  --arg state "$power_state" \
  --argjson data "$response" \
  '{
    "name": $name,
    "ip": $ip,
    "state": $state,
    "voltage": ($data.StatusSNS.ENERGY.Voltage // null),
    "current": ($data.StatusSNS.ENERGY.Current // null),
    "active_power": ($data.StatusSNS.ENERGY.Power // null),
    "energy_today": ($data.StatusSNS.ENERGY.Today // null),
    "energy_yesterday": ($data.StatusSNS.ENERGY.Yesterday // null),
    "energy_total": ($data.StatusSNS.ENERGY.Total // null)
  }')

# Check if jq failed (e.g., due to invalid response from curl)
if [[ $? -ne 0 ]]; then
    LOG_FATAL "Failed to parse JSON response from the device."
fi

# --- Output the result ---
echo "$json_output"

exit 0