#!/bin/bash
# Script with helping functions and variables

# Variables for database file
DB_FILE="spc.db"
SCHEMA_FILE="schema.sql"

# Function for checking connectivity
check_connection() {
  ping -c 1 -q 8.8.8.8 &> /dev/null
}

# Function for checking if file exists
file_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    return 0
  else
    return 1
  fi
}

# Function for checking the state of the smartplug
check_state(){
  local state=$(curl -s "http://$1/cm?cmnd=Power" | jq -r '.POWER')
  echo "$state"
}

# Function for checking if MAC address is already in the database
check_MAC_in_db() {
  local mac_address="$1"
  local result=$(sqlite3 "$DB_FILE" "SELECT mac FROM devices WHERE mac = '$mac_address';")

  if [ -n "$result" ]; then
    return 0
  else
    return 1
  fi
}

# Function for validating IPv4 CIDR notation
function validate_ipv4_cidr() {
  local ip_cidr=$1
  local stat=1

  # Regex for checking format x.x.x.x/x
  if [[ $ip_cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]]; then
    # Zapisuje dopasowane grupy do tablicy
    read -ra parts <<< "${BASH_REMATCH[0]}"

    # Divide into IP and CIDR prefix
    IFS='/' read -ra addr_parts <<< "$parts"
    local ip=${addr_parts[0]}
    local cidr=${addr_parts[1]}

    # Check CIDR prefix (0-32)
    if (( cidr >= 0 && cidr <= 32 )); then
      # Divide IP address into octets
      IFS='.' read -ra octets <<< "$ip"

      # Check if each octet is in the range 0-255
      if [[ ${octets[0]} -le 255 && \
            ${octets[1]} -le 255 && \
            ${octets[2]} -le 255 && \
            ${octets[3]} -le 255 ]]; then
        # Address is valid
        stat=0
      fi
    fi
  fi
  
  return $stat
}