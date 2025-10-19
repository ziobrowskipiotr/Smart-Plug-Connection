#!/bin/bash
# Script for checking the simple power state (ON/OFF) of a Tasmota smartplug
# It outputs ONLY the state ("ON" or "OFF") and uses exit codes for success/failure.

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the helpers script
source "$SCRIPT_DIR/spc-helpers.sh"

# Function to display usage information
show_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]
  Outputs the power state ("ON" or "OFF") of a Tasmota smart plug.
  Exits with 0 on success, 1 on failure.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.
EOF
}

# --- Argument Parsing ---
if [[ $# -eq 0 ]]; then
  show_usage >&2 # Show usage on stderr
  exit 1
fi

process_arguments "$@"
NAME="$PARSED_NAME"
IP="$PARSED_IP"

# --- Device Resolution ---
# All logs/errors from this function will go to stderr. The script's stdout remains clean.
TARGET_IP=$(resolve_device_ip "$NAME" "$IP")
if [[ -z "$TARGET_IP" ]]; then
    exit 1
fi

# --- State Retrieval ---
STATE=$(check_state "$TARGET_IP")

# --- Output and Exit ---
if [[ "$STATE" == "ON" || "$STATE" == "OFF" ]]; then
  echo "$STATE"
  LOG_INFO "Device at $TARGET_IP is currently: $STATE"
  exit 0
else
  # The check_state function might not produce a log, so let's add one.
  # All logs from spc-logging go to stderr by default.
  LOG_FATAL "Could not retrieve state from $TARGET_IP. Device may be offline."
fi