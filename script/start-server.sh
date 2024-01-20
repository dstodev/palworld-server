#!/bin/bash
set -euo pipefail
# -e : exit on error
# -u : error on unset variable
# -o pipefail : fail on any error in pipe

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
source_dir="$script_dir/.."
docker_dir="$source_dir/docker"

# shellcheck disable=SC2046
export $(xargs < "$docker_dir/.env")

server_user_id="$SERVER_USER_ID"
server_user_name="$SERVER_USER_NAME"
server_group_id="$SERVER_GROUP_ID"
server_group_name="$SERVER_GROUP_NAME"

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

logs_dir="$source_dir/logs"
compose_yml=$(readlink --canonicalize "$docker_dir/compose.yml")

running_container=$(docker container list --filter name=palworld-server --quiet)

if [ -n "$running_container" ]; then
	echo Server is already running!
	exit 2
fi

compose=(docker compose -f "$compose_yml")

if $update_server; then
	# If there is no server group, create it.
	if [ ! "$(getent group "$server_group_name")" ]; then
		echo Creating group: "$server_group_name"
		sudo groupadd --gid "$server_group_id" "$server_group_name"
	fi

	# If there is no server user, create it.
	if [ ! "$(getent passwd "$server_user_name")" ]; then
		echo Creating user: "$server_user_name"
		sudo useradd --uid "$server_user_id" --gid "$server_group_id" "$server_user_name"
	fi

	# If the host user is not in the server group, add them.
	if ! id --groups --name | grep --quiet --fixed-strings --word-regexp "$server_group_name"; then
		echo "Adding current user $(id --user --name) to group: $server_group_name"
		sudo usermod -aG "$server_group_name" "$(id --user --name)"
	fi

	echo Updating server...
	"${compose[@]}" run --rm server-files

	mount_dir="$("$script_dir/cd-mountpoint.sh" --path)"

	echo Fixing file permissions...
	sudo chown --recursive "$server_user_name:$server_group_name" "$mount_dir"
	sudo chmod --recursive g+w,g+s "$mount_dir"  # required for mkdir later
	sudo chown --recursive "$server_user_name:$server_group_name" "$source_dir/cfg/"

	# links FROM the host TO the volume
	echo Linking host files to volume...
	mkdir --parents "$mount_dir/server"
	ln --logical --force "$source_dir/cfg/start.sh" "$mount_dir/server/start.sh"

	# links FROM the volume TO the host
	echo Linking volume files to host...
	ln --symbolic --no-dereference --force "$mount_dir" "$source_dir/server-files"

	# handle=docker container ls -all --quiet --filter name=server-files
fi

compose_run=("${compose[@]}" run --rm --service-ports palworld-server)

log=$(readlink -m "$logs_dir/log-$(date +%Y%j-%H%M%S).txt")
mkdir --parents "$(dirname "$log")"

echo Running command: "${compose_run[*]}"
echo "... with output logging to file: $log"
echo "... in screen daemon; screen -r palworld"

screen -dmS palworld -L -Logfile "$log" "${compose_run[@]}"
