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
# command (a plain shell locally, docker exec in a containerised setup). Launch
# the agent with NO prompt argument and send the prompt afterwards, exactly as a
# worker is started: an inline prompt has to survive this loop's quoting and
# then the shell's, and when it does not the window comes up empty, the UI never
# appears, and the loop logs one failure an hour while doing nothing at all.
inner="cd ${RUN_WORK_DIR} && $(agent_launch_cmd "${model}")"
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
  # Kill and create, never `respawn-window -k`: respawn reuses the pane, and an
  # agent launched through `docker exec -it` never comes up under a reused one.
  # Create against the SESSION with -n, since `-t session:name` means "at the
  # position of the window called name" and so cannot create it.
  tmx kill-window -t "${target}" 2> /dev/null
  if ! tmx new-window -d -t "${RUN_SESSION}" -n heartbeat "${cmd}" 2> /dev/null; then
    hb_log "BEAT FAILED: could not create ${target} — the loop is alive and doing nothing"
  elif wait_for_agent_ui "${target}" 90; then
    send_to_agent "${target}" "Read ${RUN_DIR}/prompts/heartbeat_check.md and follow it."
    hb_log "beat: checker prompted"
  else
    hb_log "BEAT FAILED: checker UI did not appear — check RUN_WINDOW_CMD and the agent binary"
  fi

  remaining=$((end + grace - $(date -u +%s)))
  if [ "${remaining}" -lt "${interval}" ]; then
    sleep "$([ "${remaining}" -gt 0 ] && echo "${remaining}" || echo 1)"
  else
    sleep "${interval}"
  fi
done
