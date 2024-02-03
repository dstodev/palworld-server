#!/bin/bash
set -euo pipefail

# Add to crontab, running every hour:
#  crontab -e
#  0 * * * * /absolute/path/to/script/backup.sh >/dev/null 2>&1

case ${1-} in
-f | --force) force=true ;;
esac

force=${force-false}

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
source_dir="$(readlink --canonicalize "$script_dir/..")"
backup_dir="$source_dir/backups"

compose_yml="$source_dir/docker/compose.yml"
compose=(docker compose --file "$compose_yml")

mkdir --parents "$backup_dir"

rcon="$script_dir/send-rcon.sh"

if $force; then
	# Try to save, but continue on error.
	"$rcon" save >/dev/null 2>&1
else
	# Exit on error e.g. server is not running
	# server does not need to be running to save, but this prevents
	# automated backups when the server is not running.
	"$rcon" save | grep --ignore-case --invert-match 'Error'
fi

"${compose[@]}" run --rm backup

# Preserve most recent backups, deleting older ones.
days_to_preserve=14
find "$backup_dir" -maxdepth 1 -type f -mtime +$days_to_preserve -name '*.tar.bz2' -delete
