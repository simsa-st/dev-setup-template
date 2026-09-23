#!/usr/bin/env bash
# Offline run metering regression: bash scripts/test_external_spend.sh
set -euo pipefail
repo=$(cd -- "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT
"${repo}/setup/agents/skills/proactive-run/scripts/run.sh" init "${scratch}/run" > /dev/null
run="${scratch}/run"
deadline=$(date -u -d 'tomorrow' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+1d +%Y-%m-%dT%H:%M:%SZ)
# shellcheck disable=SC2016
printf '\nRUN_DEADLINE_UTC=%s\nRUN_CODEX_SNAPSHOT=%s/codex.json\nRUN_EXTERNAL_SPEND_SNAPSHOT=%s/spend.json\nRUN_EXTERNAL_SPEND_CAP_USD=10\n' \
  "${deadline}" "${scratch}" "${scratch}" >> "${run}/meta/run.env"
now=$(date +%s)
jq -n --argjson t "${now}" '{captured_at:$t,rate_limits:{five_hour:{used_percentage:0},seven_day:{used_percentage:0}}}' > "${scratch}/codex.json"
status() { RUN_DIR="${run}" "${repo}/setup/agents/skills/proactive-run/scripts/time_status.sh"; }
jq -n --argjson t "${now}" '{captured_at:$t,spend:3}' > "${scratch}/spend.json"
grep -q 'EXTERNAL_SPEND=OK.*SPEND_USD=3 CAP_USD=10' <<< "$(status)"
jq -n --argjson t "${now}" '{captured_at:$t,spend:10}' > "${scratch}/spend.json"
grep -q 'EXTERNAL_SPEND=STOP' <<< "$(status)"
jq -n --argjson t "$((now-1800))" '{captured_at:$t,spend:1}' > "${scratch}/spend.json"
grep -q 'EXTERNAL_SPEND=stale' <<< "$(status)"
printf 'not json\n' > "${scratch}/spend.json"
grep -q 'EXTERNAL_SPEND=unavailable' <<< "$(status)"
echo 'external spend status: ok'
