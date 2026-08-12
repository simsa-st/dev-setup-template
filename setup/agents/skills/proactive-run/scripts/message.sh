#!/usr/bin/env bash
# Inboxes and event logs — the run's whole communication system.
#
#   message.sh send <from> <to> <text...>   append to <to>'s inbox; nudge only if idle
#   message.sh read <who>                   print and archive <who>'s inbox
#   message.sh log  <who> <text...>         append one timestamped line to <who>'s log
#
# `to` is a role, a worker window (cw-<name>), or `human` (file only — nobody is
# watching). A busy recipient is never typed into; it reads at its next cycle.
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

action=${1:?usage: message.sh send|read|log ...}
shift

case "${action}" in
  send)
    from=${1:?from required}
    to=${2:?to required}
    shift 2
    msg=$*
    inbox="${RUN_DIR}/comms/inbox/${to}.md"
    append_inbox() {
      printf -- '- %s **%s → %s**: %s\n' "$(now_utc)" "${from}" "${to}" "${msg}" >> "${inbox}"
    }
    lock_do "${inbox}.lock" append_inbox
    printf -- '- %s %s → %s: %s\n' "$(now_utc)" "${from}" "${to}" "${msg}" >> "${RUN_DIR}/logs/comms.md"

    if [ "${to}" = "human" ]; then
      echo "left in the human's inbox"
      exit 0
    fi
    # Capture fully, then take line 1: piping agent.sh into head would SIGPIPE it.
    state=$(head -n1 <<< "$("${SKILL_DIR}/scripts/agent.sh" check "${to}")")
    if [ "${state}" = "STATE=IDLE" ]; then
      send_to_agent "$(target_of "${to}")" \
        "New inbox message from ${from} — run ${SKILL_DIR}/scripts/message.sh read ${to} and act on it."
      echo "delivered + nudged (${to} idle)"
    else
      echo "delivered to inbox (${to} ${state} — no nudge, it reads at its next cycle)"
    fi
    ;;
  read)
    who=${1:?who required}
    inbox="${RUN_DIR}/comms/inbox/${who}.md"
    archive="${RUN_DIR}/comms/read/${who}.md"
    mkdir -p "${RUN_DIR}/comms/read"
    drain_inbox() {
      if [ -s "${inbox}" ]; then
        cat "${inbox}"
        {
          echo "## read at $(now_utc)"
          cat "${inbox}"
        } >> "${archive}"
        : > "${inbox}"
      else
        echo "(inbox empty)"
      fi
    }
    lock_do "${inbox}.lock" drain_inbox
    ;;
  log)
    who=${1:?who required}
    shift
    printf -- '- %s %s\n' "$(now_utc)" "$*" >> "${RUN_DIR}/logs/${who}.md"
    ;;
  *)
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
