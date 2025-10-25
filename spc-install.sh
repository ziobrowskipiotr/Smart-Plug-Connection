#!/usr/bin/env bash
# Lightweight self-contained installer for Smart-Plug-Connection
# This script is safe to run via: curl -sSfL <url> | bash

set -euo pipefail

REPO_URL="https://github.com/ziobrowskipiotr/Smart-Plug-Connection.git"
DEST_DIR="$HOME/Smart-Plug-Connection"
SPC_DIR="$DEST_DIR/spc"

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

# Make sure spc directory exists
if [ ! -d "$SPC_DIR" ]; then
    err "Expected directory $SPC_DIR not found in repository"
    exit 1
fi

# Make scripts in spc/ readable and executable for the user
info "Adjusting permissions for scripts in $SPC_DIR"
chmod -R u+rwX "$SPC_DIR" || true

# Create user-local bin and symlink dispatcher
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
ln -sf "$SPC_DIR/spc.sh" "$LOCAL_BIN/spc"
chmod u+x "$SPC_DIR/spc.sh" || true

info "Installed 'spc' -> $LOCAL_BIN/spc"
info "Make sure $LOCAL_BIN is in your PATH, e.g. add to ~/.profile:"
echo "  export PATH=\"$LOCAL_BIN:\$PATH\""

# Optionally run setup script if present
SETUP_SCRIPT="$DEST_DIR/spc/spc-setup.sh"
if [ -f "$SETUP_SCRIPT" ]; then
    info "Found setup script: $SETUP_SCRIPT"
    info "Running setup script (no sudo)"
    bash "$SETUP_SCRIPT" || err "Setup script exited with non-zero status"
else
    info "No setup script found at $SETUP_SCRIPT — skipping"
fi

info "Installation complete"