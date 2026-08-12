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
pid_file="${RUN_DIR}/meta/wakeup_${tag}.pid"

if [ -f "${pid_file}" ]; then
  old=$(cat "${pid_file}")
  if kill -0 "${old}" 2> /dev/null; then
    kill -- -"${old}" 2> /dev/null || kill "${old}" 2> /dev/null || true
  fi
fi

nohup setsid resume-agent "${delay}" "${target}" "${text}" \
  >> "${RUN_DIR}/meta/wakeup_${tag}.log" 2>&1 &
echo $! > "${pid_file}"
echo "wakeup '${tag}' scheduled in ${delay} for ${target} (pid $(cat "${pid_file}"))"
