#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
source_dir="$script_dir/.."
compose_yml=$(readlink --canonicalize "$source_dir/docker/compose.yml")
backup_dir="$source_dir/backups"

mkdir --parents "$backup_dir"

compose=(docker compose -f "$compose_yml")

"${compose[@]}" run --rm backup
