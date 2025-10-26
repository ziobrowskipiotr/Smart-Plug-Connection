#!/bin/bash
# Script for retrieving a device's name from the database.

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the helpers script
source "$SCRIPT_DIR/spc-helpers.sh"

# Function to display usage information
show_usage() {
  cat <<EOF
Usage: $0 (--name <current_name> | --ip <ip_address>)
  Retrieves the name of a device from the database.

Required Arguments:
  - An identifier for the device to be retrieved:
      --name <current_name>   Specify the device by its current name.
      --ip <ip_address>       Specify the device by its IP address.

Other Options:
  -h, --help              Display this help message and exit.

Examples:
    $0 --name kitchen_plug
    $0 --ip 192.168.1.105
EOF
}

# --- Custom Argument Parsing for this script ---
CURRENT_NAME=""
IP=""

if [[ $# -eq 0 ]]; then
  show_usage >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_usage
      exit 0
      ;;
    --name)
      CURRENT_NAME="$2"
      shift 2
      ;;
    --ip)
      IP="$2"
      shift 2
      ;;
    *)
      LOG_ERROR "Unknown option: $1"
      show_usage >&2
      exit 1
      ;;
  esac
done

# --- Validation of inputs ---
if [[ -z "$CURRENT_NAME" && -z "$IP" ]]; then
  LOG_ERROR "You must identify the device using --name or --ip." >&2
  exit 1
fi

# --- Resolve Device and Find Name ---
# Use the helper to get the definitive IP address.
TARGET_IP=$(resolve_device_ip "$CURRENT_NAME" "$IP")
if [[ -z "$TARGET_IP" ]]; then
    # resolve_device_ip logs its own errors, so we just exit if it failed.
    exit 1
fi

# Now that we have a confirmed IP, we fetch the name from the DB.
DEVICE_NAME=$(sqlite3 "$DB_FILE" "SELECT name FROM devices WHERE ipv4 = '$TARGET_IP';")

if [[ -z "$DEVICE_NAME" ]]; then
    LOG_FATAL "Device with IP \"$TARGET_IP\" not found in the database."
fi

# --- Output the result ---
# Simply print the retrieved name to standard output.
echo "$DEVICE_NAME"
exit 0