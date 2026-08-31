#!/usr/bin/env bash
# Inboxes and event logs — the run's whole communication system.
#
#   message.sh send [--wake] <from> <to> <text...>
#   message.sh read <who>                   print and archive <who>'s inbox
#   message.sh log  <who> <text...>         append one timestamped line to <who>'s log
#
# `to` is a role, a worker window (cw-<name>), or `human` (file only — nobody is
# watching). Every message lands in the inbox file; the difference is when the
# recipient finds out:
#
#   default   file-only, plus a nudge if the recipient happens to be idle. The
#             right choice for almost everything: progress, results, questions
#             that can wait a cycle. A busy recipient is never typed into.
#   --wake    also types a nudge whatever the recipient is doing, so it lands as
#             their next input. For what must not wait a cycle — a hard blocker,
#             DONE/FAILED, a finding the human needs relayed now. Use sparingly;
#             a turn-based recipient that self-schedules nothing has no other
#             way to hear you, and that is what this is for.
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

action=${1:?usage: message.sh send|read|log ...}
shift

case "${action}" in
  send)
    wake=0
    if [ "${1:-}" = "--wake" ]; then
      wake=1
      shift
    fi
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

    target=$(target_of "${to}")
    nudge="[${from}] New inbox message — run ${SKILL_DIR}/scripts/message.sh read ${to} and act on it."
    if [ "${wake}" = 1 ]; then
      if send_to_agent_now "${target}" "${nudge}"; then
        echo "delivered + woke ${to} (${target})"
      else
        echo "delivered to inbox (could not reach ${target})"
      fi
      exit 0
    fi

    state=$(pane_state "${target}")
    if [ "${state}" = "IDLE" ]; then
      send_to_agent "${target}" "${nudge}" && echo "delivered + nudged (${to} idle)"
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
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
