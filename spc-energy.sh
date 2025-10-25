#!/bin/bash
# Script to calculate energy consumed between two timestamps (or since a given time until latest)

# Get the directory of the current script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source helpers (defines DB_FILE, logging and device resolution functions)
source "$SCRIPT_DIR/spc-helpers.sh"

show_usage() {
	cat <<EOF
Usage: $0 --name <device_name> --from <timestamp> [--to <timestamp>] [--ip <ip_address>]

Outputs energy consumed (Wh) between --from and --to timestamps for a device.
If --to is omitted, the latest measurement for the device is used.

Timestamp formats accepted: epoch seconds (e.g. 1666699200) or any format accepted by "date -d".

Options:
	--name <name>      Device name (required)
	--from <time>      Start time (required)
	--to <time>        End time (optional; default = latest measurement)
	--ip <ip_address>  Device IP (optional; used together with --name for validation)
	-h, --help         Show this help and exit
EOF
}

# --- Argument parsing ---
if [[ $# -eq 0 ]]; then
	show_usage >&2
	exit 1
fi

NAME=""
IP=""
FROM_RAW=""
TO_RAW=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			show_usage
			exit 0
			;;
		--name)
			NAME="$2"; shift 2
			;;
		--ip)
			IP="$2"; shift 2
			;;
		--from)
			FROM_RAW="$2"; shift 2
			;;
		--to)
			TO_RAW="$2"; shift 2
			;;
		--*)
			LOG_ERROR "Unknown option: $1"
			show_usage
			exit 1
			;;
		*)
			# positional fallback (not recommended)
			if [[ -z "$NAME" ]]; then
				NAME="$1"
			elif [[ -z "$FROM_RAW" ]]; then
				FROM_RAW="$1"
			elif [[ -z "$TO_RAW" ]]; then
				TO_RAW="$1"
			else
				LOG_ERROR "Too many positional arguments"
				show_usage
				exit 1
			fi
			shift
			;;
	esac
done

# Validate required args
if [[ -z "$NAME" ]]; then
	LOG_FATAL "--name is required"
fi
if [[ -z "$FROM_RAW" ]]; then
	LOG_FATAL "--from is required"
fi

# Convert input timestamps to SQLite compatible 'YYYY-MM-DD HH:MM:SS'
convert_to_sqlite_ts() {
	local input="$1"
	local out
	if [[ "$input" =~ ^[0-9]+$ ]]; then
		out=$(date -d "@$input" +"%Y-%m-%d %H:%M:%S" 2>/dev/null) || return 1
	else
		out=$(date -d "$input" +"%Y-%m-%d %H:%M:%S" 2>/dev/null) || return 1
	fi
	echo "$out"
	return 0
}

FROM_TS=$(convert_to_sqlite_ts "$FROM_RAW") || LOG_FATAL "Invalid --from timestamp: $FROM_RAW"

if [[ -n "$TO_RAW" ]]; then
	TO_TS=$(convert_to_sqlite_ts "$TO_RAW") || LOG_FATAL "Invalid --to timestamp: $TO_RAW"
else
	TO_TS=""
fi

# Resolve device IP (and validate device existence). This will exit on failure.
TARGET_IP=$(resolve_device_ip "$NAME" "$IP")

# Get device_id from database
DEVICE_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM devices WHERE name = ?;" "$NAME")
if [[ -z "$DEVICE_ID" ]]; then
	LOG_FATAL "Device '$NAME' not found in database."
fi

# Helper to get nearest measurement (energy_total and timestamp) for a given target time
get_nearest_measurement() {
	local device_id="$1"
	local target_ts="$2" # 'YYYY-MM-DD HH:MM:SS'

	# Query: return energy_total and timestamp separated by |; nearest by absolute seconds diff
	sqlite3 -separator '|' "$DB_FILE" \
		"SELECT energy_total, timestamp FROM measurements WHERE device_id = ? ORDER BY abs(strftime('%s', timestamp) - strftime('%s', ?)) LIMIT 1;" \
		"$device_id" "$target_ts"
}

# Helper to get latest measurement
get_latest_measurement() {
	local device_id="$1"
	sqlite3 -separator '|' "$DB_FILE" \
		"SELECT energy_total, timestamp FROM measurements WHERE device_id = ? ORDER BY strftime('%s', timestamp) DESC LIMIT 1;" \
		"$device_id"
}

# Get from-measurement
FROM_ROW=$(get_nearest_measurement "$DEVICE_ID" "$FROM_TS")
if [[ -z "$FROM_ROW" ]]; then
	LOG_FATAL "No measurement found near --from time ($FROM_TS) for device '$NAME'."
fi
IFS='|' read -r FROM_ENERGY FROM_TS_ACTUAL <<< "$FROM_ROW"

# Get to-measurement (nearest to provided TO_TS or latest if not provided)
if [[ -n "$TO_TS" ]]; then
	TO_ROW=$(get_nearest_measurement "$DEVICE_ID" "$TO_TS")
else
	TO_ROW=$(get_latest_measurement "$DEVICE_ID")
fi

if [[ -z "$TO_ROW" ]]; then
	LOG_FATAL "No measurement found for --to (or latest) for device '$NAME'."
fi
IFS='|' read -r TO_ENERGY TO_TS_ACTUAL <<< "$TO_ROW"

# Validate energies
if [[ ! "$FROM_ENERGY" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
	LOG_FATAL "Invalid energy value for --from measurement: '$FROM_ENERGY' (timestamp: $FROM_TS_ACTUAL)"
fi
if [[ ! "$TO_ENERGY" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
	LOG_FATAL "Invalid energy value for --to measurement: '$TO_ENERGY' (timestamp: $TO_TS_ACTUAL)"
fi

# Compute difference using awk for floats
ENERGY_DIFF=$(awk "BEGIN{printf \"%.6f\", ($TO_ENERGY) - ($FROM_ENERGY)}")

echo "$ENERGY_DIFF"
LOG_INFO "Energy for device '$NAME' between '$FROM_TS_ACTUAL' and '$TO_TS_ACTUAL' = $ENERGY_DIFF Wh"
exit 0

