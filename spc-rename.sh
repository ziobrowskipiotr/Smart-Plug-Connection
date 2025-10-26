#!/bin/bash
# Script for renaming a device in the database.

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the helpers script
source "$SCRIPT_DIR/spc-helpers.sh"

# Function to display usage information
show_usage() {
  cat <<EOF
Usage: $0 (--name <current_name> | --ip <ip_address>) --new-name <new_name>
  Renames a device in the database.

Required Arguments:
  - An identifier for the device to be renamed:
      --name <current_name>   Specify the device by its current name.
      --ip <ip_address>       Specify the device by its IP address.
  
  - The new name for the device:
      --new-name <new_name>   Provide the new name.

Other Options:
  -h, --help              Display this help message and exit.

Examples:
    $0 --name old_plug --new-name kitchen_plug
    $0 --ip 192.168.1.105 --new-name office_lamp
EOF
}

# --- Custom Argument Parsing for this script ---
CURRENT_NAME=""
IP=""
NEW_NAME=""

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
    --new-name)
      NEW_NAME="$2"
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
  LOG_ERROR "You must identify the device to rename using --name or --ip." >&2
  exit 1
fi

if [[ -z "$NEW_NAME" ]]; then
  LOG_ERROR "You must provide a new name using --new-name." >&2
  exit 1
fi

# Validate the new name format
if ! validate_device_name "$NEW_NAME"; then
    exit 1
fi

# Check if the new name is already taken
if sqlite3 "$DB_FILE" "SELECT id FROM devices WHERE name = '$NEW_NAME';" | grep -q .; then
    LOG_FATAL "The name \"$NEW_NAME\" is already in use by another device."
fi


# --- Resolve Device and Find ID ---
# Use the helper to get the definitive IP address.
# This handles validation and potential auto-correction via MAC address if both name and IP were provided but didn't match.
TARGET_IP=$(resolve_device_ip "$CURRENT_NAME" "$IP")
if [[ -z "$TARGET_IP" ]]; then
    # resolve_device_ip logs its own errors, so we just exit if it failed.
    exit 1
fi

# Now that we have a confirmed IP, we fetch the ID and current name from the DB.
# We need the ID for a safe renaming operation.
DEVICE_INFO=$(sqlite3 -separator '|' "$DB_FILE" "SELECT id, name FROM devices WHERE ipv4 = '$TARGET_IP';")

if [[ -z "$DEVICE_INFO" ]]; then
    # This might happen if resolve_device_ip returned an IP that isn't actually in the DB 
    # (e.g. if only --ip was provided and it was a typo not present in DB).
    LOG_FATAL "Device with IP \"$TARGET_IP\" not found in the database."
fi

DEVICE_ID=$(echo "$DEVICE_INFO" | cut -d'|' -f1)
CURRENT_DISPLAY_NAME=$(echo "$DEVICE_INFO" | cut -d'|' -f2)


# --- Perform Rename ---
LOG_DEBUG "Renaming device \"$CURRENT_DISPLAY_NAME\" (ID: $DEVICE_ID, IP: $TARGET_IP) to \"$NEW_NAME\"..."

sqlite3 "$DB_FILE" "UPDATE devices SET name = '$NEW_NAME' WHERE id = $DEVICE_ID;"

# --- Confirmation ---
if [[ $? -eq 0 ]]; then
  LOG_DEBUG "Success! Device renamed to \"$NEW_NAME\"."
  exit 0
else
  LOG_FATAL "Failed to update the database."
fi