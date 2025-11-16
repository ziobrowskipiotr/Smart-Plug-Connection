#!/bin/bash
# Script with helping functions and variables

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source logging functions
source "$SCRIPT_DIR/spc-logging.sh"

# Variables for database file
DB_FILE="$HOME/Smart-Plug-Connection/spc.db"
SCHEMA_FILE="$HOME/Smart-Plug-Connection/schema.sql"

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

# Function for checking if directory exists
directory_exists() {
  local dir="$1"
  if [ -d "$dir" ]; then
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

  if [[ "$count" == 0 ]]; then
    LOG_FATAL "Could not find an active local IPv4 address."
  fi

  if [[ "$count" == 1 ]]; then
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
      LOG_WARN "Invalid selection. Please try again."
    fi
  done
}

# Function to calculate the network address from IP and prefix
function calculate_network_address() {
  # Check if argument is provided
  if [[ -z "$1" || ! "$1" == */* ]]; then
    LOG_FATAL "Invalid format. Expected IP/PREFIX format, e.g. 192.168.1.1/24"
  fi

  local ip
  local prefix
  local net_addr_arr=()
  local i

  IFS='/' read -ra parts <<< "$1"
  ip="${parts[0]}"
  prefix="${parts[1]}"
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

  echo "${net_addr_arr[0]}.${net_addr_arr[1]}.${net_addr_arr[2]}.${net_addr_arr[3]}/$prefix"
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

  net_addr1=$(calculate_network_address "$connector_ip/$prefix") 
  net_addr2=$(calculate_network_address "$smartplug_ip/$prefix")

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
    LOG_FATAL "ERROR: Device name cannot be empty."
  fi

  # Check if the name contain only allowed characters (and no spaces)?
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    LOG_ERROR "Name contains invalid characters or spaces."
    LOG_FATAL "Only letters, numbers, hyphens (-), and underscores (_) are allowed."
  fi

  # Check if the name is of an appropriate length (e.g., 3 to 30 characters)?
  if (( ${#name} < 3 || ${#name} > 30 )); then
    LOG_FATAL "Name must be between 3 and 30 characters long."
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
    LOG_ERROR "No IP address provided to check_tasmota_firmware function."
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

  if echo "$response" | grep -q '"Topic"'; then
    # Success, found Tasmota signature
    return 0 
  else
    # The device responded, but it doesn't look like Tasmota
    return 1 
  fi
}

# Function for processing arguments
function process_arguments() {
  local NAME=""
  local IP=""

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
        fi
        ;;
      --ip)
        # Check if a value was provided for the flag
        if [ -n "$2" ]; then
          IP="$2"
          shift 2 # Move past --ip and its value
        else
          LOG_ERROR "Missing argument for --ip option."
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
        elif [ -z "$IP" ]; then
          IP="$1"
        else
          LOG_ERROR "Too many positional arguments provided."
          show_usage
          exit 1
        fi
        shift # Move to the next argument
        ;;
    esac
  done

  # Return the parsed values (NAME and IP) via global variables or other means as needed.
  PARSED_NAME="$NAME"
  PARSED_IP="$IP"
  return 0
}

function find_and_update_ip_by_mac() {
  local device_name="$1"
  local mac_address
  local scan_result
  local found_ip

  # Get the MAC address from the database for the given name
  mac_address=$(sqlite3 "$DB_FILE" "SELECT mac FROM devices WHERE name = '$device_name';")

  if [[ -z "$mac_address" ]]; then
    LOG_ERROR "Could not find MAC address for device \"$device_name\" in the database."
    echo "" # Return empty string on failure
    return 1
  fi

  LOG_INFO "Scanning the network for MAC address: $mac_address..."

  # Scan the network with arp-scan and filter for the MAC address
  # arp-scan requires root privileges.
  scan_result=$(sudo arp-scan -l | grep -i "$mac_address")

  if [[ -z "$scan_result" ]]; then
    LOG_WARN "Device with MAC $mac_address not found on the local network. It may be offline."
    echo "" # Return empty string on failure
    return 1
  fi

  # Extract the IP address from the scan result (it's the first column)
  found_ip=$(echo "$scan_result" | head -n 1 | awk '{print $1}')
  
  # Read old IP from database
  local old_ip
  old_ip=$(sqlite3 "$DB_FILE" "SELECT ipv4 FROM devices WHERE name = '$device_name';")

  if [[ "$old_ip" != "$found_ip" ]]; then
    LOG_INFO "Device found at new IP: $found_ip. Updating database..."
    sqlite3 "$DB_FILE" "UPDATE devices SET ipv4 = '$found_ip' WHERE name = '$device_name';"
    
    if [[ $? -ne 0 ]]; then
      LOG_ERROR "Failed to update IP address in the database for device \"$device_name\"."
      echo ""
      return 1
    fi
  fi

  # Return founded IP
  echo "$found_ip"
  return 0
}

function resolve_device_ip() {
  local device_name="$1"
  local device_ip="$2"
  local db_ip
  local new_ip

  # Validation
  if [[ -z "$device_name" && -z "$device_ip" ]]; then
    LOG_ERROR "You must provide a device name (--name) or an IP address (--ip)."
    show_usage
    exit 1
  fi

  # Case: Both name and IP are provided (highest priority for validation)
  if [[ -n "$device_name" && -n "$device_ip" ]]; then
    db_ip=$(sqlite3 "$DB_FILE" "SELECT ipv4 FROM devices WHERE name = '$device_name';")
    
    if [[ -z "$db_ip" ]]; then
      LOG_FATAL "Device with name \"$device_name\" not found in the database."
    fi
    
    # If the IPs match, we are good to go.
    if [[ "$db_ip" == "$device_ip" ]]; then
      echo "$device_ip"
      return 0
    else
      # Search the network for the correct IP using MAC address
      LOG_WARN "Provided IP ($device_ip) does not match the one in the database ($db_ip)."
      LOG_INFO "Attempting to find the correct IP on the network via MAC scan..."
      
      new_ip=$(find_and_update_ip_by_mac "$device_name")
      
      if [[ -n "$new_ip" ]]; then
        LOG_INFO "Successfully found and updated IP to $new_ip. Proceeding with command."
        echo "$new_ip"
        return 0
      else
        LOG_FATAL "Could not find the device on the network. Please check if it's powered on."
      fi
    fi
  fi

  # Case: Only name is provided
  if [[ -n "$device_name" ]]; then
    db_ip=$(sqlite3 "$DB_FILE" "SELECT ipv4 FROM devices WHERE name = '$device_name';")
    
    if [[ -z "$db_ip" ]]; then
      LOG_FATAL "No device with name \"$device_name\" found in the database."
    fi
    echo "$db_ip"
    return 0
  fi

  # Case: Only IP is provided
  if [[ -n "$device_ip" ]]; then
    echo "$device_ip"
    return 0
  fi
}

function get_active_power() {
  local ip_address="$1"
  local response
  
  # Command 'Status 8' returns sensor data, including power consumption
  response=$(curl -s --connect-timeout 3 "http://$ip_address/cm?cmnd=Status%208")
  
  # Use jq to parse the JSON and extract the 'Power' value.
  # The '-r' flag gives the raw value without quotes.
  echo "$response" | jq -r '.StatusSNS.ENERGY.Power'
}

function get_voltage() {
  local ip_address="$1"
  local response
  
  response=$(curl -s --connect-timeout 3 "http://$ip_address/cm?cmnd=Status%208")
  
  echo "$response" | jq -r '.StatusSNS.ENERGY.Voltage'
}

function get_current() {
  local ip_address="$1"
  local response
  
  response=$(curl -s --connect-timeout 3 "http://$ip_address/cm?cmnd=Status%208")
  
  echo "$response" | jq -r '.StatusSNS.ENERGY.Current'
}

function get_energy_today() {
  local ip_address="$1"
  local response
  
  response=$(curl -s --connect-timeout 3 "http://$ip_address/cm?cmnd=Status%208")
  
  echo "$response" | jq -r '.StatusSNS.ENERGY.Today'
}

function get_energy_yesterday() {
  local ip_address="$1"
  local response
  
  response=$(curl -s --connect-timeout 3 "http://$ip_address/cm?cmnd=Status%208")
  
  echo "$response" | jq -r '.StatusSNS.ENERGY.Yesterday'
}
