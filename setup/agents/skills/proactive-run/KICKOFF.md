# KICKOFF — the checklist for standing a proactive run up

`SKILL.md` is the authority on what a proactive run *is* and how it operates;
`roles/` is the per-role library. This file is the ordered list of things to do
before the first agent starts, plus the two things most often got wrong
afterwards: **pacing** and **the live report**.

Work top to bottom. Every item below exists because skipping it cost a run
hours, and the cheapest hour to spend is this one.

---

## 1. Plumbing — verify at kickoff, never at the deadline

Each of these is a command whose *output* you read, not a box you tick.

- [ ] **The push path works, if the project authorizes pushes.** On a disposable
      branch under the project's review rules, make a test commit and push it,
      then `git ls-remote` to confirm the remote head moved. Do not bypass PR
      gates or publish a public repo just to test credentials. "Commit
      succeeded" is not evidence the run can deliver anything.
- [ ] **Credentials are fresh, and you know when they expire.** Re-source
      immediately before every write batch; never cache across days. Tokens
      rotating mid-run is normal, not an incident.
- [ ] **Models are pinned by full id** in `run.env`, one role per scarce quota.
      An unpinned model silently becomes a different model, and this run can
      prove one changed underneath a measurement.
- [ ] **The scripts run from the run directory**: `time_status.sh`,
      `message.sh send`/`read`, `wakeup.sh`, `agent.sh check <role>`. Run each
      once by hand.
- [ ] **A wakeup actually fires.** Arm one for 60 seconds against a real window
      and watch it land. Validate at arm time; a wakeup armed against a window
      that does not exist fails silently an hour later.
- [ ] **The deliverable folder can be committed.** Run the repo's pre-commit
      hooks on a trivial change now, not at hour 40. Find out today that the
      linter, the large-file check and the e-mail check all pass.
- [ ] **Shell prompts are disabled.** `DISABLE_AUTO_UPDATE=true` in the tmux
      *session environment* so worker windows inherit it, and
      `DISABLE_AUTOUPDATER=1` in `RUN_AGENT_ENV`. A framework update prompt held
      one run's heartbeat for hours; an agent self-update ended a worker.
- [ ] **`IS_SANDBOX=1`** so the bypass-permissions dialog never appears — a
      dialog draws the same cursor as an empty prompt, and a nudge's Enter has
      killed a manager before its first turn.
- [ ] **The ports you will occupy are listed** in the protocol, and each is
      free. Address services by container name or a run-prefixed alias, never a
      bare shared DNS alias.
- [ ] **`sysmon.sh` is running** and its thresholds match the machine.
- [ ] **Blast radius accepted.** `RUN_AGENT_ARGS` defaults to
      `--dangerously-skip-permissions`; point `RUN_WORK_DIR` at a repo whose
      worst case you can live with.
- [ ] **`meta/jobs.txt` exists** — even empty — and the manager knows to add
      every background job to it. See §4.
- [ ] **The window command works both ways.** `RUN_WINDOW_CMD` is used bare
      (`worker.sh`: `new-window … "$RUN_WINDOW_CMD"`) *and* with `-ic '<cmd>'`
      appended (`heartbeat.sh`). A group re-entry like `sg docker -c zsh`
      takes neither form; wrap it in an argv-quoting shim, and remember that
      bash's `printf '%q ' "$@"` prints `''` for zero arguments (zsh then runs
      a file named `''` and the window closes at once). Open one window each
      way and watch it stay up. One run's heartbeat checker never ran for three
      hours because of the `-ic` form, and the fix then broke every new worker
      window because of the bare form.
- [ ] **The heartbeat's own beats succeed.** `tail meta/heartbeat.log` after
      the first beat: `BEAT_FAILED` lines mean the checker never started. A
      heartbeat that only logs its own failure is silent; make sure a failed
      beat reaches the manager's inbox.
- [ ] **A worker in a fresh cwd starts.** A never-trusted directory (a new
      worktree) stops Claude Code on the folder-trust dialog and then the
      external-imports dialog, and the start prompt is never delivered. Accept
      both and re-send the start line with `tmux-say`, or pre-trust the
      worktree before spawning.
- [ ] **Shared-clone commits.** When another run commits the same clone, stage
      and commit in one step with an explicit file list
      (`git commit -- <files>`); never leave files staged (their commit sweeps
      them), and never `git commit -- <dir>` (it takes every modified tracked
      file under the directory, including workers' half-edited scripts).
      Pre-commit hooks that auto-fix (end-of-file, ruff format) abort the
      commit: re-add and commit again.
- [ ] **Any external per-call paid service is either metered or not called.**
      A proxied LLM key, a paid search/data API — before anything programmatic
      makes the first call, know the approved spend cap and have a script that
      snapshots spend against it (see `RUN_EXTERNAL_SPEND_SNAPSHOT` in
      `run.env` and the matching block in `time_status.sh`). No snapshot means
      no metering, and no metering means that service does not get called —
      an agent must never authorise going over a cap; only a human can raise
      one, in writing, in `run.env`.

## 2. `meta/run.env` — the fields that matter

`run.sh init` writes the file; these are the ones worth thinking about rather
than accepting:

| Field | Why it bites |
|---|---|
| `RUN_NAME`, `RUN_SESSION` | the run gets its **own** tmux session; never the one a human works in |
| `TMUX_SOCKET` | a private socket — from outside a pane every command needs `-S` |
| `RUN_WORK_DIR` | the blast radius, given skip-permissions |
| `RUN_WINDOW_CMD` | the shell; where framework prompts come from |
| `RUN_AGENT_ENV` | `IS_SANDBOX=1 DISABLE_AUTOUPDATER=1` — both non-optional |
| `RUN_ROLES` | `name:model`, pinned by full id; keep in sync with `PROTOCOL.md` |
| `RUN_DEADLINE_UTC` | what `time_status.sh` counts down to; `STATUS=OVER` means finalize |
| `RUN_QUOTA_RESET_UTC` | the long window's reset; the linear target is re-derived from it |
| `RUN_BUDGET_GOAL_PERCENT` (+`_AFTER_RESET`) | the long-window target before and after a mid-run reset |
| `RUN_BUDGET_BASELINE_PERCENT` | what was already spent when the run started — without it the target is wrong all run |
| `RUN_SHORT_WINDOW_MAX_PERCENT` | the hard ceiling on the 5-hour window |
| `RUN_HEARTBEAT_INTERVAL_S` | 7200 worked; shorter is mostly cost |
| `RUN_ALLOW_CREDITS` | **policy, not prompt.** Default is decline-and-wait; a human can reverse it for a phase, and then it belongs here |
| `RUN_*_SNAPSHOT` | where each meter's cached reading lives — report builders must read these, never issue a fresh paid probe |
| `RUN_EXTERNAL_SPEND_SNAPSHOT`, `RUN_EXTERNAL_SPEND_CAP_USD` | snapshot + cap for any metered external per-call service; empty means unmetered, and unmetered means that service must not be called |
| `RUN_MIN_MEM_AVAIL_MB`, `RUN_MIN_DISK_FREE_GB` | sysmon thresholds for the actual box |
| `RUN_START_UTC` | written at start; elapsed/remaining come from it |

Programmatic LLM traffic that isn't one agent's own conversation (bulk pipeline
calls, automated judges) goes through a metered key with a tag, **never**
through an agent's subscription — otherwise the run cannot say what it spent.

## 3. Pacing — the exact rule, in arithmetic

Utilization is a **bad primary objective**: aimed at directly it either idles
under target or manufactures churn. Aimed at as a *floor*, with a
pre-authorised backlog and named spend categories, it works.

Read `time_status.sh`, never a UI bar. Apply the subscription rules independently
for Claude and pi: the Codex line has the same 5h/7d reset and target fields.
An unavailable or stale reading is not spare capacity; restore the meter before
scheduling that CLI. Three meters, three rules:

**Short (5-hour) window — a reserve proportional to time remaining.**

```
reserve_percent = RESERVE_RATE × hours_until_short_window_reset
allowed_percent = 100 − reserve_percent
```

with `RESERVE_RATE = 10` as this run applies it — i.e. **keep 5% per remaining
half-hour**: 5 h left → keep ≥ 50% unused; 2 h left → keep ≥ 20%; 30 min left →
keep ≥ 5%. Above the allowance: **stop starting anything** — no workers, no
read-outs, no heavy builds — coordination only. The rate is the one dial worth
tuning per run: a lower rate spends more of the window and leaves less room for
a long task to overrun its end.

**Restart hysteresis — 10 points.** Once stopped for breaching the reserve, do
not start again until unused headroom is at least `reserve + 10` points (2 h
left → resume only at ≥ 30% unused). Without hysteresis the run flaps on the
boundary, starting and abandoning work.

**Long (7-day) window — linear target.** Target = a straight line to
`RUN_BUDGET_GOAL_PERCENT` by the reset, re-derived whenever a window resets
mid-run. Above the line: coordination only. Below it by a lot: **launch more
substantial delegated work** — being far under target is a finding, not a
comfort.

**Credits.** Default: never accept a "continue on extra usage / credits"
dialog; decline it, log it, and schedule a wakeup for the reset. Reversible by
the human for a phase, via `RUN_ALLOW_CREDITS=1` in `run.env` — never by an
agent under pacing pressure.

**Second CLI / second subscription.** A role or worker spelled
`pi/<provider>/<model>` runs on the other subscription with its own quota.
Apply the same short-window reserve, long-window target and reset guard to
Codex; switching CLIs does not reset either meter. Limit concurrent workers
by measured headroom; two can exhaust a shared 5h window mid-task. Size each
task to fit comfortably in what remains. Claude extra-usage dollars are reported only
when available; Pi's credit balance has unknown monetary units.

**Any other per-call paid service.** Same rule as the two subscriptions, in
miniature: an approved cap, a snapshot the run can read (never a fresh paid
probe), and a stop that a human — not the pacing pressure of the moment —
authorises past. No snapshot means no calls, full stop.

**What the heartbeat enforces.** All of the above, every beat, as an **inbox
alert to the manager — not a silent stop**. Plus, mechanically in bash and
independent of any agent's judgement: the background-job failure count and
liveness from `meta/jobs.txt`, waking the manager on a change.

**The machine is a budget too.** On a small box (4 cores, 16 GB): at most ~8
role windows, ~4 concurrent workers, ~2 heavy processes. Prefer heavy fan-outs
when load is low.

## 4. Background jobs — `meta/jobs.txt`

One line per job: `<name> <pgrep-pattern> <log> <failure-regex> <finished-regex>`.

`heartbeat.sh` counts failures and liveness from this file every beat in plain
bash and wakes the manager when the count changes. This exists because a run
lost most of its background jobs over several hours while every beat reported
"no alerts" — **agent liveness is not run health**. The manager additionally
greps the job's log at the top of its own cycle, against a **stated
baseline**, so a known and handled failure does not get re-diagnosed hourly.

Two traps, both paid for:

- **Anchor every `pgrep -f` pattern on the invocation** (`'^bash .*/run\.sh$'`,
  `'python3? -m pkg\.module'`) and filter your own pid (`| grep -vx "$$"`).
  `pgrep -f` matches any process that merely *mentions* the pattern — including
  the watcher itself, a wakeup whose prompt text names the script, and a
  monitor loop that greps for it. This cost one dead driver hour and one killed
  wakeup.
- **The finished regex must match the runner's real last line.** A job runner
  that ends its log with `=== <name> done exit=0` never matches a regex
  written for `[job] … exit=0`, so every clean finish raised a JOB ALERT.
  Copy the last line of a finished log into the regex, and test both regexes
  against a real log before registering the job.
- **The failure regex must not match content.** Line-anchor it
  (`^Traceback \(most recent`): a judge job that dumps its prompts or spans to
  stdout quotes the rubric, and the rubric may contain the word you grep for.
- **List a job only when it starts** (or comment it `#not-started-yet`): a
  listed job with no log alerts every beat. And a pattern anchored on `^env`
  never matches — `env` execs its command.
- **Count the job's real progress unit**, not a proxy. Records, not processes;
  and check the *newest record's age*, not merely that a process exists. A slow
  job and a wedged job look identical from a process list.

## 5. The live report loop — what made it work

Owned by the presenter (`roles/presenter.md`); this is the shape, for a run
that wants progress visible as it happens with no restarts and no manual
wiring.

- **The site is static.** `python3 -m http.server -d dist` in its own window.
  Therefore **a JSON file in `dist/` is already the endpoint** — this is the
  whole trick, and it removes the backend, the wiring and the restart.
- **Split the producer from the presentation, and make the file a contract.**
  A loop (`--loop 60`) recomputes `dist/<thing>.json` beside the live job,
  **read-only** over the data directory, written **atomically** (`tmp` +
  `os.replace`) so a poller never sees half a table. The page renders that file
  and computes nothing. If the card needs a field the producer does not emit,
  the producer is where it is added.
- **The page re-renders itself in place** from the same file on a timer — no
  reload, no framework, no request that is not same-origin.
- **Slim, findings-first, details one click away.** The finding in a sentence,
  above the apparatus; every run document rendered to its own page with the
  same styling, so links work over `http://` *and* `file://`.
- **No statistic is computed in the browser** beyond `k/n` as a percentage with
  k and n printed beside it. Intervals come down the producer.
- **Render checks that could fail.** Run the live page *and* a copy with
  polling removed in one pass, so the check cannot pass against a dead poller;
  assert a mutated input turns it red; check desktop and mobile; block HTTP(S)
  inside the check so a hidden CDN dependency fails there rather than in front
  of the human.
- **The report builder reads cached meters only.** A status script that issues
  a paid probe means the report is spending the budget it reports on.
- **Do not rebuild into `dist/` while a measurement is running.** A build can be
  heavy enough to perturb what is being measured.

## 6. Before you start the agents

- [ ] Mission and two or three **explicitly balanced** criteria in `PROTOCOL.md`.
- [ ] Context distilled into `context/` with an `INDEX.md`.
- [ ] A **deep, ranked backlog** and the gate decisions made **in writing**,
      including the ones you would rather defer. The dominant failure of a first
      run is a queue that drains into "needs the human".
- [ ] Named acceptable spend categories, so surplus budget has somewhere honest
      to go.
- [ ] The standing prohibitions written **verbatim**, in a form that can be
      pasted into every worker prompt without summarising.
- [ ] The milestones the manager reports on, listed explicitly.
- [ ] `roles/` read for each role you are staffing.
