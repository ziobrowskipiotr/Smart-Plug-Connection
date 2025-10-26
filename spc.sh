#!/bin/bash
# Dispatcher front-end for spc scripts.
# Usage: spc <command> [args...]
# It will look for a script named spc-<command>.sh in the same directory and execute it.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

show_usage() {
	echo "Usage: $0 <command> [args...]"
	echo
	echo "Available commands:"
	for f in "$SCRIPT_DIR"/spc-*.sh; do
		[ -e "$f" ] || continue
		name=$(basename "$f")
		cmd=${name#spc-}
		cmd=${cmd%.sh}
		echo "  $cmd"
	done
	echo
	echo "Example: $0 on --name myplug"
	echo "To make 'spc' available system-wide, create a symlink to this file in your PATH, e.g.:"
}

if [[ $# -eq 0 ]]; then
	show_usage
	exit 1
fi

CMD="$1"
shift

# Special-case: help for a subcommand
if [[ "$CMD" == "-h" || "$CMD" == "--help" || "$CMD" == "help" ]]; then
	show_usage
	exit 0
fi

# Normalize command to match file names: allow underscore/dash interchange
try_variants() {
	local base="$1"
	local variants=("$base" "${base//_/-}" "${base//-/_}")
	for v in "${variants[@]}"; do
		local candidate="$SCRIPT_DIR/spc-$v.sh"
		if [[ -f "$candidate" ]]; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

SCRIPT_PATH=$(try_variants "$CMD")
if [[ -z "$SCRIPT_PATH" ]]; then
	echo "Unknown command: $CMD" >&2
	echo
	show_usage >&2
	exit 2
fi

# Execute the target script with forwarded arguments. Use bash to avoid needing exec bit.
bash "$SCRIPT_PATH" "$@"
exit $?