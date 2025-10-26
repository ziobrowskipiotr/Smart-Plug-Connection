#!/bin/bash
# Script for listing all devices from the database in JSON format.

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the helpers script for DB_FILE and logging
source "$SCRIPT_DIR/spc-helpers.sh"

# Function to display usage information
show_usage() {
  cat <<EOF
Usage: $0 [-h|--help]
  Lists all registered devices in JSON format.

Options:
  -h, --help    Display this help message and exit.
EOF
}

# Handle --help argument
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_usage
  exit 0
fi

# --- Main Logic ---

# Execute sqlite3 with flags to output JSON directly.
# -json: specifies the output format.
# The SQL query selects all columns for all devices.
JSON_OUTPUT=$(sqlite3 -json "$DB_FILE" "SELECT id, name, ipv4, mac FROM devices;")

# Check if the command failed or returned nothing
if [[ $? -ne 0 || -z "$JSON_OUTPUT" ]]; then
    LOG_ERROR "Failed to retrieve devices from the database or database is empty."
    # Output an empty JSON array for scripting consistency
    echo "[]"
    exit 1
fi

# --- Output the result ---
# Simply print the JSON output to standard out.
# This makes the script easily usable with tools like jq.
echo "$JSON_OUTPUT"

exit 0