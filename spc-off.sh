#!/bin/bash
# Script using for turning smartplug with tasmota firmware off

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the helpers script
source "$SCRIPT_DIR/spc-helpers.sh"

# Function to display usage information
show_usage() {
  # Added more information to the help
  cat <<EOF
Usage: $0 [OPTIONS] <device_name>
       $0 [OPTIONS] <ip_address>
       $0 [OPTIONS]
  Turns a Tasmota smart plug off.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Notes:
  - You can provide a device name, an IP address, or both.
    • If both are provided, they must refer to the same device (name → IP in DB must match the given IP).

Examples:
    $0 my_plug
    $0 192.168.1.100
    $0 --name my_plug
    $0 --ip 192.168.1.100
EOF
}

# If no arguments are provided, show usage and exit
if [[ $# -eq 0 ]]; then
  show_usage
  exit 1
fi

# Processing arguments
process_arguments "$@"
NAME="$PARSED_NAME"
IP="$PARSED_IP"

# Ensure at least one identifier is provided
if [[ -z "$NAME" && -z "$IP" ]]; then
  LOG_ERROR "You must provide at least a device name or an IP address."
  show_usage
  exit 1
fi

# If only NAME is provided, resolve IP from the database
if [[ -n "$NAME" && -z "$IP" ]]; then
  IP=$(sqlite3 "$DB_FILE" "SELECT ipv4 FROM devices WHERE name = '$NAME';")
  if [[ -z "$IP" ]]; then
    LOG_FATAL "No device with name '$NAME' found in the database."
  fi
fi

# If both NAME and IP are provided, verify they match what's in DB (if present)
if [[ -n "$NAME" && -n "$IP" ]]; then
  DB_IP=$(sqlite3 "$DB_FILE" "SELECT ipv4 FROM devices WHERE name = '$NAME';")
  # If the name is found in the DB, check if the IP matches
  if [[ -n "$DB_IP" && "$DB_IP" != "$IP" ]]; then
    LOG_ERROR "Given name '$NAME' maps to IP '$DB_IP' in the database, but IP '$IP' was provided."
    LOG_FATAL "Please fix the mismatch or provide only one of: name or IP."
  # If the name is not in the DB, just warn and proceed with the provided IP
  elif [[ -z "$DB_IP" ]]; then
    LOG_WARN "Name '$NAME' not found in DB; proceeding with provided IP '$IP'."
  fi
fi

# Validate IP format (must be set by now)
if ! validate_ipv4 "$IP"; then
  LOG_FATAL "Invalid IPv4 address: $IP"
fi

TARGET="$IP"

# Send the Power OFF command
LOG_DEBUG "Sending Power OFF command to $TARGET..."
if curl -s "http://$TARGET/cm?cmnd=Power%20OFF" > /dev/null; then
  LOG_DEBUG "Command sent successfully to $TARGET"
else
  LOG_FATAL "Failed to send Power OFF command to $TARGET. The device may be offline."
fi

exit 0