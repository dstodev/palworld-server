#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"

running_container=$(docker container list --filter name=palworld-server --quiet)

if [ -n "$running_container" ]; then
	"$script_dir/backup.sh"

	# palworld commands
	rcon="$script_dir/send-rcon.sh"
	"$rcon" shutdown 1 closing... | grep --ignore-case --invert-match 'Error'

	printf 'Waiting for server to close... '
	docker wait "$running_container" >/dev/null
	printf 'done!\n'
else
	echo Server is not running!
	exit 2
fi
