#!/bin/bash
# Script using for adding smartplug with tasmota firmware to the database

# Source the helpers script
source ./spc-helpers.sh

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

# Initialize variables
NAME=""
IP=""

# If no arguments are provided, show usage and exit
if [[ $# -eq 0 ]]; then
  show_usage
  exit 1
fi

# Processing arguments in a loop. This logic now handles all flags.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_usage
      exit 0 # Exit with code 0 (success) since the user requested help
      ;;
    --name)
      # Check if a value was provided for the flag
      if [ -n "$2" ]; then
        NAME="$2"
        shift 2 # Move past --name and its value
      else
        LOG_ERROR "Missing argument for --name option."
        exit 1
      fi
      ;;
    --ip)
      # Check if a value was provided for the flag
      if [ -n "$2" ]; then
        IP="$2"
        shift 2 # Move past --ip and its value
      else
        LOG_ERROR "Missing argument for --ip option."
        exit 1
      fi
      ;;
    -*)
      # Handling unknown flags (starting with -)
      LOG_ERROR "Unknown option: $1"
      show_usage
      exit 1
      ;;
    *)
      # Handling positional arguments (if no flags were used)
      # If NAME is not set yet, this is the first positional argument
      if [ -z "$NAME" ]; then
        NAME="$1"
      # If IP is not set yet, this is the second positional argument
      elif [ -z "$IP" ]; then
        IP="$1"
      fi
      shift 1 # Move past the positional argument
      ;;
  esac
done

# Check if both variables (name and IP) are set
if [[ -z "$NAME" ]] || [[ -z "$IP" ]]; then
  LOG_FATAL "Both device name and IP address are required."
  show_usage
  exit 1
fi

# Check if user has internet connection
if ! check_connection; then
  LOG_FATAL "Check your internet connection"
  exit 1
fi

# Check if the name is valid
if ! validate_device_name "$NAME"; then
  LOG_ERROR "Invalid device name."
  exit 1
fi

# Check if the name is already in the database
if sqlite3 "$DB_FILE" "SELECT name FROM devices WHERE name = ?;" "$NAME" | grep -q .; then
  LOG_ERROR "Device with name \"$NAME\" is already in the database"
  LOG_WARN "Choose another name"
  exit 1
fi

if ! validate_ipv4 "$IP"; then
  LOG_ERROR "IP address is not in correct format"
  LOG_WARN "Correct format is x.x.x.x"
  exit 1
fi

# Get IP address and mask of the connector
connector_ip_and_mask=$(get_connector_ip_and_mask)
if [ $? -ne 0 ]; then
  LOG_FATAL "Failed to get the connector IP address and mask"
  exit 1
fi

# Check if the IP address is in the same subnet as the connector
if ! is_ip_in_same_subnet "$IP" "$connector_ip_and_mask"; then
  LOG_WARN "IP address \"$IP\" is not in the same subnet as the connector"
  exit 1
fi

# Check if the IP address is already in the database
if sqlite3 "$DB_FILE" "SELECT ipv4 FROM devices WHERE ipv4 = ?;" "$IP" | grep -q .; then
  LOG_ERROR "Device with IP address \"$IP\" is already in the database"
  LOG_WARN "Choose another IP address"
  exit 1
fi

# Check if the device is available
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://"$IP") 
if (( STATUS_CODE!=200 )); then
  LOG_FATAL "IP address of smartplug is unavailable"
  LOG_WARN "Check if IP address \"$IP\" is correct"
  exit 1
fi

# Check if the device is running Tasmota firmware
if ! check_tasmota_firmware "$IP"; then
  LOG_FATAL "Device is not running Tasmota firmware"
  exit 1
fi

# Check MAC address of the device
ping -c 1 -W 1 "$IP" &> /dev/null # Send a single ping request with a 1 second timeout
MAC_ADDRESS=$(ip neigh show "$IP" | awk '{print $5}')
if [ -z "$MAC_ADDRESS" ]; then
  LOG_FATAL "Failed to retrieve MAC address for IP $IP"
  exit 1
fi

# Check the state of the smartplug
STATE=$(check_state "$IP")
if [ "$STATE" != "ON" ] && [ "$STATE" != "OFF" ]; then
  LOG_FATAL "Connector is unable to get state of the device"
  exit 1
fi

echo "Smartplug with IP address \"$IP\" is available"

# Add device to the database or change its name and IP address
if (check_MAC_in_db "$MAC_ADDRESS"); then
    LOG_INFO "Device with MAC address $MAC_ADDRESS is already in the database"
    LOG_INFO "Changing name and IP address of the device..."
    sqlite3 "$DB_FILE" "UPDATE devices SET ipv4 = ?, name = ? WHERE mac = ?;" "$IP" "$NAME" "$MAC_ADDRESS"
    if [ $? -ne 0 ]; then
        LOG_FATAL "Failed to update the device in the database."
        exit 1
    fi
    LOG_INFO "Device updated successfully."
else
    LOG_INFO "Adding device to the database..."
    sqlite3 "$DB_FILE" "INSERT INTO devices (name, ipv4, mac) VALUES (?, ?, ?);" "$NAME" "$IP" "$MAC_ADDRESS"
    if [ $? -ne 0 ]; then
        LOG_FATAL "Failed to add the device to the database."
        exit 1
    fi
    LOG_INFO "Device added successfully."
fi

exit 0