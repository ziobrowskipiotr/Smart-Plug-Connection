#!/bin/bash
# Script for checking the current voltage of a Tasmota smartplug.

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the helpers script
source "$SCRIPT_DIR/spc-helpers.sh"

# Function to display usage information
show_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]
  Outputs the current voltage (in Volts) of a Tasmota smart plug.
  Exits with 0 on success, 1 on failure.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.
EOF
}

# --- Argument Parsing ---
if [[ $# -eq 0 ]]; then
  show_usage >&2
  exit 1
fi

process_arguments "$@"
NAME="$PARSED_NAME"
IP="$PARSED_IP"

# --- Device Resolution ---
# All logs/errors will go to stderr, keeping stdout clean.
TARGET_IP=$(resolve_device_ip "$NAME" "$IP")
if [[ -z "$TARGET_IP" ]]; then
    LOG_FATAL "Could not resolve the specified device. Exiting."
fi

# --- Voltage Retrieval ---
VOLTAGE=$(get_voltage "$TARGET_IP")

# --- Output and Exit ---
# Check if the result is a valid number.
if [[ "$VOLTAGE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "$VOLTAGE"
  LOG_INFO "Current voltage of device at $TARGET_IP is: $VOLTAGE V"
  exit 0
else
  # Log error to stderr
  LOG_FATAL "Could not retrieve voltage data from $TARGET_IP."
fi