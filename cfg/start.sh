#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH-}:$script_dir/.."
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH-}:$script_dir/../linux64"

# For file permissions:
# file: -rw-rw-r--
#  dir: drwxrwxr-x
umask 0002

# Run in a loop unless a stop file is present
while [ ! -f "$script_dir/stop" ]; do
	"$script_dir/../PalServer.sh" -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS
done

rm --force "$script_dir/stop"
