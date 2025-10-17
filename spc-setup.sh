#!/bin/bash

# Script for setting up the Smart-Plug-Connection environment
if [[ "$EUID" -ne 0 ]]; then
  LOG_FATAL "This command must be running with root privileges"
fi

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source the helpers script
source "$SCRIPT_DIR/spc-helpers.sh"

# Update and install dependencies
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl sqlite3 jq arp-scan
sudo curl -fsSL https://tailscale.com/install.sh | sh

# Check if the installation was successful
if [[ $? -ne 0 ]]; then
    LOG_FATAL "Failed to install dependencies."
fi

# Create .env file if it doesn't exist
if ! file_exists ".env"; then
    LOG_DEBUG "Creating .env file..."
    echo "KEY=EXAMPLE_KEY" > .env
fi

if ! file_exists ".env"; then
    LOG_FATAL "Failed to create .env file."
fi

LOG_INFO "To complete Tailscale setup:"
LOG_INFO "  1. You need to visit https://login.tailscale.com/admin/acls/visual/tags:"
LOG_INFO "    - click 'Create tag' button"
LOG_INFO "    - enter 'SPC' as 'Tag name'"
LOG_INFO "    - enter 'autogroup:admin' as 'Tag owner'"
LOG_INFO "    - Add the note below to 'Tag notes' if you want:"
LOG_INFO "      * Tag for unattended servers, disables key expiration or for devices that need to be constantly online."
LOG_INFO "    - click 'Save tag' button"
LOG_INFO "  2. You need to generate an auth key from https://login.tailscale.com/admin/settings/authkeys"
LOG_INFO "    - click 'Generate auth key' button"
LOG_INFO "    - check 'Reusable' and enter (e.g.) 90 at 'Expires' options"
LOG_INFO "    - set Ephemeral unchecked"
LOG_INFO "    - Check 'Tags' and add your created tag 'SPC' to 'Tags' by choosing from the dropdown menu 'Add tag'"
LOG_INFO "    - click 'Generate auth key' button"
LOG_INFO "    - You will see this key only once... make sure you copy it now!"
LOG_INFO "    - if you lose it, you will need to generate a new one and revoke the old one"
LOG_INFO "    - copy the generated key (starts with 'tskey-...')"
LOG_INFO "  3. Paste the key into the .env file in the ~/bin/Smart-Plug-Connection directory"
# Wait for user confirmation
while true; do
    read -p "Have you completed the steps above? (y/n): " answer
    case $answer in
        [Yy]* ) break;;
        [Nn]* ) LOG_INFO "Please complete the steps above and then run this script again."; exit 0;;
        * ) LOG_INFO "Please answer yes or no.";;
    esac
done

# Start Tailscale with the provided auth key and advertise the SPC tag
connector_ip_and_mask=$(get_connector_ip_and_mask)
if [[ $? -ne 0 || -z "$connector_ip_and_mask" ]]; then
    LOG_FATAL "Failed to get connector IP and mask."
fi
network_address=$(calculate_network_address "$connector_ip_and_mask")
if [[ $? -ne 0 || -z "$network_address" ]]; then
    LOG_FATAL "Failed to calculate network address."
fi
sudo tailscale up --authkey="$(grep 'KEY=' .env | cut -d '=' -f2)" --accept-routes --advertise-tags=tag:SPC --advertise-routes="$network_address"

# Verify Tailscale status
sudo tailscale status
if [[ $? -ne 0 ]]; then
    LOG_FATAL "Tailscale is not running correctly. Please check your Tailscale setup."
fi

# Check if the database file already exists
if (! file_exists "$SCHEMA_FILE"); then
    LOG_FATAL "Schema file '$SCHEMA_FILE' not found!"
fi

# Initialize the database
sqlite3 "$DB_FILE" < "$SCHEMA_FILE"
if [ $? -ne 0 ]; then
    LOG_FATAL "Failed to initialize the database."
fi
LOG_INFO "Database '$DB_FILE' initialized successfully."

# Create a directory for private scripts and programs if it doesn't exist
if [ ! -d ~/bin ]; then
    sudo mkdir ~/bin
fi
# Check if the directory was created successfully
if directory_exists ~/bin; then
    LOG_FATAL "Failed to create directory ~/bin"
fi

# Create symbolic link to the scripts in ~/bin
ln -s ~/Smart-Plug-Connection/spc.sh ~/bin/spc

LOG_INFO "Installation complete."
exit 0
