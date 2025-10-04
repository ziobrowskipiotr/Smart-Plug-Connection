#!/bin/bash
# Script with helping functions and variables

# Source logging functions
source ./spc-logging.sh

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

# Function for validating IPv4 notation
function validate_ipv4() {
  local ip=$1
  local stat=1

  # Regex for checking format x.x.x.x
  if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
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
  
  return $stat
}

# Function to get the local connector IP address
function get_connector_ip_and_mask() {
  local ip_list
  # Exclude 100.x.x.x addresses (commonly used for Docker or Tailscale etc.)
  mapfile -t ip_list < <(ip -4 -o addr show scope global | grep -v '100\.' | awk '{print $4}')

  local count=${#ip_list[@]}

  if [ "$count" -eq 0 ]; then
    echo "ERROR: Could not find an active local IPv4 address." >&2
    return 1
  fi

  if [ "$count" -eq 1 ]; then
    echo "${ip_list[0]}"
    return 0
  fi

  echo "Found multiple active IP addresses. Please select one to use:"
  local i
  for i in "${!ip_list[@]}"; do
    echo "  $((i + 1))) ${ip_list[i]}"
  done

  local choice
  while true; do
    read -p "Select a number (1-$count): " choice
    if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
      echo "${ip_list[$((choice - 1))]}"
      return 0
    else
      echo "Invalid selection. Please try again." >&2
    fi
  done
}

# Function to calculate the network address from IP and prefix
function calculate_network_address() {
  local ip=$1
  local prefix=$2
  local net_addr_arr=()
  local i

  IFS='.' read -ra ip_octets <<< "$ip"
  
  local mask_bits=""
  for ((i=0; i<32; i++)); do
    if [ $i -lt $prefix ]; then
      mask_bits+="1"
    else
      mask_bits+="0"
    fi
  done

  for i in {0..3}; do
    local mask_octet_bin=${mask_bits:i*8:8}
    local mask_octet=$((2#$mask_octet_bin))
    local ip_octet=${ip_octets[i]}
    
    net_addr_arr+=($((ip_octet & mask_octet)))
  done

  echo "${net_addr_arr[0]}.${net_addr_arr[1]}.${net_addr_arr[2]}.${net_addr_arr[3]}"
}

function is_ip_in_same_subnet() {
  local smartplug_ip=$1             #(smartplug_IP)
  local connector_ip_and_mask=$2    #(connector_IP/mask)

  # Extract IP and prefix from CIDR notation
  local connector_ip
  local prefix
  IFS='/' read -ra parts <<< "$connector_ip_and_mask"
  connector_ip="${parts[0]}"
  prefix="${parts[1]}"

  # Calculate network addresss for connector
  net_addr1=$(calculate_network_address "$connector_ip" "$prefix") 

  # Calculate network addresss for smartplug
  net_addr2=$(calculate_network_address "$smartplug_ip" "$prefix") 

  # Compare results
  if [[ "$net_addr1" == "$net_addr2" ]]; then
    return 0 # They are the same -> success!
  else
    return 1 # They are different -> failure!
  fi
}

function validate_device_name() {
  local name="$1"

  # Check if the name empty?
  if [[ -z "$name" ]]; then
    echo "ERROR: Device name cannot be empty." >&2
    return 1
  fi

  # Check if the name contain only allowed characters (and no spaces)?
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: Name contains invalid characters or spaces." >&2
    echo "       Only letters, numbers, hyphens (-), and underscores (_) are allowed." >&2
    return 1
  fi

  # Check if the name is of an appropriate length (e.g., 3 to 30 characters)?
  if (( ${#name} < 3 || ${#name} > 30 )); then
    echo "ERROR: Name must be between 3 and 30 characters long." >&2
    return 1
  fi

  # If all checks passed
  return 0
}

# Function to check if the device at given IP is running Tasmota firmware
function check_tasmota_firmware() {
  local ip=$1
  # Set timeout for curl requests (in seconds)
  local timeout=3 

  # Check if the argument is provided
  if [[ -z "$ip" ]]; then
    echo "ERROR: No IP address provided to check_tasmota_firmware function." >&2
    return 1
  fi

  # Send HTTP request to the device's status endpoint
  local response
  response=$(curl -s -f --connect-timeout $timeout --max-time $timeout "http://$ip/cm?cmnd=Status")

  # Check the exit code of the curl command.
  if [ $? -ne 0 ]; then
    # The device did not respond correctly to the HTTP request
    return 1 
  fi

  # If curl succeeded, check if the response contains the Tasmota-specific key.
  # "StatusFWR" is very specific to the Tasmota status JSON structure.
  if echo "$response" | grep -q '"StatusFWR"'; then
    # Success, found Tasmota signature
    return 0 
  else
    # The device responded, but it doesn't look like Tasmota
    return 1 
  fi
}