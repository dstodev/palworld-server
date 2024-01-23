#!/bin/bash
set -euo pipefail

# Add to crontab, running every hour:
#  crontab -e
#  0 * * * * /absolute/path/to/script/backup.sh >/dev/null 2>&1

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
source_dir="$script_dir/.."
backup_dir="$source_dir/backups"

compose_yml=$(readlink --canonicalize "$source_dir/docker/compose.yml")
compose=(docker compose -f "$compose_yml")

mkdir --parents "$backup_dir"

"${compose[@]}" run --rm backup

# Preserve the most recent backups, deleting older ones.
days_to_preserve=14
find "$backup_dir" -maxdepth 1 -type f -mtime +$days_to_preserve -name '*.tar.bz2' -delete
