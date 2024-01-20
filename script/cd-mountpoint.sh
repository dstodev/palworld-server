#!/bin/bash
set -euo pipefail

case ${1-} in
-p | --path) path_only=true ;;
esac

path_only=${path_only-false}

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
compose="$script_dir/../docker/compose.yml"

volume_name=$(docker compose -f "$compose" config --volumes)
docker_volume=$(docker volume ls --filter "name=$volume_name" --quiet)
inspect=$(docker volume inspect "$docker_volume")
mountpoint=$(grep Mountpoint <<<"$inspect" | awk '{ print $2 }' | tr -d ',"')

if $path_only; then
	echo "$mountpoint"
else
	cd "$mountpoint" && exec bash -i
fi
