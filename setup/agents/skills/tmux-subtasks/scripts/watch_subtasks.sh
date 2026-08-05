#!/usr/bin/env bash
# Poll until every named subtask reports a status, printing one compact line per
# poll so the parent agent spends as little context as possible on waiting.
#
#   watch_subtasks.sh <task_dir> <interval_s> <max_polls> <name>...
set -euo pipefail

task_dir="${1:?task_dir required}"
interval="${2:?interval required}"
max_polls="${3:?max polls required}"
shift 3
names=("$@")
[ ${#names[@]} -gt 0 ] || { echo "at least one subtask name required" >&2; exit 2; }

progress="${task_dir}/progress.log"
for ((poll = 1; poll <= max_polls; poll++)); do
  done_count=0
  line=""
  for name in "${names[@]}"; do
    # `|| true`: a subtask that has not reported yet makes grep exit 1, which
    # would otherwise kill this script on its first poll under `set -e`.
    status=$(grep -oE "STATUS: [A-Z]+ — ${name}" "${progress}" 2> /dev/null | tail -1 | awk '{print $2}' || true)
    if [ -n "${status}" ]; then
      done_count=$((done_count + 1))
    else
      status="running"
    fi
    line+="${name}=${status} "
  done
  echo "[poll ${poll}/${max_polls}] ${line}"
  if [ "${done_count}" -eq "${#names[@]}" ]; then
    echo "all subtasks reported; results in ${task_dir}/results/"
    exit 0
  fi
  sleep "${interval}"
done

echo "timed out after ${max_polls} polls; still running: check tmux windows named sub-*" >&2
exit 1
