#!/bin/bash
set -euo pipefail
# -e : exit on error
# -u : error on unset variable
# -o pipefail : fail on any error in pipe

help() {
	cat <<-EOF
		Usage: $(basename "$0") [ -u ]
		  -u, --update  Updates the server files before starting the server.
	EOF
}

canonicalized=$(getopt --name "$(basename "$0")" \
	--options hu \
	--longoptions help,update \
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
	-u | --update)
		update_server=true
		;;
	esac
done

update_server=${update_server-false}

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
logs_dir="$script_dir/../logs"
compose_yml=$(readlink --canonicalize "$script_dir/../docker/compose.yml")

running_container=$(docker container list --filter name=palworld-server --quiet)

if [ -n "$running_container" ]; then
	echo Server is already running!
	exit 2
fi

compose=(docker compose -f "$compose_yml")

if $update_server; then
	echo Updating server...
	"${compose[@]}" run --rm server-files
	"${compose[@]}" run --rm cmd "chown --recursive $(id --user):$(id --group) /server-files/"

	mount_dir="$("$script_dir/cd-mountpoint.sh" --path)"

	# links FROM the volume TO the host
	ln --symbolic --no-dereference --force "$mount_dir" "$script_dir/../server-files"

	# links FROM the host TO the volume
	mkdir --parents "$mount_dir/server"
	ln --logical --force "$script_dir/../cfg/start.sh" "$mount_dir/server/start.sh"

	# handle=docker container ls -all --quiet --filter name=server-files
fi

compose_run=("${compose[@]}" run --rm --service-ports --user "$(id --user)" palworld-server)

log=$(readlink -m "$logs_dir/log-$(date +%Y%j-%H%M%S).txt")
mkdir --parents "$(dirname "$log")"

echo Running command: "${compose_run[*]}"
echo "... with output logging to file: $log"
echo "... in screen daemon; screen -r palworld"

screen -dmS palworld -L -Logfile "$log" "${compose_run[@]}"
