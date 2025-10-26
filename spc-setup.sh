#!/bin/bash

# Script for setting up the Smart-Plug-Connection environment
# Smart behavior: don't require running the whole script as root.
# Only privileged commands will use sudo. Files that belong to the user
# will be created in the user's home (even if installer is run via sudo).

# Get the directory of the current script and project root
# (realpath to follow symlinks reliably)
SCRIPT_DIR="$( cd -- "$( dirname -- "$( realpath "${BASH_SOURCE[0]}" )" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Ensure we run relative ops from project root (so .env/DB/schema are consistent)
cd "$PROJECT_ROOT" || exit 1

# Source helpers if available (they define LOG_* and utility functions)
if [ -f "$SCRIPT_DIR/spc-helpers.sh" ]; then
    source "$SCRIPT_DIR/spc-helpers.sh"
else
    LOG_FATAL "Helpers script '$SCRIPT_DIR/spc-helpers.sh' not found!"
fi

# If the script is executed with sudo, remember the original user and home
ORIG_USER=${SUDO_USER:-$USER}
ORIG_HOME=$(eval echo ~"${SUDO_USER:-$USER}")

# Sudo command for privileged operations (empty when running as root)
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
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

# RESET_TAILSCALE=1 -> remove local tailscale state and logout before 'tailscale up'
RESET_TAILSCALE=${RESET_TAILSCALE:-0}

# Update and install dependencies (requires privileges)
$SUDO_CMD apt update
$SUDO_CMD apt upgrade -y
$SUDO_CMD apt install -y git curl sqlite3 jq arp-scan

# Logout first to clear local state
$SUDO_CMD tailscale logout

# Install Tailscale (their installer needs privilege)
curl -fsSL https://tailscale.com/install.sh | $SUDO_CMD sh

# Check if the installation was successful
if [[ $? -ne 0 ]]; then
    LOG_FATAL "Failed to install dependencies."
fi

# First, run interactive login to connect the device to an account
LOG_DEBUG "Starting login to Tailscale..."
LOG_DEBUG "Copy the link that appears and open it in your browser to log in the device."
$SUDO_CMD tailscale up

# Check if login was successful
if [[ $? -ne 0 ]]; then
    LOG_FATAL "Login to Tailscale failed. Please try running the script again."
fi
LOG_DEBUG "Device was successfully logged into your Tailscale account."
LOG_DEBUG "Now, to complete the setup, you will need an authorization key (auth key)."

# Create .env file if it doesn't exist (store in PROJECT_ROOT)
ENV_FILE="$PROJECT_ROOT/.env"
if ! file_exists "$ENV_FILE"; then
    LOG_DEBUG "Creating .env file..."
    echo "KEY=EXAMPLE_KEY" > "$ENV_FILE"
fi

if ! file_exists "$ENV_FILE"; then
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

INPUT=/dev/tty
if [ ! -r "$INPUT" ]; then
    INPUT=/dev/stdin
fi

while true; do
    # read from chosen input
    read -r -p "Have you completed the steps above and pasted the key? (y/n): " answer <"$INPUT"
    case "$answer" in
        [Yy]* ) break;;
        [Nn]* ) LOG_DEBUG "Please complete the steps above and then run this script again."; exit 0;;
        * ) LOG_DEBUG "Please answer yes or no.";;
    esac
done

# Start tailscale on systemctl to make sure it runs on boot
$SUDO_CMD systemctl start tailscaled

# Start Tailscale with the provided auth key and advertise the SPC tag
connector_ip_and_mask=$(get_connector_ip_and_mask)
if [[ $? -ne 0 || -z "$connector_ip_and_mask" ]]; then
    LOG_DEBUG "Failed to get connector IP and mask."
    LOG_FATAL "Failed to get connector IP and mask."
fi
network_address=$(calculate_network_address "$connector_ip_and_mask")
if [[ $? -ne 0 || -z "$network_address" ]]; then
    LOG_DEBUG "Failed to calculate network address from $connector_ip_and_mask."
    LOG_FATAL "Failed to calculate network address."
fi

# If an auth key exists in .env, use it
AUTHKEY=$(grep -E '^KEY=' "$ENV_FILE" 2>/dev/null | cut -d '=' -f2- || true)
if [ -n "$AUTHKEY" ]; then
    LOG_INFO "Using auth key from .env to re-authenticate and apply tags/routes..."
    $SUDO_CMD tailscale up --authkey="$AUTHKEY" --accept-routes --advertise-tags=tag:SPC --advertise-routes="$network_address"
else
    LOG_DEBUG "No auth key found in .env file."
    LOG_FATAL "No auth key found in .env file. Please generate one and add it."
fi

# Verify Tailscale status
$SUDO_CMD tailscale status
if [[ $? -ne 0 ]]; then
    LOG_DEBUG "Tailscale is not running correctly."
    LOG_FATAL "Tailscale is not running correctly. Please check your Tailscale setup."
fi

# Define schema/database paths
SCHEMA_FILE="$HOME/Smart-Plug-Connection/schema.sql"
DB_FILE="$HOME/Smart-Plug-Connection/spc.db"

# Check if the database schema file exists
if (! file_exists "$SCHEMA_FILE"); then
    LOG_DEBUG "Schema file '$SCHEMA_FILE' not found!"
    LOG_FATAL "Schema file '$SCHEMA_FILE' not found!"
fi

# Initialize the database
sqlite3 "$DB_FILE" < "$SCHEMA_FILE"
if [ $? -ne 0 ]; then
    LOG_DEBUG "Failed to initialize the database."
    LOG_FATAL "Failed to initialize the database."
fi
LOG_DEBUG "Database '$DB_FILE' initialized successfully."

# Define the target directory in the original user's home
USER_BIN_DIR="$ORIG_HOME/bin"

LOG_DEBUG "Ensuring '$USER_BIN_DIR' exists for user '$ORIG_USER'..."
# Use run_as_user to create the directory if it doesn't exist
run_as_user "mkdir -p '$USER_BIN_DIR'"

# Check if the directory was created successfully (also run as user)
if ! run_as_user "test -d '$USER_BIN_DIR'"; then
    LOG_DEBUG "Failed to create directory $USER_BIN_DIR for user $ORIG_USER"
    LOG_FATAL "Failed to create directory $USER_BIN_DIR for user $ORIG_USER"
fi

# Create or update symbolic link in the user's bin directory
# Use -sf to force overwrite if it exists, preventing errors on re-runs
LOG_DEBUG "Creating symbolic link from '$SCRIPT_DIR/spc.sh' to '$USER_BIN_DIR/spc'"
run_as_user "ln -sf '$SCRIPT_DIR/spc.sh' '$USER_BIN_DIR/spc'"

# --- Added: also install into ~/.local/bin and ensure PATH (bez kasowania Twojej logiki powyżej)
USER_LOCAL_BIN="$ORIG_HOME/.local/bin"
LOG_DEBUG "Ensuring '$USER_LOCAL_BIN' exists for user '$ORIG_USER'..."
run_as_user "mkdir -p '$USER_LOCAL_BIN'"
LOG_DEBUG "Creating symbolic link from '$SCRIPT_DIR/spc.sh' to '$USER_LOCAL_BIN/spc'"
run_as_user "ln -sf '$SCRIPT_DIR/spc.sh' '$USER_LOCAL_BIN/spc'"

# Ensure PATH contains ~/.local/bin for the user
if ! run_as_user "grep -q \"$USER_LOCAL_BIN\" \"$ORIG_HOME/.bashrc\" 2>/dev/null"; then
    LOG_DEBUG "Adding '$USER_LOCAL_BIN' to PATH in $ORIG_HOME/.bashrc"
    run_as_user "echo 'export PATH=\"$USER_LOCAL_BIN:\$PATH\"' >> \"$ORIG_HOME/.bashrc\""
fi

# Reset Bash's command hash cache to pick up new symlinks right away
LOG_DEBUG "Resetting Bash command cache (hash -r)"
run_as_user "hash -r || true"

# Install collector systemd unit
LOG_DEBUG "$SUDO_CMD cp $SCRIPT_DIR/spc-collect.service /etc/systemd/system/"
$SUDO_CMD cp "$SCRIPT_DIR/spc-collect.service" /etc/systemd/system/
LOG_DEBUG "$SUDO_CMD cp $SCRIPT_DIR/spc-collect.timer /etc/systemd/system/"
$SUDO_CMD cp "$SCRIPT_DIR/spc-collect.timer" /etc/systemd/system/

$SUDO_CMD systemctl daemon-reload
$SUDO_CMD systemctl enable --now spc-collect.timer

LOG_INFO "Measurement collector enabled (every 5 minutes)."

LOG_DEBUG "Installation complete."
exit 0
