#!/bin/bash
# spc-remove.sh
# Remove smartplug from DB. Supports optional --name and/or --ip.
# If no flags are provided, the script will show usage and exit.

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
  - If both are provided, they must refer to the same device in the database.

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

# Ensure at least one identifier is provided
if [[ -z "$NAME" && -z "$IP" ]]; then
  LOG_ERROR "You must provide a device name (--name) or an IP address (--ip)."
  show_usage
  exit 1
fi

# If both name and IP are provided, verify they match in the database
if [[ -n "$NAME" && -n "$IP" ]]; then
  DB_IP=$(sqlite3 "$DB_FILE" "SELECT ipv4 FROM devices WHERE name = ?;" "$NAME")
  
  # Check if the name exists at all
  if [[ -z "$DB_IP" ]]; then
    LOG_FATAL "Device with name \"$NAME\" not found in the database."
  fi

  # Check if the found IP matches the provided IP
  if [[ "$DB_IP" != "$IP" ]]; then
    LOG_FATAL "Mismatch: Device \"$NAME\" exists but has IP \"$DB_IP\", not the provided IP \"$IP\"."
  fi
fi


# Determine which identifier to use for the final lookup
if [[ -n "$NAME" ]]; then
  # Find device by name. We use a separator '|' to safely parse the output.
  DEVICE_INFO=$(sqlite3 -separator '|' "$DB_FILE" "SELECT id, name FROM devices WHERE name = ?;" "$NAME")
  if [[ -z "$DEVICE_INFO" ]]; then
    # This case is redundant if both name and ip were provided, but necessary if only name was.
    LOG_FATAL "Device with name \"$NAME\" not found in the database."
  fi
elif [[ -n "$IP" ]]; then
  # Find device by IP
  DEVICE_INFO=$(sqlite3 -separator '|' "$DB_FILE" "SELECT id, name FROM devices WHERE ipv4 = ?;" "$IP")
  if [[ -z "$DEVICE_INFO" ]]; then
    LOG_FATAL "Device with IP \"$IP\" not found in the database."
  fi
fi

# Extract ID and Name from the query result
DEVICE_ID=$(echo "$DEVICE_INFO" | cut -d'|' -f1)
DEVICE_NAME=$(echo "$DEVICE_INFO" | cut -d'|' -f2)


# Confirm removal
read -p "Are you sure you want to remove device \"$DEVICE_NAME\" (id=$DEVICE_ID)? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY](es)?$ ]]; then
  LOG_INFO "Operation cancelled."
  exit 0
fi

# Delete
sqlite3 "$DB_FILE" "DELETE FROM devices WHERE id = ?;" "$DEVICE_ID"
if [[ $? -ne 0 ]]; then
  LOG_FATAL "Failed to remove device \"$DEVICE_NAME\" (id=$DEVICE_ID)."
fi

LOG_INFO "Device \"$DEVICE_NAME\" (id=$DEVICE_ID) removed successfully."
exit 0