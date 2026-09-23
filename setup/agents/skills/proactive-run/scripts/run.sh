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
  for f in PROTOCOL.md WORKER_PROTOCOL.md STATUS.md; do
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
#
# Skipping permissions is what makes an unattended run possible at all: a
# prompt nobody is there to answer stalls that agent until the deadline. The
# price is that every role runs unconfirmed for the length of the run, so point
# RUN_WORK_DIR at a repo whose blast radius you accept.
RUN_AGENT_BIN=claude
RUN_AGENT_ARGS='--dangerously-skip-permissions'
# Environment prefix for that command. A containerised run is commonly root,
# and claude refuses to skip permissions as root unless IS_SANDBOX=1 says the
# confinement was deliberate -- without it such a run dies at launch.
# DISABLE_AUTOUPDATER=1 stops Claude Code's own updater: a worker that
# self-updates mid-run parks at "Update installed - Restart to update" with an
# empty prompt, which liveness reads as idle. (DISABLE_AUTO_UPDATE is the
# oh-my-zsh switch, a different prompt -- heartbeat.sh sets that one.)
RUN_AGENT_ENV='IS_SANDBOX=1 DISABLE_AUTOUPDATER=1'
RUN_MODEL_FLAG=--model
RUN_CONTINUE_FLAG=--continue

# name:model — each role gets a window named after it. Keep in sync with
# PROTOCOL.md; drop roles you do not need.
# A role may run on pi instead: 'name:pi/<provider>/<model>' (e.g.
# pi/openai-codex/<model>); workers take the same spelling as their model.
RUN_ROLES='heartbeat:TODO-cheap-model manager:TODO-model tester:TODO-model reviewer:TODO-model evaluator:TODO-model'

# Deadline, and the reset of the usage window if one falls inside the run.
RUN_DEADLINE_UTC=TODO-YYYY-MM-DDTHH:MM:SSZ
RUN_QUOTA_RESET_UTC=
RUN_BUDGET_GOAL_PERCENT=95
# Share of the FRESH long window allowed after RUN_QUOTA_RESET_UTC (default: same goal).
RUN_BUDGET_GOAL_PERCENT_AFTER_RESET=
RUN_BUDGET_BASELINE_PERCENT=0
RUN_SHORT_WINDOW_MAX_PERCENT=90
# 1 only when the human has said the run may continue on extra-usage credits;
# time_status.sh and the heartbeat prompt then stop advising to decline them.
RUN_ALLOW_CREDITS=0
RUN_HEARTBEAT_INTERVAL_S=3600
RUN_RATE_LIMIT_SNAPSHOT=/tmp/claude-rate-limits.json

# pi (Codex subscription) — usage via scripts/codex_usage.sh; cap on either window.
# Empty uses this pi agent directory's ignored usage file (keeps setups apart).
RUN_CODEX_SNAPSHOT=
RUN_CODEX_MAX_PERCENT=95

# Any external per-call paid service the run drives programmatically (a
# proxied LLM key, a paid search/data API) needs its own approved spend cap
# and a script that snapshots spend against it — see the comment in
# time_status.sh for the snapshot shape it expects. Leave both empty to skip
# the meter, but then nothing may call that service: unmetered spend must not
# happen, and only a human may authorise going over the cap.
RUN_EXTERNAL_SPEND_SNAPSHOT=
RUN_EXTERNAL_SPEND_CAP_USD=

# System monitor (scripts/sysmon.sh): alert thresholds.
RUN_MIN_MEM_AVAIL_MB=1500
RUN_MIN_DISK_FREE_GB=5
RUN_SYSMON_INTERVAL_S=120
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

  # The run owns its session outright: its windows are named after roles and
  # workers, agents address each other by window name, and the heartbeat and
  # the stop script kill and create windows in it. Sharing a session with a
  # human's own windows is how a stray window gets killed or nudged.
  if ! tmx has-session -t "${RUN_SESSION}" 2> /dev/null; then
    tmx new-session -d -s "${RUN_SESSION}" -n "$(role_names | head -n1)" "${RUN_WINDOW_CMD}"
    for role in $(role_names | tail -n +2); do
      ensure_window "${role}"
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
  if [ -f "${pid_file}" ] && proc_alive "$(cat "${pid_file}")"; then
    echo "heartbeat already running (pid $(cat "${pid_file}"))"
  else
    DETACH_LOG="${RUN_DIR}/meta/heartbeat.log"
    export DETACH_LOG
    detach "${SKILL_DIR}/scripts/heartbeat.sh" > "${pid_file}"
    echo "heartbeat loop started (pid $(cat "${pid_file}"))"
  fi

  local sm_pid="${RUN_DIR}/meta/sysmon.pid"
  if [ -f "${sm_pid}" ] && proc_alive "$(cat "${sm_pid}")"; then
    echo "sysmon already running (pid $(cat "${sm_pid}"))"
  else
    DETACH_LOG="${RUN_DIR}/meta/sysmon.err"
    export DETACH_LOG
    detach "${SKILL_DIR}/scripts/sysmon.sh" > "${sm_pid}"
    echo "system monitor started (pid $(cat "${sm_pid}"))"
  fi

  "${SKILL_DIR}/scripts/time_status.sh"
  echo "watch it: tmux -S ${TMUX_SOCKET} attach -t ${RUN_SESSION}"
}

cmd_stop() {
  # shellcheck source=run_env.sh
  source "${SKILL_DIR}/scripts/run_env.sh"
  local pid_file pid
  for pid_file in "${RUN_DIR}"/meta/heartbeat.pid "${RUN_DIR}"/meta/sysmon.pid "${RUN_DIR}"/meta/wakeup_*.pid; do
    [ -f "${pid_file}" ] || continue
    pid=$(cat "${pid_file}")
    if proc_alive "${pid}"; then
      kill -- -"${pid}" 2> /dev/null || kill "${pid}" 2> /dev/null || true
      echo "killed $(basename "${pid_file}" .pid) (pid ${pid})"
    fi
    rm -f "${pid_file}"
  done

  send_to_agent_now "$(target_of manager)" \
    "STOP: the run is being wound down. Tell every agent and worker to finish the current step and go idle, finalize REPORT.md and STATUS.md, update logs and scratchpads, commit the run folder, then stop scheduling anything." || true
  echo "wind-down message sent to the manager"
}

case "${1:-}" in
  init) shift; cmd_init "$@" ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  *) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
