#!/bin/bash

# Script for setting up the Smart-Plug-Connection environment
# Smart behavior: don't require running the whole script as root.
# Only privileged commands will use sudo. Files that belong to the user
# will be created in the user's home (even if installer is run via sudo).

# Get the directory of the current script and project root
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# Source helpers if available (they define LOG_* and utility functions)
if [ -f "$SCRIPT_DIR/spc-helpers.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/spc-helpers.sh"
else
    # minimal fallbacks
    LOG_FATAL() { echo "FATAL: $*" >&2; exit 1; }
    LOG_ERROR() { echo "ERROR: $*" >&2; }
    LOG_WARN() { echo "WARN: $*" >&2; }
    LOG_INFO() { echo "INFO: $*"; }
    LOG_DEBUG() { echo "DEBUG: $*"; }
    file_exists() { [ -f "$1" ]; }
    directory_exists() { [ -d "$1" ]; }
fi

# If the script is executed with sudo, remember the original user and home
ORIG_USER=${SUDO_USER:-$USER}
ORIG_HOME=$(eval echo ~${SUDO_USER:-$USER})

# Sudo command for privileged operations (empty when running as target user)
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD="sudo"
else
    SUDO_CMD="sudo"
fi

# Helper to run a command as the original user (useful for creating files in user's home)
run_as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$ORIG_USER" != "root" ]; then
        sudo -u "$ORIG_USER" -- bash -c "$*"
    else
        bash -c "$*"
    fi
}

# Optional behavior flags (can be set as environment variables):
# INTERACTIVE=1  -> force interactive prompts (read from /dev/tty)
# RESET_TAILSCALE=1 -> remove local tailscale state and logout before 'tailscale up'
INTERACTIVE=${INTERACTIVE:-0}
RESET_TAILSCALE=${RESET_TAILSCALE:-0}

# Update and install dependencies (requires privileges)
$SUDO_CMD apt update
$SUDO_CMD apt upgrade -y
$SUDO_CMD apt install -y git curl sqlite3 jq arp-scan
# Install Tailscale (their installer needs privilege)
curl -fsSL https://tailscale.com/install.sh | $SUDO_CMD sh

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

LOG_DEBUG "To complete Tailscale setup:"
LOG_DEBUG "  1. You need to visit https://login.tailscale.com/admin/acls/visual/tags:"
LOG_DEBUG "    - click 'Create tag' button"
LOG_DEBUG "    - enter 'SPC' as 'Tag name'"
LOG_DEBUG "    - enter 'autogroup:admin' as 'Tag owner'"
LOG_DEBUG "    - Add the note below to 'Tag notes' if you want:"
LOG_DEBUG "      * Tag for unattended servers, disables key expiration or for devices that need to be constantly online."
LOG_DEBUG "    - click 'Save tag' button"
LOG_DEBUG "  2. You need to generate an auth key from https://login.tailscale.com/admin/settings/authkeys"
LOG_DEBUG "    - click 'Generate auth key' button"
LOG_DEBUG "    - check 'Reusable' and enter (e.g.) 90 at 'Expires' options"
LOG_DEBUG "    - set Ephemeral unchecked"
LOG_DEBUG "    - Check 'Tags' and add your created tag 'SPC' to 'Tags' by choosing from the dropdown menu 'Add tag'"
LOG_DEBUG "    - click 'Generate auth key' button"
LOG_DEBUG "    - You will see this key only once... make sure you copy it now!"
LOG_DEBUG "    - if you lose it, you will need to generate a new one and revoke the old one"
LOG_DEBUG "    - copy the generated key (starts with 'tskey-...')"
LOG_DEBUG "  3. Paste the key into the .env file in the ~/Smart-Plug-Connection directory"
# Wait for user confirmation (only if running interactively or INTERACTIVE=1)
if [ "$INTERACTIVE" -eq 1 ] || ( [ -t 0 ] && [ -t 1 ] ); then
    # choose input source: if /dev/tty is readable use it (works when stdin is a pipe)
    INPUT=/dev/tty
    if [ ! -r "$INPUT" ]; then
        INPUT=/dev/stdin
    fi

    while true; do
        # read from chosen input so piping can still work with INTERACTIVE=1
        read -r -p "Have you completed the steps above? (y/n): " answer <"$INPUT"
        case "$answer" in
            [Yy]* ) break;;
            [Nn]* ) LOG_INFO "Please complete the steps above and then run this script again."; exit 0;;
            * ) LOG_INFO "Please answer yes or no.";;
        esac
    done
else
    # Non-interactive shell (e.g. curl | bash) - do not loop endlessly
    LOG_INFO "Non-interactive shell detected - skipping interactive confirmation."
    LOG_INFO "When ready, run this script interactively to continue Tailscale setup:"
    echo "  sudo bash '$SCRIPT_DIR/spc-setup.sh'"
    exit 0
fi


# Optionally reset local Tailscale state before logging in
if [ "$RESET_TAILSCALE" -eq 1 ]; then
    LOG_INFO "Resetting local Tailscale state (logout + remove state files)"
    $SUDO_CMD tailscale logout || true
    $SUDO_CMD systemctl stop tailscaled || true
    $SUDO_CMD rm -rf /var/lib/tailscale/* || true
    $SUDO_CMD systemctl start tailscaled || true
fi

# Start Tailscale with the provided auth key and advertise the SPC tag
connector_ip_and_mask=$(get_connector_ip_and_mask)
if [[ $? -ne 0 || -z "$connector_ip_and_mask" ]]; then
    LOG_FATAL "Failed to get connector IP and mask."
fi
network_address=$(calculate_network_address "$connector_ip_and_mask")
if [[ $? -ne 0 || -z "$network_address" ]]; then
    LOG_FATAL "Failed to calculate network address."
fi

# If an auth key exists in .env, use it; otherwise run interactive tailscale up
AUTHKEY=$(grep -E '^KEY=' .env 2>/dev/null | cut -d '=' -f2- || true)
if [ -n "$AUTHKEY" ]; then
    LOG_INFO "Using auth key from .env to connect Tailscale"
    $SUDO_CMD tailscale up --authkey="$AUTHKEY" --accept-routes --advertise-tags=tag:SPC --advertise-routes="$network_address"
else
    LOG_INFO "No auth key found — running interactive 'tailscale up'"
    # run interactive tailscale up; ensure tty input if INTERACTIVE forced
    if [ "$INTERACTIVE" -eq 1 ] && [ -r /dev/tty ]; then
        $SUDO_CMD tailscale up --accept-routes --advertise-tags=tag:SPC --advertise-routes="$network_address" < /dev/tty
    else
        $SUDO_CMD tailscale up --accept-routes --advertise-tags=tag:SPC --advertise-routes="$network_address"
    fi
fi

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
LOG_DEBUG "Database '$DB_FILE' initialized successfully."

# Create a directory for private scripts and programs if it doesn't exist
if [ ! -d ~/bin ]; then
    sudo mkdir ~/bin
fi
# Check if the directory was created successfully
if ! directory_exists ~/bin; then
    LOG_FATAL "Failed to create directory ~/bin"
fi

# Create symbolic link to the scripts in ~/bin
ln -s ~/Smart-Plug-Connection/spc.sh ~/bin/spc

LOG_DEBUG "Installation complete."
exit 0
