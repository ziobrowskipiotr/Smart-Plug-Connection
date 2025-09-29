#!/bin/bash
# Script using for turning on smartplug with tasmota
source "$PDE_HELPERS"

if [check_connection()]; then
  pass
else
  echo "Check your internet connection"
  exit 1
fi

# TO DO
read -p "Write name of the device: " user_name
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://"$IP") 

if [STATUS_CODE!=200]; then
  echo "IP address of smartplug is unavailable"
  echo "Check is IP address \"$IP\" is correct"
  echo "If not, use change-IP command"
fi
