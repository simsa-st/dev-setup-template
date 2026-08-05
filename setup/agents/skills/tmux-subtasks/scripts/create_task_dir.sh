#!/usr/bin/env bash
# Create a task directory for a set of subtasks and print its path.
# Always under $TMPDIR//tmp, never inside the repo.
set -euo pipefail

summary="${1:-subtasks}"
slug=$(printf '%s' "${summary}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-40)
slug="${slug%-}"

base="${TMPDIR:-/tmp}"
task_dir="${base%/}/subtasks-${slug:-task}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${task_dir}/prompts" "${task_dir}/results" "${task_dir}/logs"
: > "${task_dir}/progress.log"
printf '%s\n' "${task_dir}"
