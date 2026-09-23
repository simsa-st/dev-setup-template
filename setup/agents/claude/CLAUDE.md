# This machine

TODO(bootstrap): describe this box in three or four lines — what it is for,
where its own setup lives, and anything that happens to it without a human
present (unattended reboots for kernel updates, nightly jobs, a shared user).
Agents waste real time rediscovering that a session "crashed" overnight when in
fact the machine rebooted itself on schedule.

Sessions and tmux windows are saved every couple of minutes and restored
afterwards (`setup/lib/sessions.sh`), so a session that vanished overnight was
rebooted, not crashed.

# Working agreement

- When anything is unclear or ambiguous, **ask** rather than guess. Always.
- Lead with the answer. Concise, but not at the cost of readability.
- Calibrate confidence to what you actually verified; never state the unverified
  as fact.
- **End each reply with the queue of tasks waiting on me** — what only I can do
  (credentials, decisions, asking a colleague), kept apart from what is waiting
  on you. Re-derive it each turn; parked items belong in the project's own
  backlog file and surface only once that queue is empty or nearly so.
- Durable notes go in the project's files (an experiment's `README.md`, a docs
  page), never in one agent's private memory store — the other agent cannot
  read it. This file is the shared one: `~/.pi/agent/AGENTS.md` symlinks here.
- Prefer a named, reusable script in the repo over an inline one-liner when the
  thing is worth running twice.
- Choose models by task: use a cost-efficient model for routine or mechanical
  work and a stronger model when complexity or ambiguity warrants it. Reserve
  the highest-capability option for genuinely high-stakes decisions where an
  error would be costly.
- Before unattended work calls an externally billed service, establish who
  pays, the approved spend ceiling, a way to observe actual spend and a stop
  condition. If the meter is missing or stale, pause that work rather than
  infer that budget remains. Never accept overages without explicit approval.

# tmux

The server runs on a **private socket**, not the default one. Inside a pane bare
`tmux` works; from anywhere else add `-S ~/tmp-tmux-socket` (`TMUX_SOCKET` in
`setup/config/profile.env`), or the server looks like it does not exist.

    tmux ls                                                    # sessions
    tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}'
    tmux display-message -p '#{session_name}:#{window_index}'  # which am I?
    tmux capture-pane -p -t work:2 | tail -30                  # read a window

Windows are named after the conversation in them, so `list-windows -a` is the
map of who is doing what.

# Activity breadcrumbs (opt-in)

If this machine's setup has enabled `ACTIVITY_LOG_CATEGORY` (`work` or
`personal`), run `activity-log add --category "$ACTIVITY_LOG_CATEGORY"
--source prompt --summary '<project · few-word goal>'` immediately on each
human prompt. Log the agent's execution time, not an inferred duration. Never
include the prompt body or secrets. Skip `[agent]` messages, scheduled nudges
and uncertain provenance; ask if unclear. This is not a CLI input hook, so a
prompt not processed by the agent cannot be captured. If the command fails,
say so rather than claiming it was logged. An instantiation must deliberately
configure the category and any vault routing; never infer it from the cwd.

# Talking to an agent in another window

    tmux-say work:2 'take a look at the pacing table'

Every agent-originated prompt, including wake messages, starts `[agent]`.
`tmux-say` and proactive-run's sender add it automatically; other transports
must add it themselves. Human prompts must not use the marker. It is a
provenance convention, not authentication.

Use it rather than raw `send-keys`: it sends the text literally and the Enter as
a separate keystroke after a pause, both of which are needed and neither of
which fails loudly when skipped. Read the answer with `capture-pane`; the
session is still working while its footer shows `esc to interrupt`.

# Starting a Claude session

    cla <remote-control-name>

in the pane it should live in. The name is what the phone shows and what lets
the session be resumed into the same pane after a reboot; `claude-panes list`
shows the tracked ones. A long-lived session started as bare `claude` has no
name and will not come back.

# Secrets

Everything under `setup/config/secrets/` except the README and the `*.example`
files is gitignored and is a local secrets file: never reveal its contents, in
output or in a commit. `setup/config/secrets/README.md` says how secrets reach a
machine.

TODO(bootstrap): add whatever else every session on this machine should know
before its first tool call — where the repos are, which commands are expensive,
what must never run here.
