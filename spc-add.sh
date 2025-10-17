#!/bin/bash
# Script using for adding smartplug with tasmota firmware to the database

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the helpers script
source "$SCRIPT_DIR/spc-helpers.sh"

# Function to display usage information
show_usage() {
  # Added more information to the help
  cat <<EOF
Usage: $0 [OPTIONS] <device_name> <ip_address>
       $0 [OPTIONS]
  Adds or updates a Tasmota smartplug in the database.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Notes:
  - You must provide both device name and IP address, either as positional arguments or using the flags.
  - If both positional arguments and flags are provided, the flags take precedence.

Examples:
    $0 my_plug 192.168.1.100
    $0 --name my_plug --ip 192.168.1.100
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

# Check if both variables (name and IP) are set
if [[ -z "$NAME" ]] || [[ -z "$IP" ]]; then
  LOG_ERROR "Both device name and IP address are required."
  show_usage
  exit 1
fi

# Check if user has internet connection
if ! check_connection; then
  LOG_FATAL "Check your internet connection"
fi

# Check if the name is valid
if ! validate_device_name "$NAME"; then
  LOG_FATAL "Invalid device name."
fi

# Check if the name is already in the database
if sqlite3 "$DB_FILE" "SELECT name FROM devices WHERE name = ?;" "$NAME" | grep -q .; then
  LOG_FATAL "Device with name \"$NAME\" is already in the database"
fi

if ! validate_ipv4 "$IP"; then
  LOG_ERROR "IP address is not in correct format"
  LOG_FATAL "Correct format is x.x.x.x"
fi

# Get IP address and mask of the connector
connector_ip_and_mask=$(get_connector_ip_and_mask)
if [ $? -ne 0 ]; then
  LOG_FATAL "Failed to get the connector IP address and mask"
fi

# Check if the IP address is in the same subnet as the connector
if ! is_ip_in_same_subnet "$IP" "$connector_ip_and_mask"; then
  LOG_FATAL "IP address \"$IP\" is not in the same subnet as the connector"
fi

# Check if the IP address is already in the database
if sqlite3 "$DB_FILE" "SELECT ipv4 FROM devices WHERE ipv4 = ?;" "$IP" | grep -q .; then
  LOG_FATAL "Device with IP address \"$IP\" is already in the database"
  exit 1
fi

# Check if the device is available
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://"$IP") 
if (( STATUS_CODE!=200 )); then
  LOG_FATAL "IP address of smartplug is unavailable"
fi

# Check if the device is running Tasmota firmware
if ! check_tasmota_firmware "$IP"; then
  LOG_FATAL "Device is not running Tasmota firmware"
fi

# Check MAC address of the device
ping -c 1 -W 1 "$IP" &> /dev/null # Send a single ping request with a 1 second timeout
MAC_ADDRESS=$(ip neigh show "$IP" | awk '{print $5}')
if [ -z "$MAC_ADDRESS" ]; then
  LOG_FATAL "Failed to retrieve MAC address for IP $IP"
fi

# Check the state of the smartplug
STATE=$(check_state "$IP")
if [ "$STATE" != "ON" ] && [ "$STATE" != "OFF" ]; then
  LOG_FATAL "Connector is unable to get state of the device"
fi

echo "Smartplug with IP address \"$IP\" is available"

# Add device to the database or change its name and IP address
if (check_MAC_in_db "$MAC_ADDRESS"); then
    LOG_INFO "Device with MAC address $MAC_ADDRESS is already in the database"
    LOG_INFO "Changing name and IP address of the device..."
    sqlite3 "$DB_FILE" "UPDATE devices SET ipv4 = ?, name = ? WHERE mac = ?;" "$IP" "$NAME" "$MAC_ADDRESS"
    if [ $? -ne 0 ]; then
        LOG_FATAL "Failed to update the device in the database."
    fi
    LOG_INFO "Device updated successfully."
else
    LOG_INFO "Adding device to the database..."
    sqlite3 "$DB_FILE" "INSERT INTO devices (name, ipv4, mac) VALUES (?, ?, ?);" "$NAME" "$IP" "$MAC_ADDRESS"
    if [ $? -ne 0 ]; then
        LOG_FATAL "Failed to add the device to the database."
    fi
    LOG_INFO "Device added successfully."
fi

exit 0