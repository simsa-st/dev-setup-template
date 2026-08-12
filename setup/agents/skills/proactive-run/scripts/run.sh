#!/usr/bin/env bash
# Lifecycle of a proactive run.
#
#   run.sh init <dir> [name]   scaffold the run directory and meta/run.env
#   run.sh start               session + windows + manager + heartbeat loop
#   run.sh stop                kill heartbeat and wakeups, tell the manager to wrap up
#
# init is the only subcommand that does not need an existing run.env: fill in
# the deadline, session, models and window command it writes, then start.
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

cmd_init() {
  local dir=${1:?usage: run.sh init <dir> [name]} name=${2:-}
  mkdir -p "${dir}" || exit 1
  dir=$(cd -- "${dir}" && pwd)
  name=${name:-$(basename "${dir}")}

  mkdir -p "${dir}"/{context,prompts,comms/inbox,comms/read,logs,scratchpads,artifacts,meta}
  for f in PROTOCOL.md STATUS.md; do
    [ -f "${dir}/${f}" ] || cp "${SKILL_DIR}/templates/${f}" "${dir}/${f}"
  done
  for f in role_prompt.md heartbeat_check.md; do
    [ -f "${dir}/prompts/${f}" ] || cp "${SKILL_DIR}/templates/${f}" "${dir}/prompts/${f}"
  done
  : > "${dir}/logs/.gitkeep"
  : > "${dir}/artifacts/.gitkeep"

  if [ ! -f "${dir}/meta/run.env" ]; then
    cat > "${dir}/meta/run.env" << EOF
# Environment of this run. Everything machine- or agent-specific lives here.
RUN_NAME=${name}
RUN_SESSION=${name}
TMUX_SOCKET=\${TMUX_SOCKET:-\${HOME}/tmp-tmux-socket}

# Where the agents work, and how a window opens a shell there. The second form
# is for a containerised environment:
#   RUN_WINDOW_CMD='docker exec -it -w /work <container> zsh'
RUN_WORK_DIR=TODO-repo-the-agents-work-in
RUN_WINDOW_CMD=\${SHELL:-/bin/bash}

# The agent CLI. Pin models explicitly — an ambiguous name once selected the
# wrong provider for a whole run.
RUN_AGENT_BIN=claude
RUN_AGENT_ARGS='--dangerously-skip-permissions'
RUN_MODEL_FLAG=--model
RUN_CONTINUE_FLAG=--continue

# name:window:model — window 0 is the heartbeat by convention. Keep in sync with
# PROTOCOL.md; drop roles you do not need.
RUN_ROLES='heartbeat:0:TODO-cheap-model manager:1:TODO-model tester:2:TODO-model reviewer:3:TODO-model evaluator:4:TODO-model'

# Deadline, and the reset of the usage window if one falls inside the run.
RUN_DEADLINE_UTC=TODO-YYYY-MM-DDTHH:MM:SSZ
RUN_QUOTA_RESET_UTC=
RUN_BUDGET_GOAL_PERCENT=95
RUN_BUDGET_BASELINE_PERCENT=0
RUN_HEARTBEAT_INTERVAL_S=3600
RUN_RATE_LIMIT_SNAPSHOT=/tmp/claude-rate-limits.json
EOF
  fi

  # An inbox per role, plus one the agents use to leave messages for the human.
  for who in manager tester reviewer evaluator human; do
    : >> "${dir}/comms/inbox/${who}.md"
  done

  echo "scaffolded ${dir}"
  echo "next: fill in the TODOs in ${dir}/meta/run.env, write PROTOCOL.md and"
  echo "      prompts/<role>.md (from prompts/role_prompt.md), distil context/,"
  echo "      then: RUN_DIR=${dir} $(basename "${BASH_SOURCE[0]}") start"
}

cmd_start() {
  # shellcheck source=run_env.sh
  source "${SKILL_DIR}/scripts/run_env.sh"
  local role

  if ! tmx has-session -t "${RUN_SESSION}" 2> /dev/null; then
    tmx new-session -d -s "${RUN_SESSION}" -n "$(role_names | head -n1)" "${RUN_WINDOW_CMD}"
    for role in $(role_names | tail -n +2); do
      ensure_window "$(role_window "${role}")" "${role}"
    done
    echo "created session ${RUN_SESSION}"
  else
    echo "session ${RUN_SESSION} already exists"
  fi

  if ! grep -q '^RUN_START_UTC=' "${RUN_DIR}/meta/run.env"; then
    echo "RUN_START_UTC=$(now_utc)" >> "${RUN_DIR}/meta/run.env"
    local base
    base=$(jq -r '.rate_limits.seven_day.used_percentage // empty' \
      "${RUN_RATE_LIMIT_SNAPSHOT}" 2> /dev/null || true)
    [ -n "${base}" ] && echo "RUN_BUDGET_BASELINE_PERCENT=${base%%.*}" >> "${RUN_DIR}/meta/run.env"
    echo "recorded start$([ -n "${base}" ] && echo " + usage baseline ${base%%.*}%")"
  fi

  "${SKILL_DIR}/scripts/agent.sh" start manager

  local pid_file="${RUN_DIR}/meta/heartbeat.pid"
  if [ -f "${pid_file}" ] && kill -0 "$(cat "${pid_file}")" 2> /dev/null; then
    echo "heartbeat already running (pid $(cat "${pid_file}"))"
  else
    nohup setsid "${SKILL_DIR}/scripts/heartbeat.sh" \
      >> "${RUN_DIR}/meta/heartbeat.log" 2>&1 &
    echo $! > "${pid_file}"
    echo "heartbeat loop started (pid $(cat "${pid_file}"))"
  fi

  "${SKILL_DIR}/scripts/time_status.sh"
  echo "watch it: tmux -S ${TMUX_SOCKET} attach -t ${RUN_SESSION}"
}

cmd_stop() {
  # shellcheck source=run_env.sh
  source "${SKILL_DIR}/scripts/run_env.sh"
  local pid_file pid
  for pid_file in "${RUN_DIR}"/meta/heartbeat.pid "${RUN_DIR}"/meta/wakeup_*.pid; do
    [ -f "${pid_file}" ] || continue
    pid=$(cat "${pid_file}")
    if kill -0 "${pid}" 2> /dev/null; then
      kill -- -"${pid}" 2> /dev/null || kill "${pid}" 2> /dev/null || true
      echo "killed $(basename "${pid_file}" .pid) (pid ${pid})"
    fi
    rm -f "${pid_file}"
  done

  send_to_agent "$(target_of manager)" \
    "STOP: the run is being wound down. Tell every agent and worker to finish the current step and go idle, finalize REPORT.md and STATUS.md, update logs and scratchpads, commit the run folder, then stop scheduling anything." || true
  echo "wind-down message sent to the manager"
}

case "${1:-}" in
  init) shift; cmd_init "$@" ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  *) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
