#!/bin/bash
set -euo pipefail

# Add to crontab, running every hour:
#  crontab -e
#  0 * * * * /absolute/path/to/script/backup.sh >/dev/null 2>&1

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
source_dir="$script_dir/.."
compose_yml=$(readlink --canonicalize "$source_dir/docker/compose.yml")
backup_dir="$source_dir/backups"

mkdir --parents "$backup_dir"

compose=(docker compose -f "$compose_yml")

"${compose[@]}" run --rm backup
