#!/usr/bin/env bash
# Shared environment for the proactive-run scripts. Source it, do not execute.
#
# Finds the run directory from ${RUN_DIR}, else by walking up from $PWD looking
# for meta/run.env, and sources that file. Everything environment-specific
# (session name, models, how a shell is opened in a window) lives there, so
# these scripts stay portable.
set -uo pipefail

if [ -z "${RUN_DIR:-}" ]; then
  d=$PWD
  while [ "${d}" != "/" ]; do
    if [ -f "${d}/meta/run.env" ]; then RUN_DIR=${d}; break; fi
    d=$(dirname "${d}")
  done
fi
[ -n "${RUN_DIR:-}" ] || { echo "No run directory: set RUN_DIR or cd into one." >&2; exit 2; }
RUN_DIR=$(cd -- "${RUN_DIR}" && pwd)
export RUN_DIR

# shellcheck source=/dev/null
[ -f "${RUN_DIR}/meta/run.env" ] && source "${RUN_DIR}/meta/run.env"

: "${RUN_SESSION:?set RUN_SESSION in meta/run.env}"
: "${RUN_ROLES:?set RUN_ROLES in meta/run.env (name:model ...)}"
export TMUX_SOCKET="${TMUX_SOCKET:-${HOME}/tmp-tmux-socket}"
export RUN_WORK_DIR="${RUN_WORK_DIR:-${RUN_DIR}}"
export RUN_WINDOW_CMD="${RUN_WINDOW_CMD:-${SHELL:-/bin/bash}}"
export RUN_AGENT_BIN="${RUN_AGENT_BIN:-claude}"
export RUN_AGENT_ARGS="${RUN_AGENT_ARGS:-}"
export RUN_MODEL_FLAG="${RUN_MODEL_FLAG:---model}"
export RUN_CONTINUE_FLAG="${RUN_CONTINUE_FLAG:---continue}"
export RUN_BUDGET_GOAL_PERCENT="${RUN_BUDGET_GOAL_PERCENT:-95}"
export RUN_HEARTBEAT_INTERVAL_S="${RUN_HEARTBEAT_INTERVAL_S:-3600}"
export RUN_RATE_LIMIT_SNAPSHOT="${RUN_RATE_LIMIT_SNAPSHOT:-/tmp/claude-rate-limits.json}"

tmx() { tmux -S "${TMUX_SOCKET}" "$@"; }

# RUN_ROLES is "name:model" pairs, so the model map has one source of truth,
# shared with PROTOCOL.md. Every window is addressed by NAME — a role's window
# is named after the role, a worker's after the worker (cw-<name>). An index is
# not a stable address: a window whose command fails is destroyed, the rest
# renumber, and the next thing addressed at that index is somebody else's work.
role_model() { # <role>
  local role=$1 spec
  for spec in ${RUN_ROLES}; do
    case "${spec}" in "${role}":*) printf '%s' "${spec#*:}"; return 0 ;; esac
  done
  return 1
}
role_names() { local spec; for spec in ${RUN_ROLES}; do printf '%s\n' "${spec%%:*}"; done; }

# Qualify a role or worker window with the session, tolerating a target that is
# already qualified: prefixing the session twice yields a target no window can
# match, and whatever was aimed at it fails silently — one run lost 16 wakeups
# that way, each one visible only in a log hours later, when it fired.
target_of() { # <role-or-window>
  printf '%s:%s' "${RUN_SESSION}" "${1#"${RUN_SESSION}:"}"
}

window_exists() { # <window>
  local w=${1#"${RUN_SESSION}:"}
  tmx list-windows -t "${RUN_SESSION}" -F '#{window_index} #{window_name}' 2> /dev/null |
    grep -qE "^${w} |^[0-9]+ ${w}\$"
}

window_list() {
  tmx list-windows -t "${RUN_SESSION}" -F '#{window_index}:#{window_name}' 2> /dev/null | tr '\n' ' '
}

# Classify what is in a window: RUNNING | IDLE | LIMIT | STOPPED | NO_WINDOW.
# A heuristic — read the pane yourself before acting on it. The input line
# renders BELOW the working area, so an agent eleven minutes into a tool call
# shows a bare prompt at the bottom of its pane and reads as idle: never judge
# from the last line.
pane_state() { # <target>
  local pane tail
  pane=$(tmx capture-pane -p -t "$1" 2> /dev/null) || { echo NO_WINDOW; return 0; }
  tail=$(grep -v '^$' <<< "${pane}" | tail -25)
  # The elapsed timer is the busy marker that always holds. Do NOT match the
  # spinner's verb: it is randomised, so any word list you write is incomplete
  # and will call a working agent idle. The minutes part is optional, and that
  # is not a detail — a pattern demanding `[0-9]+m [0-9]+s` is blind for the
  # first 60 seconds of every turn, which is exactly when an agent has just been
  # given work and is most likely to be looked at. One run typed into three
  # working agents through that hole, in the rule written to prevent it.
  if grep -qE '\(([0-9]+m )?[0-9]+s · |esc to interrupt|esc to cancel|ctrl\+b to run in background' <<< "${tail}"; then
    echo RUNNING
  # Only a real limit banner: agents constantly *mention* resets in their own
  # prose, so a bare "resets at" must not classify as LIMIT.
  elif grep -qiE '(reached|exceeded|hit) (your|the)? ?(usage|5-hour|weekly|session)? ?limit|limit (reached|exceeded)|out of (tokens|credits)' <<< "${tail}"; then
    echo LIMIT
  elif grep -qE 'shift\+tab to cycle|❯' <<< "${tail}"; then
    echo IDLE
  else
    echo STOPPED
  fi
}

# Type a message into an agent TUI and submit it. Agent TUIs treat a fast
# text+Enter burst as a paste and leave it unsent, so send the text, let paste
# detection settle, then submit separately.
#
# The state is re-read here, immediately before typing, and not trusted from
# whatever decided to call this: the gap between judging a pane idle and typing
# into it is where this goes wrong.
send_to_agent() { # <target> <text...>
  local target=$1
  shift
  if [ "$(pane_state "${target}")" = RUNNING ]; then
    echo "refusing to type into ${target}: it is working (send_to_agent_now queues it deliberately)" >&2
    return 1
  fi
  send_to_agent_now "${target}" "$@"
}

# Type into a window whatever its state; the text queues as the agent's next
# input. For deliberate interruptions only — a stop, or a wake that must not
# wait for the recipient's next cycle.
send_to_agent_now() { # <target> <text...>
  local target=$1
  shift
  tmx send-keys -t "${target}" -l "$*"
  sleep 2
  tmx send-keys -t "${target}" C-m
}

# Wait until an agent TUI is drawn, answering a workspace-trust dialog if one
# appears. Adjust the markers if your agent's TUI differs.
wait_for_agent_ui() { # <target> [timeout_s]
  local target=$1 timeout=${2:-90} waited=0 pane
  while [ "${waited}" -lt "${timeout}" ]; do
    pane=$(tmx capture-pane -p -t "${target}" 2> /dev/null || true)
    if grep -q "Do you trust the files" <<< "${pane}"; then
      tmx send-keys -t "${target}" Enter
    elif grep -qE "shift\+tab to cycle|esc to interrupt" <<< "${pane}"; then
      return 0
    fi
    sleep 3
    waited=$((waited + 3))
  done
  echo "warning: no agent UI in ${target} after ${timeout}s" >&2
  return 1
}

agent_launch_cmd() { # <model> [extra-args...]
  local model=$1
  shift
  printf '%s %s %s %s' "${RUN_AGENT_BIN}" "${RUN_MODEL_FLAG} ${model}" "${RUN_AGENT_ARGS}" "$*"
}

# Open a window running a shell in the run's working environment. RUN_WINDOW_CMD
# is a plain shell locally, or e.g. `docker exec -it -w /work <container> zsh`.
# Create against the SESSION, never against `session:name`: tmux reads that as
# "at the position of the window called name", so it cannot create one.
ensure_window() { # <window>
  local name=${1#"${RUN_SESSION}:"}
  window_exists "${name}" && return 0
  tmx new-window -d -t "${RUN_SESSION}" -n "${name}" "${RUN_WINDOW_CMD}"
}

# Serialize inbox reads/writes: several agents and workers append concurrently.
# flock where it exists (Linux), a mkdir spin lock elsewhere (macOS has none).
lock_do() { # <lockfile> <function-or-command...>
  local lock=$1 waited=0
  shift
  if command -v flock > /dev/null 2>&1; then
    (
      flock 9
      "$@"
    ) 9> "${lock}"
  else
    until mkdir "${lock}.d" 2> /dev/null; do
      sleep 1
      waited=$((waited + 1))
      [ "${waited}" -ge 10 ] && break
    done
    "$@"
    rmdir "${lock}.d" 2> /dev/null || true
  fi
}

# True only for a process that is actually running. `kill -0` succeeds for a
# zombie too, and this run's own background processes — setsid'd wakeups, the
# heartbeat loop — are never reaped, so a wakeup that has already FIRED keeps
# answering "still pending" forever. One run had all ten recorded wakeup pids
# pass `kill -0` while not one was armed: the scheduler and the watchdog that
# was meant to catch it both believed the manager had a cycle coming.
proc_alive() { # <pid>
  local pid=${1:-} state
  [ -n "${pid}" ] || return 1
  state=$(ps -o stat= -p "${pid}" 2> /dev/null | tr -d ' ')
  [ -n "${state}" ] || return 1
  case "${state}" in Z*) return 1 ;; *) return 0 ;; esac
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# GNU and BSD date disagree on parsing; try both so these scripts work on a
# Linux box and a Mac.
epoch_of() { # <utc-timestamp>
  date -u -d "$1" +%s 2> /dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2> /dev/null
}

load_1m() {
  if [ -r /proc/loadavg ]; then
    cut -d' ' -f1 /proc/loadavg
  else
    uptime | sed -E 's/.*load averages?: ([0-9.]+).*/\1/'
  fi
}
