#!/bin/bash
# Script for setting up the Smart-Plug-Connection environment
if [ "$EUID" -ne 0 ]; then
  echo "This command must be running with root privileges"
  exit 1
fi

# Update and install dependencies
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl sqlite3

DB_FILE="spc.db"
SCHEMA_FILE="schema.sql"

# Check if the database file already exists
if [ ! -f "$SCHEMA_FILE" ]; then
    echo "Error: Schema file '$SCHEMA_FILE' not found!"
    exit 1
fi

# Initialize the database
sqlite3 "$DB_FILE" < "$SCHEMA_FILE"
if [ $? -ne 0 ]; then
    echo "Error: Failed to initialize the database."
    exit 1
fi
echo "Database '$DB_FILE' initialized successfully."

# Get the absolute path to the database file
FULL_DB_PATH="$(pwd)/$DB_FILE"
# Set environment variable for SPC_DB_PATH in .bashrc
if grep -q "export SPC_DB_PATH=" ~/.bashrc; then
    echo "Updating existing SPC_DB_PATH environment variable..."
    sed -i '/Smart-Plug-Connection/d' "~/.bashrc"
    sed -i '/SPC_DB_PATH/d' "~/.bashrc"

    echo "Old variable removed. Adding the new one..."
else
    echo "Adding SPC_DB_PATH to environment variables..."
fi
    echo '' >> ~/.bashrc
    echo '# Path to the Smart-Plug-Connection database file' >> ~/.bashrc
    echo "export SPC_DB_PATH=\"$FULL_DB_PATH\"" >> ~/.bashrc
    
    echo "Variable SPC_DB_PATH set to: $FULL_DB_PATH"

echo "Installation complete."