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