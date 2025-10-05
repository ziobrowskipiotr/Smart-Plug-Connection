#!/bin/bash
# Script for setting up the Smart-Plug-Connection environment
if [ "$EUID" -ne 0 ]; then
  LOG_FATAL "This command must be running with root privileges"
  exit 1
fi

# Update and install dependencies
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl sqlite3 jq

# Check if the installation was successful
if [ $? -ne 0 ]; then
    LOG_FATAL "Failed to install dependencies."
    exit 1
fi

# Source the helpers script
source ./spc-helpers.sh

# Check if the database file already exists
if (! file_exists "$SCHEMA_FILE"); then
    LOG_FATAL "Schema file '$SCHEMA_FILE' not found!"
    exit 1
fi

# Initialize the database
sqlite3 "$DB_FILE" < "$SCHEMA_FILE"
if [ $? -ne 0 ]; then
    LOG_FATAL "Failed to initialize the database."
    exit 1
fi
LOG_INFO "Database '$DB_FILE' initialized successfully."

LOG_INFO "Installation complete."
exit 0
