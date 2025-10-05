#!/bin/bash
# Script for setting up the Smart-Plug-Connection environment
if [ "$EUID" -ne 0 ]; then
  LOG_FATAL "This command must be running with root privileges"
  exit 1
fi
# Go to home directory
cd ~
# Clone the repository
sudo git clone https://github.com/ziobrowskipiotr/Smart-Plug-Connection.git
# Check if the git clone was successful
if [ $? -ne 0 ]; then
    LOG_FATAL "Failed to clone repository"
    exit 1
fi
# Check if the cloned repository directory exists
if ! directory_exists Smart-Plug-Connection; then
    LOG_FATAL "Cloned repository directory not found"
    exit 1
fi
# Give execute permission to all scripts in the cloned repository
sudo chmod -R +x Smart-Plug-Connection
# Run the setup script
cd Smart-Plug-Connection
if ! file_exists spc-setup.sh; then
    LOG_FATAL "Setup script not found in the cloned repository"
    exit 1
fi
sudo ./spc-setup.sh