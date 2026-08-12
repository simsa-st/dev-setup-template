---
name: proactive-run
description: Use when setting up, operating, or closing an unattended multi-agent run — a team of agents working a goal for days while nobody is watching (vacation, a week off, or spending the rest of a usage window). Covers the run layout, the operating protocol, budget pacing, the verification discipline that makes unattended output trustworthy, and the failure modes worth pre-empting. Works in both Claude Code and pi.
---

# proactive-run

A **proactive run** is a fixed-length, unattended push at one goal: several
long-lived agents in tmux windows, disposable workers under them, a heartbeat
that repairs the machinery, and a deadline. Nobody answers questions while it
runs. Everything it produces has to be legible and verifiable afterwards.

Worth it when there is a real goal that survives days without you, a usage
window that would otherwise expire, and a deliverable that is not a single
irreversible action. Not worth it for one well-scoped task (use
`tmux-subtasks`) or for anything whose value depends on a decision only the
absent human can make.

The scripts here are the machinery; `templates/` are the fill-in-the-blanks
documents. The rest of this file is what two such runs taught, condensed.

## Shape

One run directory, dated like an experiment (`YYMMDD_short_name/`):

```text
PROTOCOL.md          binding rules for every agent — the one authority
STATUS.md            live dashboard, owned by the manager, rewritten each cycle
REPORT.md            living human-first report; what the human reads first
context/             distilled inputs, INDEX.md first; read-only during the run
prompts/             one prompt per role; workers get generated prompt files
comms/inbox/<who>.md inboxes, incl. one for the human; comms/read/ archives
logs/<who>.md        append-only event log, one line per external action
scratchpads/<who>.md compact state + ranked next actions, rewritten constantly
artifacts/           everything that should survive: results, evidence, plans
meta/                machine state: run.env, wakeup pids, heartbeat log
```

Roles, each in a fixed tmux window, each a first-level manager with its own
workers:

| Role | Owns | Notes |
|---|---|---|
| `heartbeat` | window 0 | fresh cheap session per beat, killed and respawned; repairs machinery only, never does the work |
| `manager` | direction, tasking, pacing, STATUS.md, REPORT.md | orchestrates, does not implement; decides everything the human would |
| `tester` | behaviour as a *user* sees it | personas, real flows, real data; never reads code to excuse bad UX |
| `reviewer` | code/design quality and the path to production | owns the plan documents; biased toward deletion |
| `evaluator` | scores against the stated criteria on request | independent; flags work serving no criterion |
| `ideator` | a ranked, mechanism-verified backlog | proposes, never implements |
| workers (`cw-*`) | one task each | own git worktree, own prompt file, own result file |

Scale down freely — a small run is manager + one critic + workers. Keep the
heartbeat at any size; it is what makes the run survive the night.

## Setting one up

1. **State the mission and the criteria** (two or three, explicitly balanced)
   in `PROTOCOL.md`. Everything else is negotiable by the manager; this is not.
2. **Distil the context** into `context/` with an `INDEX.md`, before starting
   agents. More is fine; unindexed is not.
3. **Pre-authorize a deep backlog and make the gate decisions up front.** The
   dominant failure of the first run was a queue that drained into "needs the
   human". Decide the open questions in writing now, including the ones you
   would rather defer.
4. **Name acceptable spend categories** (adversarial self-review against real
   systems, re-verification of worker claims, rebases, test strengthening,
   comparing several directions) so surplus budget has somewhere honest to go.
5. **Verify the plumbing at kickoff**, not at the deadline: the push path
   works, credentials are fresh, the models are pinned explicitly, the
   scratchpad/inbox scripts run, the deliverable folder can be committed.
6. `scripts/run.sh init <dir>` scaffolds the layout and `meta/run.env`; fill
   in the deadline, session, models, and window command, then
   `scripts/run.sh start`.

## Operating rules

These are prompt-level rules for every agent — they are in
`templates/PROTOCOL.md` because each one was bought with a failure.

- **Never wait for the human.** No questions, no forms. Decide, record the
  decision and its rationale, continue. Genuinely blocked work gets parked in
  a file and swapped for the next ranked item.
- **Scratchpad-first recovery.** Every agent owns and continually rewrites its
  scratchpad: compact state plus ranked next actions. Rewrite it before going
  idle, before risky work, and before compaction; on any restart read
  scratchpad → inbox → time status, in that order, before anything else.
- **One line per event in your own log**, with the URL or path. This is what
  makes the run auditable when it is over.
- **Messages go to files, nudges go to idle windows only.** Never type into a
  working agent. Workers report only to their spawner.
- **Agents cannot wake themselves.** Before ending a turn that expects future
  work, schedule a wakeup, deduplicated by tag.
- **Compact when a work block ends and the scratchpad is current.** Long stale
  context is the most expensive thing the run buys.
- **Gates are sticky.** A recorded decision to wait for the human may not be
  reversed by the agent that recorded it — least of all under pacing pressure.
  A near-miss here is why an independent boundary-enforcer is worth its cost.
- **"Finished" is a forbidden steady state** while the deadline and the budget
  both allow more. Closing an arc means opening the next one: deeper testing,
  adversarial passes, harder plans, another direction compared. The cycle
  question is never "is there work left?" but "which next arc is worth most?"

## Budget and pacing

Utilization is a **bad primary objective** — aimed at directly it either idles
under target or manufactures churn. Aimed at as a floor, with a pre-authorized
backlog and named spend categories, it works.

- Pace linearly toward a target percentage of the window, and re-derive the
  target when a limit window resets mid-run. Run the status script before
  scheduling work; treat it, not a UI bar, as the source of truth.
- Hard guards, enforced by the manager and the heartbeat: near the short-window
  limit, start no new workers; very near it, coordination only; near the long
  window limit, stop until reset. **Never accept a "continue on extra
  usage/credits" dialog** — decline it and schedule a wakeup for the reset.
- Different models may have separate quotas the scripts cannot see. Pin one
  role per scarce model, and treat the human's occasional readings as truth.
- Prefer heavy fan-outs when the machine is quiet (check load, prefer nights),
  and keep a per-run registry of the ports and stacks you occupy.

## Verification discipline

This is the part that decides whether unattended work is worth anything. Every
line below is a finding, not a principle.

- **A status code is not evidence.** Systems return success for non-answers: a
  misconfigured run reported SUCCESS while writing to a throwaway database; a
  200 came back with an empty result list and would have been reported as a
  pass. Read what actually came back, and **poll the observable — never sleep**.
- **Feed wrong input on a real system.** The worst defects of both runs were
  invisible to green unit suites, to a diff review, and to a happy-path
  click-through; they surfaced only under mistyped input against real
  backends. Mocks and in-memory fakes hid a data-loss bug for a week.
- **Verify worker claims — both failures and successes.** Workers report
  "dead code" from a stack missing a sibling's changes, and passes from
  hand-built fixtures. A moved branch head or a written result file is the real
  completion signal; workers routinely finish without notifying anyone.
- **Build the small fixture early.** Three times a defect argued about for
  hours narrowed in minutes under one synthetic fixture.
- **Assert the seam, not the halves.** The piece that joins two well-tested
  things is the piece nobody tests — the sharpest instance stayed green while
  the wiring between a tested decision function and a tested component was
  deleted.
- **A failing check earns the same scrutiny as a passing one** — false fails
  waste hours. Worse: distrust any check whose result is the answer you hoped
  for. A query that silently returned empty for every call read as "nothing
  varies here", a false pass that flattered the thing under test.
- **A self-authored control inherits the hypothesis's blind spot.** Three
  adversarial cases built from the model that produced the invariant all
  passed; one real-data run refuted it immediately. When a prediction is about
  how real data behaves, the right verdict is ACCEPT-PENDING-RERUN.
- **Before asserting an invariant about a budget or any conserved resource,
  enumerate everything that spends it** and justify the enumeration — that is
  the step reasoning alone never checks.
- **A success message is not evidence of the state it claims.** Read the state
  back (`git status --porcelain`, the rendered screen, the row in the database).
- **A single grep form is not a complete map.** Verify removal scope by
  behaviour, and sweep callers by value shape as well as by symbol.
- Where a run keeps finding the same class of defect, say so as a **convention**
  ("every write says what it did"; "a real value must be distinguishable from
  an absent one") — a convention is adoptable, six fixes are just six fixes.

## Failure modes to pre-empt

- **Typing into agent TUIs**: send literal text, let paste detection settle,
  then a separate submit key. Named-Enter alone inserts a newline and the
  message sits unsent (this dominated one run's failures until fixed).
- **One git worktree per concurrent code-writing worker**, always. Watch for
  editable/linked installs that silently shadow a worktree, so a worker tests
  the wrong checkout (symptom: regenerated files show no diff).
- **Never squash by resetting to a moving target**; the upstream advances and
  the reverse of its new commits lands in your commit. Never run a
  history-rewriting worker concurrently with an add-commits worker on the same
  branch — and if a safety ref is claimed, verify it exists remotely.
- **Verify pushes** (`git ls-remote`) before believing "done".
- **Address services by container name or a run-prefixed alias**, never a bare
  shared DNS alias — two workers picking the same alias cost three
  investigations.
- **Kill only through the stop script**, which exits the agent cleanly before
  killing the window; a killed window leaves an orphan process. Never kill on
  a reported pid — verify by process tree and working directory. Make kill
  patterns not match the killing command itself.
- **Re-source credentials immediately before every write batch**; never cache
  them across days. Rotated tokens mid-run are normal.
- **Restart a service as a sequence, not a command**: kill, confirm the port is
  free, start separately, wait for a real response, verify exactly one process.
- Watch for runaway helper processes (filesystem-wide scans from tooling) and
  kill them on sight; they eat the machine the workers need.

## Deliverables and close-out

- The **report is human-first and living**, updated as things land, not written
  at the end. Lead with the most transferable finding, and record decisions
  with their rationale as they are made.
- An **interactive report** — a small local webapp that walks the human through
  variants, tradeoffs, decisions and screenshots — beats a long document, and
  is worth testing and iterating like a deliverable. Cross-check every commit
  reference it cites; stale references are the most common defect in it.
- **A test suite written as user instructions plus success criteria** (what to
  do, what counts as done, how many steps it should take) can be executed by
  cheap agents at every checkpoint. Requirements and user stories translate
  directly.
- **Budget a real multi-hour close-out** from the start: re-open every item
  against live truth rather than trusting old summaries, exercise the basic
  flow once more, then write. The first run's shallow finalization changed
  conclusions when redone properly.
- At the deadline: finalize the report and dashboard, push branches, commit the
  run folder, cancel wakeups, log the finish, all agents idle.

## Scripts

All read `meta/run.env`; set `RUN_DIR` or run them from inside the run
directory. Read the header of each for its arguments.

| Script | Purpose |
|---|---|
| `run.sh init\|start\|stop` | scaffold a run, bring up the session + manager + heartbeat, wind down |
| `agent.sh start\|restart\|check\|stop <role>` | fresh start, resume with context, classify state, clean exit |
| `worker.sh <name> <prompt-file> [cwd] [model] [spawner]` | disposable worker in its own window |
| `message.sh send\|read\|log` | inboxes and event logs |
| `wakeup.sh <tag> <delay> <role> [text]` | self-nudge, replacing any pending wakeup with the same tag |
| `time_status.sh` | deadline, elapsed/remaining, usage vs linear target, machine load |
| `heartbeat.sh` | detached loop that respawns a fresh checker session every beat |

The usage figures come from the snapshot the agent's status line writes (see
`setup/agents/claude/statusline.sh`); without it every other line still works.
`wakeup.sh` needs `resume-agent` from this repo's `config/bin` on `PATH`.
`templates/` holds `PROTOCOL.md`, `STATUS.md`, `role_prompt.md` and
`heartbeat_check.md` — `run.sh init` copies them into the run.
