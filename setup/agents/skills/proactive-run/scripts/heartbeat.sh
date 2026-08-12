#!/usr/bin/env bash
# Dead-man heartbeat: plain bash, detached by run.sh start, outliving every
# agent. Each beat KILLS whatever is in the heartbeat window and respawns a
# fresh cheap session on prompts/heartbeat_check.md — so the checker never
# grows a conversation, and a wedged checker is replaced rather than nudged.
# This loop never types into an agent's window itself; the checker does that.
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

interval=${RUN_HEARTBEAT_INTERVAL_S}
end=$(epoch_of "${RUN_DEADLINE_UTC}")
grace=$((2 * 3600))
target=$(target_of heartbeat)
model=$(role_model heartbeat)

hb_log() { echo "$(now_utc) $*"; }

# Respawn runs on the tmux host side, so wrap the agent in the run's window
# command (a plain shell locally, docker exec in a containerised setup).
inner="cd ${RUN_WORK_DIR} && $(agent_launch_cmd "${model}") \"Read ${RUN_DIR}/prompts/heartbeat_check.md and follow it.\""
cmd="${RUN_WINDOW_CMD} -ic '${inner}'"

hb_log "heartbeat loop started (every ${interval}s until ${RUN_DEADLINE_UTC})"
while true; do
  now=$(date -u +%s)
  if [ "${now}" -ge $((end + grace)) ]; then
    hb_log "deadline + grace reached, exiting"
    break
  fi
  if ! tmx has-session -t "${RUN_SESSION}" 2> /dev/null; then
    hb_log "session ${RUN_SESSION} is gone — cannot respawn, exiting"
    break
  fi

  hb_log "beat: respawning the checker in ${target}"
  tmx respawn-window -k -t "${target}" "${cmd}" 2> /dev/null ||
    hb_log "respawn-window failed (retrying next beat)"
  wait_for_agent_ui "${target}" 90 || hb_log "checker UI did not appear"

  remaining=$((end + grace - $(date -u +%s)))
  if [ "${remaining}" -lt "${interval}" ]; then
    sleep "$([ "${remaining}" -gt 0 ] && echo "${remaining}" || echo 1)"
  else
    sleep "${interval}"
  fi
done
