#!/bin/bash
# spc-remove.sh
# Remove smartplug from DB. Supports optional --name and/or --ip.
# If no flags provided, prompts interactively for name (no interactive IP prompt).

source ./spc-helpers.sh

show_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --name <device_name>    Remove device by name
  --ip   <ipv4_address>   Remove device by IPv4 address
  -h, --help              Show this help and exit

Notes:
  - You may provide --name, --ip, both, or none.
  - If both provided, --name is used.

Examples:
    $0 --name my_plug
    $0 --ip 192.168.1.100
    $0 --name my_plug --ip 192.168.1.100
EOF
}

# Parse args (both optional)
NAME=""
IP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_usage
      exit 0
      ;;
    --name)
      if [ -n "$2" ]; then
        NAME="$2"
        shift 2
      else
        echo "ERROR: Missing value for --name" >&2
        exit 1
      fi
      ;;
    --ip)
      if [ -n "$2" ]; then
        IP="$2"
        shift 2
      else
        echo "ERROR: Missing value for --ip" >&2
        exit 1
      fi
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      show_usage
      exit 1
      ;;
    *)
      # treat lone positional as name if name not set
      if [ -z "$NAME" ]; then
        NAME="$1"
      fi
      shift
      ;;
  esac
done

# Determine which identifier to use:
# Priority: NAME (if given) > IP (if given)
if [[ -n "$NAME" ]]; then
  # find device by name
  DEVICE_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM devices WHERE name = ?;" "$NAME")
  if [[ -z "$DEVICE_ID" ]]; then
    echo "ERROR: Device with name \"$NAME\" not found in database." >&2
    exit 1
  fi
  DEVICE_NAME="$NAME"
else
  # use IP (we know IP is non-empty here)
  DEVICE_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM devices WHERE ipv4 = ?;" "$IP")
  if [[ -z "$DEVICE_ID" ]]; then
    echo "ERROR: Device with IP \"$IP\" not found in database." >&2
    exit 1
  fi
  # get friendly name if any
  DEVICE_NAME=$(sqlite3 "$DB_FILE" "SELECT name FROM devices WHERE id = ?;" "$DEVICE_ID")
fi

# Confirm removal
read -p "Are you sure you want to remove device \"$DEVICE_NAME\" (id=$DEVICE_ID)? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY](es)?$ ]]; then
  echo "Operation cancelled."
  exit 0
fi

# Delete
sqlite3 "$DB_FILE" "DELETE FROM devices WHERE id = ?;" "$DEVICE_ID"
if [[ $? -ne 0 ]]; then
  echo "ERROR: Failed to remove device \"$DEVICE_NAME\" (id=$DEVICE_ID)." >&2
  exit 1
fi

echo "Device \"$DEVICE_NAME\" (id=$DEVICE_ID) removed successfully."
exit 0