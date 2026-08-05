#!/usr/bin/env bash
# Launch one detached run whose log survives a dropped SSH connection.
#
#   ./run_task.sh <run_name> [extra args...]
#
# `screen` (rather than nohup) so you can reattach to a live job:
#   screen -r <run_name>        detach again with C-a d
set -euo pipefail

cd "$(dirname "$0")"

run_name="${1:?usage: run_task.sh <run_name> [args...]}"
shift || true

mkdir -p screen_logs data
log="screen_logs/${run_name}.txt"

if screen -ls | grep -q "\.${run_name}[[:space:]]"; then
  echo "A run named '${run_name}' is already going; pick another name or kill it first." >&2
  exit 1
fi

# TODO: the actual command this experiment runs.
cmd=(uv run python main.py --run-name "${run_name}" "$@")

echo "starting '${run_name}': ${cmd[*]}"
echo "  log: ${log}"
screen -L -Logfile "${log}" -dmS "${run_name}" "${cmd[@]}"
