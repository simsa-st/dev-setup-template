#!/usr/bin/env bash
# Schedule a delayed nudge to an agent's window, replacing any still-pending
# wakeup with the same tag. Agents cannot wake themselves: before ending a turn
# that expects future work, an agent schedules its own next cycle here.
#
#   wakeup.sh <tag> <delay> <role-or-window> [text...]
#   wakeup.sh manager-cycle 1h manager "Cycle: read inbox, check workers, continue."
#
# Re-scheduling the same tag every cycle is the intended use. `resume-agent`
# (from this repo's config/bin) does the waiting and the submit protocol.
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

tag=${1:?tag required}
delay=${2:?delay required (seconds or 1h30m)}
role=${3:?role or window required}
shift 3
text=${*:-continue}
target=$(target_of "${role}")

# Refuse to arm against a window that does not exist. A wakeup reports its bad
# target only when it fires, so without this check a typo or a renamed window
# costs the hours between arming and the silence that follows.
if ! window_exists "${target}"; then
  echo "wakeup: no window '${role}' in ${RUN_SESSION} — refusing to arm '${tag}'" >&2
  echo "  windows: $(window_list)" >&2
  exit 1
fi

pid_file="${RUN_DIR}/meta/wakeup_${tag}.pid"
if [ -f "${pid_file}" ] && proc_alive "$(cat "${pid_file}")"; then
  old=$(cat "${pid_file}")
  kill -- -"${old}" 2> /dev/null || kill "${old}" 2> /dev/null || true
fi

nohup setsid resume-agent "${delay}" "${target}" "${text}" \
  >> "${RUN_DIR}/meta/wakeup_${tag}.log" 2>&1 &
echo $! > "${pid_file}"
echo "wakeup '${tag}' scheduled in ${delay} for ${target} (pid $(cat "${pid_file}"))"

# What is armed after this call — the only honest answer to "does that agent
# have a cycle coming?", and the check the heartbeat repeats every beat.
for f in "${RUN_DIR}"/meta/wakeup_*.pid; do
  [ -f "${f}" ] && proc_alive "$(cat "${f}")" && echo "  pending: $(basename "${f}" .pid)"
done
