#!/bin/bash
# spc-remove.sh
# Remove smartplug from DB. Supports optional --name and/or --ip.

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR/spc-helpers.sh"

show_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --name <device_name>    Remove device by name.
  --ip   <ipv4_address>   Remove device by IPv4 address.
  -h, --help              Show this help and exit.

Notes:
  - You must provide at least --name or --ip.
  - If both are provided, the script will validate that they match.
    If they don't, it will try to find the device on the network.

Examples:
    $0 --name my_plug
    $0 --ip 192.168.1.100
    $0 --name my_plug --ip 192.168.1.100
EOF
}

# If no arguments are provided, show usage and exit
if [[ $# -eq 0 ]]; then
  show_usage
  exit 1
fi

# Parse arguments
process_arguments "$@"
NAME="$PARSED_NAME"
IP="$PARSED_IP"

# Resolve the target IP using the helper function. It handles all validation and auto-correction.
# NOTE: This command might need to be run with sudo for the arp-scan to work.
TARGET_IP=$(resolve_device_ip "$NAME" "$IP")
if [[ -z "$TARGET_IP" ]]; then
    LOG_FATAL "Could not resolve the specified device. Exiting."
fi

# Now that we have the definitive IP, get the device details for removal
DEVICE_INFO=$(sqlite3 -separator '|' "$DB_FILE" "SELECT id, name FROM devices WHERE ipv4 = '$TARGET_IP';")

if [[ -z "$DEVICE_INFO" ]]; then
    LOG_FATAL "Could not find device details in database for IP \"$TARGET_IP\". The database might be out of sync."
fi

# Extract ID and Name from the query result
DEVICE_ID=$(echo "$DEVICE_INFO" | cut -d'|' -f1)
DEVICE_NAME=$(echo "$DEVICE_INFO" | cut -d'|' -f2)

# Confirm removal
read -p "Are you sure you want to remove device \"$DEVICE_NAME\" (id=$DEVICE_ID) from IP $TARGET_IP? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY](es)?$ ]]; then
  LOG_DEBUG "Operation cancelled."
  exit 0
fi

# Delete using the unique ID
sqlite3 "$DB_FILE" "DELETE FROM devices WHERE id = $DEVICE_ID;"
if [[ $? -ne 0 ]]; then
  LOG_FATAL "Failed to remove device \"$DEVICE_NAME\" (id=$DEVICE_ID)."
fi

LOG_DEBUG "Device \"$DEVICE_NAME\" (id=$DEVICE_ID) removed successfully."
exit 0