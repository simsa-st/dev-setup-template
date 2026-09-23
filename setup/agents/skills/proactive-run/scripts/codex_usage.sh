#!/usr/bin/env bash
# Snapshot the Codex (ChatGPT subscription) rate limits that pi's OAuth login
# is subject to, in the same shape as the Claude status-line snapshot, so
# time_status.sh can pace pi work the way it paces Claude work.
#
#   codex_usage.sh            refresh if the snapshot is older than 10 min
#   codex_usage.sh --force    refresh now
#
# Source: GET https://chatgpt.com/backend-api/wham/usage with the access token
# pi stores in ${PI_CODING_AGENT_DIR:-~/.pi/agent}/auth.json (never printed).
# primary_window = 5 h, secondary_window = 7 d.
# Writes RUN_CODEX_SNAPSHOT or this pi agent directory's ignored usage file.
# Separate agent directories must not share an account's quota snapshot.
set -uo pipefail
umask 077  # Account-specific snapshot under the ignored pi agent directory.
out=${RUN_CODEX_SNAPSHOT:-${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}/codex-usage.json}
max_age=600
if [ "${1:-}" != "--force" ] && [ -s "${out}" ]; then
  age=$(( $(date +%s) - $(jq -r '.captured_at // 0' "${out}") ))
  [ "${age}" -lt "${max_age}" ] && { cat "${out}"; exit 0; }
fi
python3 - "${out}" <<'PY'
import json, os, sys, time, urllib.request
out = sys.argv[1]
agent_dir = os.path.expanduser(os.environ.get("PI_CODING_AGENT_DIR", "~/.pi/agent"))
auth = json.load(open(os.path.join(agent_dir, "auth.json")))["openai-codex"]
req = urllib.request.Request(
    "https://chatgpt.com/backend-api/wham/usage",
    headers={"Authorization": "Bearer " + auth["access"],
             "ChatGPT-Account-Id": auth.get("accountId", ""),
             "User-Agent": "proactive-run codex_usage.sh"})
try:
    d = json.load(urllib.request.urlopen(req, timeout=30))
except Exception as e:  # keep the old snapshot rather than write garbage
    print(json.dumps({"error": str(e)[:200]}), file=sys.stderr); sys.exit(1)
rl = d.get("rate_limit") or {}
def win(k):
    w = rl.get(k) or {}
    return {"used_percentage": w.get("used_percent"), "resets_at": w.get("reset_at")}
snap = {"captured_at": int(time.time()), "model": "codex",
        "plan_type": d.get("plan_type"), "limit_reached": rl.get("limit_reached"),
        "rate_limits": {"five_hour": win("primary_window"), "seven_day": win("secondary_window")}}
# The API calls this a credit balance, not a USD amount; do not label it '$'.
credits = d.get("credits") or {}
if isinstance(credits.get("balance"), (int, float)) and not isinstance(credits["balance"], bool):
    snap["credit_balance"] = credits["balance"]
tmp = out + ".tmp"
json.dump(snap, open(tmp, "w")); os.replace(tmp, out)
print(json.dumps(snap))
PY
