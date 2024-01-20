#!/bin/bash
set -euo pipefail
# -e : exit on error
# -u : error on unset variable
# -o pipefail : fail on any error in pipe

export server_user_id=30120
export server_group_id=30120

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
source_dir="$script_dir/.."
logs_dir="$source_dir/logs"
compose_yml=$(readlink --canonicalize "$source_dir/docker/compose.yml")

running_container=$(docker container list --filter name=palworld-server --quiet)

if [ -n "$running_container" ]; then
	echo Server is already running!
	exit 2
fi

compose=(docker compose -f "$compose_yml")

if $update_server; then
	echo Updating server...
	"${compose[@]}" run --rm server-files
	"${compose[@]}" run --rm cmd "chown --recursive $server_user_id:$server_group_id /server-files/"

	# If there is no server group, create it.
	if [ ! "$(getent group server-group)" ]; then
		echo Creating group: server-group
		sudo addgroup --gid "$server_group_id" server-group
	fi

	# If there is no server user, create it.
	if [ ! "$(getent passwd server-user)" ]; then
		echo Creating user: server-user
		sudo adduser --uid "$server_user_id" --gid "$server_group_id" --disabled-password --gecos '' server-user
	fi

	# If the host user is not in the server group, add them.
	if ! id --groups --name | grep --quiet --fixed-strings --word-regexp server-group; then
		echo "Adding current user $(id --user --name) to group: server-group"
		sudo usermod -aG server-group "$(id --user --name)"
	fi

	mount_dir="$("$script_dir/cd-mountpoint.sh" --path)"

	# links FROM the volume TO the host
	echo Linking volume files to host...
	ln --symbolic --no-dereference --force "$mount_dir" "$source_dir/server-files"

	# links FROM the host TO the volume
	echo Linking host files to volume...
	sudo chown --recursive server-user:server-group "$source_dir/cfg/"
	mkdir --parents "$mount_dir/server"
	sudo ln --logical --force "$source_dir/cfg/start.sh" "$mount_dir/server/start.sh"

	# handle=docker container ls -all --quiet --filter name=server-files
fi

compose_run=("${compose[@]}" run --rm --service-ports palworld-server)

log=$(readlink -m "$logs_dir/log-$(date +%Y%j-%H%M%S).txt")
mkdir --parents "$(dirname "$log")"

echo Running command: "${compose_run[*]}"
echo "... with output logging to file: $log"
echo "... in screen daemon; screen -r palworld"

screen -dmS palworld -L -Logfile "$log" "${compose_run[@]}"
