#!/bin/bash
# Script for setting up the Smart-Plug-Connection environment
if [ "$EUID" -ne 0 ]; then
  echo "This command must be running with root privileges"
  exit 1
fi

# Create a directory for private scripts and programs if it doesn't exist
if [ ! -d ~/bin ]; then
    sudo mkdir ~/bin
fi
cd ~/bin
sudo git clone https://github.com/ziobrowskipiotr/Smart-Plug-Connection.git
# Give execute permission to all scripts in the cloned repository
sudo chmod -R +x Smart-Plug-Connection
cd Smart-Plug-Connection
# Run the setup script
sudo ./setup.sh