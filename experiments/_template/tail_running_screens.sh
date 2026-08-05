#!/usr/bin/env bash
# Print the last log line of every running screen job in this experiment — the
# cheapest way (for a human or an agent) to see where a batch of runs stands
# without opening any log.
set -euo pipefail

cd "$(dirname "$0")"

lines="${1:-1}"

screen -ls 2> /dev/null | awk '/\t/ {print $1}' | cut -d. -f2- | sort | while read -r job; do
  log="screen_logs/${job}.txt"
  [ -f "${log}" ] || continue
  echo "==> ${job} <=="
  tail -n "${lines}" "${log}"
  echo
done
