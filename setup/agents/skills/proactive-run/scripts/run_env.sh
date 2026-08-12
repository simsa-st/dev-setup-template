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
: "${RUN_ROLES:?set RUN_ROLES in meta/run.env (name:window:model ...)}"
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

# RUN_ROLES is "name:window:model" triples, so the window and model maps have a
# single source of truth shared with PROTOCOL.md.
role_field() { # <role> <1=window|2=model>
  local role=$1 field=$2 spec
  for spec in ${RUN_ROLES}; do
    case "${spec}" in
      "${role}":*) printf '%s' "$(printf '%s' "${spec}" | cut -d: -f$((field + 1)))"; return 0 ;;
    esac
  done
  return 1
}
role_window() { role_field "$1" 1; }
role_model() { role_field "$1" 2; }
role_names() { local spec; for spec in ${RUN_ROLES}; do printf '%s\n' "${spec%%:*}"; done; }

# A role name resolves to its fixed window; anything else (a cw-* worker) is
# addressed by window name directly.
target_of() { # <role-or-window>
  local w
  w=$(role_window "$1" 2> /dev/null) || w=$1
  printf '%s:%s' "${RUN_SESSION}" "${w}"
}

# Type a message into an agent TUI and submit it. Agent TUIs treat a fast
# text+Enter burst as a paste and leave it unsent, so send the text, let paste
# detection settle, then submit separately. Never call this on a busy agent.
send_to_agent() { # <target> <text...>
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
ensure_window() { # <window> [name]
  local window=$1 name=${2:-}
  tmx list-windows -t "${RUN_SESSION}" -F '#{window_index}' 2> /dev/null | grep -qx "${window}" && return 0
  if [ -n "${name}" ]; then
    tmx new-window -d -t "${RUN_SESSION}:${window}" -n "${name}" "${RUN_WINDOW_CMD}"
  else
    tmx new-window -d -t "${RUN_SESSION}:${window}" "${RUN_WINDOW_CMD}"
  fi
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
