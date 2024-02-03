#!/bin/bash
set -euo pipefail

# Add to crontab, restarting every day at 5am:
#  crontab -e
#  0 5 * * * /absolute/path/to/script/stop-server.sh --restart --time 30 >/dev/null 2>&1

help() {
	cat <<-EOF
		Usage: $(basename "$0") [ -f ] [ -t <time> ] [ -r ]
		  -h, --help     Prints this message.
		  -f, --force    Force stop the server. Does not backup or wait.
		  -t, --time     Time in seconds to wait before stopping the server.
		  -r, --restart  Restart the server after stopping.
	EOF
}

canonicalized=$(getopt --name "$(basename "$0")" \
	--options hft:r \
	--longoptions help,force,time:,restart \
	-- "$@") || status=$?

if [ "${status-0}" -ne 0 ]; then
	help
	exit 1
fi

eval set -- "$canonicalized"

for arg in "$@"; do
	case $arg in
	-h | --help)
		help
		exit 0
		;;
	-f | --force)
		force=true
		shift
		;;
	-t | --time)
		if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
			time="$2"
			shift 2
		else
			echo "Error: --time option requires a value."
			exit 1
		fi
		;;
	-r | --restart)
		restart=true
		shift
		;;
	esac
done

force=${force-false}
restart=${restart-false}
time=${time-10}

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
rcon="$script_dir/send-rcon.sh"

running_container_id=$(docker container list --filter name=palworld-server --quiet)

if [ -n "$running_container_id" ]; then
	if $force; then
		compose="$script_dir/../docker/compose.yml"
		docker compose -f "$compose" down --remove-orphans
	else
		"$rcon" shutdown "$time" "Closing_in_${time}_seconds..." | grep --ignore-case --invert-match 'Error'
		printf 'Waiting for server to close... '
		docker container wait "$running_container_id" >/dev/null
		printf 'done!\n'

		"$script_dir/backup.sh" --force
	fi
else
	echo Server is not running!

	if ! $restart; then
		exit 2
	fi
fi

if $restart; then
	"$script_dir/start-server.sh"
fi
