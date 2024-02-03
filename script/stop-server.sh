#!/bin/bash
set -euo pipefail

case ${1-} in
-f | --force) force=true ;;
esac

force=${force-false}

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
rcon="$script_dir/send-rcon.sh"

running_container_id=$(docker container list --filter name=palworld-server --quiet)

if [ -n "$running_container_id" ]; then
	if $force; then
		compose="$script_dir/../docker/compose.yml"
		docker compose -f "$compose" down --remove-orphans
	else
		"$script_dir/backup.sh"
		"$rcon" shutdown 1 Closing... | grep --ignore-case --invert-match 'Error'
		printf 'Waiting for server to close... '
		docker container wait "$running_container_id" >/dev/null
		printf 'done!\n'
	fi
else
	echo Server is not running!
	exit 2
fi
