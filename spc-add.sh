#!/bin/bash
# Script using for turning on smartplug with tasmota

# Source the helpers script
source ./spc-helpers.sh

if (!check_connection()); then
  echo "Check your internet connection"
  exit 1
fi

# TO DO - Check if the format of name and IP address is correct
read -p "Write name of the device: " name
if (sqlite3 "$DB_FILE" "SELECT name FROM devices WHERE name = '$name';" | grep -q .); then
  echo "Device with name \"$name\" is already in the database"
  echo "Choose another name"
  exit 1
fi
read -p "Write IP address of the device: " IP
if (sqlite3 "$DB_FILE" "SELECT ipv4 FROM devices WHERE ipv4 = '$IP';" | grep -q .); then
  echo "Device with IP address \"$IP\" is already in the database"
  echo "Choose another IP address"
  exit 1
fi

STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://"$IP") 
if (( STATUS_CODE!=200 )); then
  echo "IP address of smartplug is unavailable"
  echo "Check is IP address \"$IP\" is correct"
  exit 1
fi

# Check MAC address of the device
MAC_ADDRESS=$(ip neigh show "$IP" | awk '{print $5}')
if [ -z "$MAC_ADDRESS" ]; then
  echo "Failed to retrieve MAC address for IP $IP"
  exit 1
fi

# Check the state of the smartplug
STATE=$(check_state "$IP")
if [ "$STATE" != "ON" ] && [ "$STATE" != "OFF" ]; then
  echo "Connector is unable to get state of the device"
  exit 1
fi

echo "Smartplug with IP address \"$IP\" is available"

# Add device to the database or change its name and IP address
if (check_MAC_in_db "$MAC_ADDRESS"); then
    echo "Device with MAC address $MAC_ADDRESS is already in the database"
    echo "Changing name and IP address of the device..."
    sqlite3 "$DB_FILE" "UPDATE devices SET ip = '$IP', name = '$NAME' WHERE mac = '$MAC_ADDRESS';"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to update the device in the database."
        exit 1
    fi
    echo "Device updated successfully."
else
    echo "Adding device to the database..."
    sqlite3 "$DB_FILE" "INSERT INTO devices (name, ipv4, mac) VALUES ('$NAME', '$IP', '$MAC_ADDRESS');"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to add the device to the database."
        exit 1
    fi
    echo "Device added successfully."
fi