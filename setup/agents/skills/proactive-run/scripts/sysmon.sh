#!/usr/bin/env bash
# System monitor for a run on Linux or macOS: a detached loop
# (started by run.sh start, pid in meta/sysmon.pid) that every interval
# appends one line to meta/sysmon.log, rewrites meta/sysmon.json with the
# latest reading, and on a breach appends to logs/sysmon_alerts.md and drops a
# file-only message in the manager's inbox (at most one per 30 min).
#
#   sysmon.sh            run the loop (foreground; run.sh detaches it)
#   sysmon.sh once       one reading, printed, no loop
#
# Thresholds: RUN_MIN_MEM_AVAIL_MB (default 1500), load1 > 2 x cores,
# RUN_MIN_DISK_FREE_GB (default 5). Interval RUN_SYSMON_INTERVAL_S (default 120).
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

interval=${RUN_SYSMON_INTERVAL_S:-120}
min_mem=${RUN_MIN_MEM_AVAIL_MB:-1500}
min_disk=${RUN_MIN_DISK_FREE_GB:-5}
cores=$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo 1)
last_alert=0

reading() {
  local load mem_avail swap_used disk_free agents
  load=$(load_1m)
  if [ -r /proc/meminfo ]; then
    mem_avail=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
    swap_used=$(awk '/SwapTotal/ {t=$2} /SwapFree/ {f=$2} END {printf "%d", (t-f)/1024}' /proc/meminfo)
  else
    # macOS vm_stat reports pages; free + inactive + speculative are reclaimable.
    mem_avail=$(vm_stat | awk '/page size of/ {for(i=1;i<=NF;i++) if($i=="of") size=$(i+1)} /Pages free:|Pages inactive:|Pages speculative:/ {gsub("[.]","",$NF); pages+=$NF} END {printf "%d", pages*size/1048576}')
    swap_used=$(sysctl -n vm.swapusage | awk '{for(i=1;i<=NF;i++) if($i=="used") {n=$(i+2); if(n ~ /G$/) {sub(/G$/,"",n); n*=1024} else sub(/M$/,"",n); printf "%d",n}}')
  fi
  disk_free=$(df -Pk "${RUN_DIR}" | tail -n1 | awk '{printf "%d", $4/1048576}')
  agents=$(pgrep -f "^(${RUN_AGENT_BIN}|node .*claude|${RUN_PI_BIN}|node .*pi-coding-agent)( |$)" 2> /dev/null | wc -l | tr -d ' ')
  printf '%s load1=%s mem_avail_mb=%s swap_used_mb=%s disk_free_gb=%s agent_procs=%s' \
    "$(now_utc)" "${load}" "${mem_avail}" "${swap_used}" "${disk_free}" "${agents}"
  jq -n --arg t "$(now_utc)" --argjson load "${load}" --argjson mem "${mem_avail}" \
    --argjson swap "${swap_used}" --argjson disk "${disk_free}" --argjson agents "${agents}" --argjson cores "${cores}" \
    '{captured_at:$t, load1:$load, mem_avail_mb:$mem, swap_used_mb:$swap, disk_free_gb:$disk, agent_procs:$agents, cores:$cores}' \
    > "${RUN_DIR}/meta/sysmon.json.tmp" && mv "${RUN_DIR}/meta/sysmon.json.tmp" "${RUN_DIR}/meta/sysmon.json"
  # Breach test; the alert text names the biggest consumers so the manager can act.
  local breach=""
  [ "${mem_avail}" -lt "${min_mem}" ] && breach+="memory available ${mem_avail} MB < ${min_mem} MB; "
  awk -v l="${load}" -v c="${cores}" 'BEGIN{exit !(l > 2*c)}' && breach+="load1 ${load} > 2x${cores} cores; "
  [ "${disk_free}" -lt "${min_disk}" ] && breach+="disk free ${disk_free} GB < ${min_disk} GB; "
  if [ -n "${breach}" ]; then
    printf ' ALERT %s' "${breach}"
    local now top
    now=$(date +%s)
    if [ $((now - last_alert)) -ge 1800 ]; then
      last_alert=${now}
      top=$(ps -eo pid,rss,pcpu,comm | sort -k2nr | head -n 5 | awk '{printf "%s(%s,%dMB,%s%%) ", $4, $1, $2/1024, $3}')
      printf -- '- %s %s top: %s\n' "$(now_utc)" "${breach}" "${top}" >> "${RUN_DIR}/logs/sysmon_alerts.md"
      "${SKILL_DIR}/scripts/message.sh" send sysmon manager "RESOURCE ALERT: ${breach}top: ${top}— start no new workers until it clears; consider stopping idle ones." > /dev/null 2>&1 || true
    fi
  fi
}

if [ "${1:-}" = once ]; then
  reading; echo; exit 0
fi
end=$(epoch_of "${RUN_DEADLINE_UTC}")
while [ "$(date -u +%s)" -lt $((end + 7200)) ]; do
  reading >> "${RUN_DIR}/meta/sysmon.log"; echo >> "${RUN_DIR}/meta/sysmon.log"
  sleep "${interval}"
done
