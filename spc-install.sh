#!/bin/bash
# Lightweight self-contained installer for Smart-Plug-Connection
# This script is safe to run via: curl -sSfL <url> | bash

set -euo pipefail

REPO_URL="https://github.com/ziobrowskipiotr/Smart-Plug-Connection.git"
DEST_DIR="$HOME/Smart-Plug-Connection"
SPC_DIR=""

err() { echo "ERROR: $*" >&2; }
info() { echo "INFO: $*"; }

info "Installing Smart-Plug-Connection into $DEST_DIR"

cd "$HOME"

if [ -d "$DEST_DIR/.git" ]; then
    info "Repository already exists at $DEST_DIR — pulling latest changes"
    if git -C "$DEST_DIR" pull --rebase --quiet; then
        info "Updated existing repository"
    else
        err "Git pull failed; keeping existing files"
    fi
else
    info "Cloning repository from $REPO_URL"
    if git clone --quiet "$REPO_URL" "$DEST_DIR"; then
        info "Cloned into $DEST_DIR"
    else
        err "Failed to clone repository"
        exit 1
    fi
fi

# Locate dispatcher script (spc.sh) — repo may place it at root or inside 'spc/'
if [ -f "$DEST_DIR/spc.sh" ]; then
    SCRIPT_PATH="$DEST_DIR/spc.sh"
    SPC_DIR="$DEST_DIR"
elif [ -f "$DEST_DIR/spc/spc.sh" ]; then
    SCRIPT_PATH="$DEST_DIR/spc/spc.sh"
    SPC_DIR="$DEST_DIR/spc"
else
    # Try to find spc.sh anywhere one level deep
    SCRIPT_PATH=$(find "$DEST_DIR" -maxdepth 2 -type f -name spc.sh | head -n 1 || true)
    if [ -n "$SCRIPT_PATH" ]; then
        SPC_DIR=$(dirname "$SCRIPT_PATH")
    else
        err "Could not find 'spc.sh' in the cloned repository (tried root and 'spc/' subdir)."
        err "Repository layout may have changed. Please inspect $DEST_DIR manually."
        exit 1
    fi
fi

# Make scripts readable and executable for the user
info "Adjusting permissions for scripts in $SPC_DIR"
chmod -R u+rwX "$SPC_DIR" || true

# Create user-local bin
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
chmod u+x "$SCRIPT_PATH" || true

info "Installed 'spc' -> $LOCAL_BIN/spc"
info "Make sure $LOCAL_BIN is in your PATH, e.g. add to ~/.profile:"
echo "  export PATH=\"$LOCAL_BIN:\$PATH\""

# Optionally run setup script if present (can be at root or in spc/)
SETUP_SCRIPT=""
if [ -f "$DEST_DIR/spc-setup.sh" ]; then
    SETUP_SCRIPT="$DEST_DIR/spc-setup.sh"
elif [ -f "$DEST_DIR/spc/spc-setup.sh" ]; then
    SETUP_SCRIPT="$DEST_DIR/spc/spc-setup.sh"
else
    # try to find it
    SETUP_SCRIPT=$(find "$DEST_DIR" -maxdepth 2 -type f -name spc-setup.sh | head -n 1 || true)
fi

if [ -n "$SETUP_SCRIPT" ] && [ -f "$SETUP_SCRIPT" ]; then
    info "Found setup script: $SETUP_SCRIPT"
    info "Running setup script (with sudo if necessary)"
    # If running as root already, don't use sudo
    if [ "$EUID" -eq 0 ]; then
        bash "$SETUP_SCRIPT" || err "Setup script exited with non-zero status"
    else
        if command -v sudo >/dev/null 2>&1; then
            sudo bash "$SETUP_SCRIPT" || err "Setup script exited with non-zero status"
        else
            err "sudo not found; cannot run setup script automatically. Run it manually: sudo bash $SETUP_SCRIPT"
        fi
    fi
else
    info "No setup script found — skipping"
fi

info "Installation complete"