#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && env pwd --physical)"
logs_dir="$script_dir/../logs"

case ${1-} in
-f | --follow) follow=true ;;
esac

follow=${follow-false}

if logs=$(ls -At "$logs_dir" 2>/dev/null) && [ -n "$logs" ]; then
	newest_log=$(echo "$logs" | head -n 1)
	cmd=(less)
	[ "$follow" = true ] && cmd+=(+F)
	"${cmd[@]}" "$logs_dir/$newest_log"
else
	echo "No log files found!"
fi
