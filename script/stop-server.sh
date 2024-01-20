#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
compose="$script_dir/../docker/compose.yml"

docker compose -f "$compose" down --remove-orphans
