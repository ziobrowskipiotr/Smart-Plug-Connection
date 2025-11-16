# Smart-Plug-Connection

A collection of shell scripts to manage and monitor smart-plugs with Tasmota firmware. This project allows you to control your smart plugs from the command line, monitor their power consumption in real-time, and log historical data to a SQLite database.

## Features

-   **Command-Line Control**: Implement dedicated `spc` command for your terminal.
-   **Real-Time Monitoring**: Get live data on active power (W), voltage (V), and current (A).
-   **Energy Usage Tracking**: Retrieve daily, monthly, and yearly energy consumption data (kWh).
-   **Automated Data Logging**: A `systemd` timer and service automatically collect and store power consumption data.
-   **Device Management**: Easily add, remove, rename, and list your smart plug devices.
-   **Easy Installation**: A simple one-line command to install all scripts.
-   **Interactive Setup**: An interactive script to configure the database and discover devices on your network.

## Installation

You can install the scripts with a single command. This will download the installer, make the scripts executable, and move them to `/usr/local/bin` for system-wide access.

```bash
curl -sSfL https://raw.githubusercontent.com/ziobrowskipiotr/Smart-Plug-Connection/main/spc-install.sh -o /tmp/spc-install.sh && bash /tmp/spc-install.sh
```

### Automatic Data Collection

To automatically log power consumption data every 5 minutes, set up the `systemd` service and timer. The setup script will offer to do this for you, but you can also do it manually:

```bash
sudo cp spc-collect.service spc-collect.timer /etc/systemd/system/
sudo systemctl enable --now spc-collect.timer
```

## Commands and Usage

All scripts include a `-h` or `--help` flag that displays usage information.

---

### **Device Management**

#### `spc add`
Adds a new smart plug device to the database.
```
Usage: spc add [OPTIONS] <device_name> <ip_address>
  Adds or updates a Tasmota smartplug in the database.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Notes:
  - You must provide both device name and IP address, either as positional arguments or using the flags.
  - If both positional arguments and flags are provided, the flags take precedence.

Examples:
    spc add my_plug 192.168.1.100
    spc add --name my_plug --ip 192.168.1.100
```

#### `spc devices`
Lists all registered devices from the database.
```
Usage: spc devices [OPTIONS]
  Lists all registered devices in JSON format.

Options:
  -h, --help    Display this help message and exit.
```

#### `spc remove`
Removes a device from the database.
```
Usage: spc remove [OPTIONS]

Options:
  --name <device_name>    Remove device by name.
  --ip   <ipv4_address>   Remove device by IPv4 address.
  -h, --help              Show this help and exit.

Notes:
  - You must provide at least --name or --ip.
  - If both are provided, the script will validate that they match.
    If they don't, it will try to find the device on the network.

Examples:
    spc remove --name my_plug
    spc remove --ip 192.168.1.100
    spc remove --name my_plug --ip 192.168.1.100
```

#### `spc rename`
Renames a device in the database.
```
Usage: spc rename (--name <current_name> | --ip <ip_address>) --new-name <new_name>
  Renames a device in the database.

Required Arguments:
  - An identifier for the device to be renamed:
      --name <current_name>   Specify the device by its current name.
      --ip <ip_address>       Specify the device by its IP address.
  
  - The new name for the device:
      --new-name <new_name>   Provide the new name.

Other Options:
  -h, --help              Display this help message and exit.

Examples:
    spc rename --name old_plug --new-name kitchen_plug
    spc rename --ip 192.168.1.105 --new-name office_lamp
```

---

### **Power Control & Status**

#### `spc on`
Turns a device on.
```
Usage: spc on [OPTIONS] <device_name>
       spc on [OPTIONS] <ip_address>
       spc on [OPTIONS]
  Turns a Tasmota smart plug on.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Notes:
  - You can provide a device name, an IP address, or both.
    • If both are provided, they must refer to the same device (name → IP in DB must match the given IP).

Examples:
    spc on my_plug
    spc on 192.168.1.100
    spc on --name my_plug
    spc on --ip 192.168.1.100
```

#### `spc off`
Turns a device off.
```
Usage: spc off [OPTIONS] <device_name>
       spc off [OPTIONS] <ip_address>
       spc off [OPTIONS]
  Turns a Tasmota smart plug off.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Notes:
  - You can provide a device name, an IP address, or both.
    • If both are provided, they must refer to the same device (name → IP in DB must match the given IP).

Examples:
    spc off my_plug
    spc off 192.168.1.100
    spc off --name my_plug
    spc off --ip 192.168.1.100
```

#### `spc state`
Gets the current power state (ON/OFF) of a device.
```
Usage: spc state [OPTIONS]
  Outputs the power state ("ON" or "OFF") of a Tasmota smart plug.
  Exits with 0 on success, 1 on failure.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.
Examples:
    spc state my_plug
    spc state --name my_plug
    spc state --ip 192.168.1.100
```

#### `spc status`
Shows a full status report for one or all devices, including power state, consumption, and network info.
```
Usage: spc status (--name <device_name> | --ip <ip_address>)
  Retrieves full status (state, power, voltage, etc.) from a device
  and returns it in JSON format.

Required Arguments:
  - An identifier for the device:
      --name <device_name>   Specify the device by its name.
      --ip <ip_address>       Specify the device by its IP address.

Other Options:
  -h, --help              Display this help message and exit.

Examples:
    spc status kitchen_plug
    spc status --name kitchen_plug
    spc status --ip 192.168.1.105
```

---

### **Real-Time Monitoring**

#### `spc active-power`
Gets the current active power consumption in Watts (W).
```
Usage: spc active-power [OPTIONS]
  Outputs the current power consumption (in Watts) of a Tasmota smart plug.
  Exits with 0 on success, 1 on failure.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Examples:
    spc active-power kitchen_plug
    spc active-power --name kitchen_plug
    spc active-power --ip 192.168.1.105
```

#### `spc voltage`
Gets the current voltage in Volts (V).
```
Usage: spc voltage [OPTIONS]
  Outputs the current voltage (in Volts) of a Tasmota smart plug.
  Exits with 0 on success, 1 on failure.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Examples:
    spc voltage kitchen_plug
    spc voltage --name kitchen_plug
    spc voltage --ip 192.168.1.105
```

#### `spc current`
Gets the current amperage in Amperes (A).
```
Usage: spc current [OPTIONS]
  Outputs the electrical current (in Amperes) of a Tasmota smart plug.
  Exits with 0 on success, 1 on failure.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Examples:
    spc current kitchen_plug
    spc current --name kitchen_plug
    spc current --ip 192.168.1.105
```

---

### **Energy Consumption**

#### `spc energy-today`
Gets the total energy consumed today in kilowatt-hours (kWh).
```
Usage: spc energy-today [OPTIONS]
  Outputs today's energy consumption (in Wh) of a Tasmota smart plug.
  Exits with 0 on success, 1 on failure.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Examples:
    spc energy-today kitchen_plug
    spc energy-today --name kitchen_plug
    spc energy-today --ip 192.168.1.105
```

#### `spc energy-yesterday`
Gets the total energy consumed yesterday in kilowatt-hours (kWh).
```
Usage: spc energy-yesterday [OPTIONS]
  Outputs yesterday's energy consumption (in Wh) of a Tasmota smart plug.
  Exits with 0 on success, 1 on failure.

Options:
    --name <name>      Specify the device name.
    --ip <ip_address>  Specify the device IPv4 address.
    -h, --help         Display this help message and exit.

Examples:
    spc energy-yesterday kitchen_plug
    spc energy-yesterday --name kitchen_plug
    spc energy-yesterday --ip 192.168.1.105
```

#### `spc energy`
Provides a detailed report of energy consumption for a device, with options to specify a year and month.
```
Usage: spc energy --name <device_name> --from <timestamp> [--to <timestamp>] [--ip <ip_address>]

Outputs energy consumed (Wh) between --from and --to timestamps for a device.
If --to is omitted, the latest measurement for the device is used.

Timestamp formats accepted: epoch seconds (e.g. 1666699200) or any format accepted by "date -d".

Options:
	--name <name>      Device name (required)
	--from "<time>"      Start time in quotation marks (required)
	--to "<time>"        End time in quotation marks (optional; default = latest measurement)
	--ip <ip_address>  Device IP (optional; used together with --name for validation)
	-h, --help         Show this help and exit

Examples:
    spc energy kitchen_plug --from "2023-11-15 15:00:00" --to "2025-11-16 16:00:00"
    spc energy kitchen_plug --from "2023-11-15 15:00:00" --to "2025-11-16 16:00:00"
    spc energy --name kitchen_plug --from "2023-11-15 15:00:00" --to "2025-11-16 16:00:00"
```

## Database Schema

The `schema.sql` file defines two tables:

-   `devices`: Stores information about your smart plug devices (name, IP address).
-   `measurements`: Stores the timestamped energy consumption data.