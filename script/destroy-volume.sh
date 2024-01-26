#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
compose="$script_dir/../docker/compose.yml"

printf '%s\n%s\n\n%s' \
	'!! Are you sure you want to destroy the server volume?' \
	'!! This includes all plugins and configuration files.' \
	'This action is irreversible. (y/N): '

read -r option

case $option in
[Yy]*) docker compose --file "$compose" down --remove-orphans --timeout 0 --volumes ;;
*) echo "Operation aborted." ;;
esac
