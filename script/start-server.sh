#!/bin/bash
set -euo pipefail
# -e : exit on error
# -u : error on unset variable
# -o pipefail : fail on any error in pipe

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
source_dir="$(readlink --canonicalize "$script_dir/..")"
docker_dir="$source_dir/docker"

help() {
	cat <<-EOF
		Usage: $(basename "$0") [ -u ]
		  -h, --help    Prints this message.
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

if $update_server; then
	if ! sudo --non-interactive true 2>/dev/null; then
		echo sudo password required to update server files.
		echo This is to fix server file permissions after updating.
		sudo --validate || exit
	fi
fi

logs_dir="$source_dir/logs"
compose_yml="$docker_dir/compose.yml"

running_container=$(docker container list --filter name=palworld-server --quiet)

if [ -n "$running_container" ]; then
	echo Server is already running!
	exit 2
fi

compose=(docker compose --file "$compose_yml")

if $update_server; then
	echo Updating server...
	"${compose[@]}" run --rm server-files

	"$script_dir/fix-permissions.sh"

	mount_dir="$("$script_dir/cd-mountpoint.sh" --path)"

	echo Linking host files to volume...

	mkdir --parents "$mount_dir/server"
	ln --logical --force "$source_dir/cfg/start.sh" "$mount_dir/server/start.sh"

	echo Linking volume files to host...

	ln --symbolic --no-dereference --force "$mount_dir" "$source_dir/server-files"

	# handle=docker container ls -all --quiet --filter name=server-files
fi

compose_run=("${compose[@]}" --progress plain run --rm --service-ports palworld-server)

log="$logs_dir/log-$(date +%Y%j-%H%M%S).txt"
mkdir --parents "$(dirname "$log")"

echo Running command: "${compose_run[*]}"
echo "... with output logging to file: $log"
echo "... in screen daemon; screen -r palworld"

screen -dmS palworld -L -Logfile "$log" "${compose_run[@]}"
