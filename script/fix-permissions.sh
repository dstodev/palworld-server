#!/bin/bash
set -euo pipefail

# This script asserts that all directories up to the mountpoint have
# permissions for others to execute (o+x). This is necessary for users
# to access their volume files without sudo permissions.

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"

IFS=/ read -ra path_parts < <("$script_dir/cd-mountpoint.sh" --path)
path=''

for part in "${path_parts[@]:1}"; do
	path="$path/$part"
	if [ "$(("$(stat -c '%a' "$path")" & 001))" = 0 ]; then
		printf '%s' "Fixing permissions for $path... "
		sudo chmod o+x "$path"
		echo 'OK'
	else
		echo "$path OK"
	fi
done
