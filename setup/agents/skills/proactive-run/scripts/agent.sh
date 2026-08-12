#!/usr/bin/env bash
# Lifecycle of one long-lived agent in its fixed window.
#
#   agent.sh start <role>     fresh session with prompts/<role>.md (exits any old one first)
#   agent.sh restart <role>   resume the crashed/exited session with its context intact
#   agent.sh check <role>     print STATE=<RUNNING|IDLE|LIMIT|STOPPED|NO_WINDOW> + pane tail
#   agent.sh stop <role>      clean exit, then keep the window (workers: window is killed)
#
# <role> is a name from RUN_ROLES, or a worker window name (cw-<name>).
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

action=${1:?usage: agent.sh start|restart|check|stop <role>}
role=${2:?role or window name required}
target=$(target_of "${role}")

# Exit the agent currently in the window and verify it is gone: a missed /exit
# turns the next launch command into a chat message for the old agent.
exit_agent() {
  local pane
  pane=$(tmx capture-pane -p -t "${target}" 2> /dev/null || true)
  grep -qE "shift\+tab to cycle|esc to interrupt" <<< "${pane}" || return 0
  tmx send-keys -t "${target}" Escape
  sleep 2
  tmx send-keys -t "${target}" C-u
  tmx send-keys -t "${target}" -l "/exit"
  sleep 2
  tmx send-keys -t "${target}" C-m
  local waited=0
  while [ "$((waited += 3))" -le 60 ]; do
    sleep 3
    pane=$(tmx capture-pane -p -t "${target}" 2> /dev/null || true)
    grep -qE "shift\+tab to cycle|esc to interrupt" <<< "${pane}" || return 0
  done
  return 1
}

case "${action}" in
  start)
    ensure_window "$(role_window "${role}")" "${role}"
    exit_agent || { echo "ERROR: old agent in ${target} did not exit; not launching ${role}" >&2; exit 1; }
    tmx send-keys -t "${target}" "cd ${RUN_WORK_DIR}" Enter
    sleep 1
    tmx send-keys -t "${target}" \
      "$(agent_launch_cmd "$(role_model "${role}")") 'Read ${RUN_DIR}/prompts/${role}.md and follow it. You are the ${role} of this run.'" C-m
    wait_for_agent_ui "${target}" 90 || true
    "${SKILL_DIR}/scripts/message.sh" log heartbeat "started ${role} (model $(role_model "${role}")) in ${target}"
    echo "${role} launched in ${target}"
    ;;
  restart)
    tmx send-keys -t "${target}" C-c
    sleep 1
    tmx send-keys -t "${target}" "cd ${RUN_WORK_DIR}" Enter
    sleep 1
    tmx send-keys -t "${target}" \
      "$(agent_launch_cmd "$(role_model "${role}")" "${RUN_CONTINUE_FLAG}")" C-m
    if wait_for_agent_ui "${target}" 90; then
      sleep 2
      send_to_agent "${target}" \
        "You were restarted. Before anything else read ${RUN_DIR}/scratchpads/${role}.md, run ${SKILL_DIR}/scripts/message.sh read ${role} and ${SKILL_DIR}/scripts/time_status.sh, then continue your highest-priority work per prompts/${role}.md."
      "${SKILL_DIR}/scripts/message.sh" log heartbeat "restarted ${role} with context in ${target}"
      echo "${role} resumed in ${target}"
    else
      echo "${role} did not come up — starting it fresh" >&2
      exec "${BASH_SOURCE[0]}" start "${role}"
    fi
    ;;
  check)
    if ! pane=$(tmx capture-pane -p -t "${target}" 2> /dev/null); then
      echo "STATE=NO_WINDOW"
      exit 0
    fi
    tail=$(grep -v '^$' <<< "${pane}" | tail -25)
    state=STOPPED
    # Busy markers: the interrupt hint, the spinner's token counter, or the
    # run-in-background hint.
    if grep -qE "esc to interrupt|esc to cancel|ctrl\+b to run in background|·[[:space:]]*[↑↓].*tokens" <<< "${tail}"; then
      state=RUNNING
    # Only real limit banners: agents constantly *mention* resets in their own
    # prose, so a bare "resets at" must not classify as LIMIT.
    elif grep -qiE "(reached|exceeded|hit) (your|the)? ?(usage|5-hour|weekly|session)? ?limit|limit (reached|exceeded)|out of (tokens|credits)" <<< "${tail}"; then
      state=LIMIT
    elif grep -qE "shift\+tab to cycle|❯" <<< "${tail}"; then
      state=IDLE
    fi
    echo "STATE=${state}"
    echo "--- pane tail (${target}):"
    printf '%s\n' "${tail}"
    ;;
  stop)
    # Exiting the agent first matters: killing the window alone leaves the
    # agent process running as an orphan.
    if ! exit_agent; then
      echo "ERROR: agent in ${target} did not exit — window kept. Identify the" \
        "process by its process tree and working directory before killing it." >&2
      exit 1
    fi
    case "${role}" in
      cw-*) tmx kill-window -t "${target}" 2> /dev/null || true ;;
    esac
    "${SKILL_DIR}/scripts/message.sh" log heartbeat "stopped ${role} (clean exit)"
    echo "${role} stopped cleanly"
    ;;
  *)
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
