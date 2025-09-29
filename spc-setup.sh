if [ "$EUID" -ne 0 ]; then
  echo "This command must be running with root privileges"
  exit 1
fi
