# Opt-in activity breadcrumbs

`activity-log add --category work|personal --source prompt --summary 'project · short goal'`
appends a timestamped anchor to a private, append-only machine spool at
`~/.local/state/activity-log/events.jsonl`. `--source manual` and optional
`--url` add deliberate anchors. Do not put prompt text, credentials or inferred
durations in the summary. The category must be explicit; never infer personal
from the current directory. To ask agents to record a short summary on each
human prompt, set `ACTIVITY_LOG_CATEGORY` in this instantiation's profile and
run its shell/agent setup. Agent instructions are **not** input hooks: the
recorded time is when the agent runs the command, not the exact keypress time.
Agent-to-agent messages start `[agent]` and are not human activity.

On a full-mode Mac with a configured category, `./setup/install.sh --only
sessions` installs a launchd job that runs `activity-log sync` every 15
minutes (and once when it wakes). The machine list comes from this
instantiation's `setup/config/ssh/hosts.toml`, not an AWS API. SSH has a
five-second connect timeout, a 15-second overall limit, and transfers only
bytes after the last committed cursor (at most 4 MiB per pull). It never
starts machines. Install the script on remotes with `--only shell`. A layer-mode
setup must not install a job into the base setup's launchd namespace; its
owner must explicitly arrange a separate scheduler, state directory and
machine inventory if it wants its own sync.

`activity-log staged --after 0` yields `{seq, event}` JSONL from a private
SQLite store. A separate vault-owning process should deduplicate event IDs
and advance its `seq` only after durable insertion into the right note. The
source spool is never deleted by sync. The CLI does not touch any vault and
does not ship external service fetchers. Each service integration needs its own
permissions, paging and durable incremental cursor. Calendar events are only
scheduled anchors, not proof of attendance; metadata from other services must
not be treated as time worked.
