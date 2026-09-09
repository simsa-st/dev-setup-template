---
name: proactive-run
description: Use when setting up, operating, recovering or closing a multi-agent run — a team of agents in tmux windows working one goal for days, either unattended while nobody is watching (vacation, a week off, spending the rest of a usage window) or attended with you driving. Covers the run layout, the operating protocol, budget pacing, the verification discipline that makes the output trustworthy, and the failure modes worth pre-empting. Works in both Claude Code and pi.
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

The same machinery runs a second shape, and runs it well: an **attended** run,
where you are around most of the day and drive, and the session exists so you
can walk into any piece of work and take the keyboard. Most of what follows
still applies; what changes is in `templates/ATTENDED.md`, and the difference
is worth respecting — the rules that make an unattended run work (never wait,
decide everything yourself, no questions) are actively wrong when the person
who owns the decision is sitting right there.

The scripts here are the machinery; `templates/` are the fill-in-the-blanks
documents. The rest of this file is what several such runs taught, condensed —
every line of it was bought with a failure.

## Shape

One run directory, dated like an experiment (`YYMMDD_short_name/`):

```text
PROTOCOL.md          binding rules for every agent — the one authority
WORKER_PROTOCOL.md   how a disposable worker behaves, read before its own prompt
STATUS.md            live dashboard, owned by the manager, rewritten each cycle
REPORT.md            living human-first report; what the human reads first
context/             distilled inputs, INDEX.md first; read-only during the run
prompts/             one prompt per role; workers get generated prompt files
comms/inbox/<who>.md inboxes, incl. one for the human; comms/read/ archives
logs/<who>.md        append-only event log, one line per external action
scratchpads/<who>.md compact state + ranked next actions, rewritten constantly
artifacts/           everything that should survive: results, evidence, plans
meta/                machine state: run.env, wakeup pids, heartbeat log,
                     target_<who> for an agent that has moved
```

Roles, each in a tmux window named after it — never addressed by index, since
a window whose command fails is destroyed and the rest renumber — and each a
first-level manager with its own workers:

| Role | Owns | Notes |
|---|---|---|
| `heartbeat` | the machinery, including its own | fresh cheap session per beat, killed and respawned; repairs, never does the work |
| `manager` | direction, tasking, pacing, STATUS.md, REPORT.md | orchestrates, does not implement; decides everything the human would |
| `tester` | behaviour as a *user* sees it | personas, real flows, real data; never reads code to excuse bad UX |
| `reviewer` | code/design quality and the path to production | owns the plan documents; biased toward deletion |
| `evaluator` | scores against the stated criteria on request | independent; flags work serving no criterion |
| `ideator` | a ranked, mechanism-verified backlog | proposes, never implements |
| workers (`cw-*`) | one task each | own git worktree, own prompt file, own result file; stands by when done, the spawner closes it |

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
   `scripts/run.sh start`. `RUN_AGENT_ARGS` defaults to
   `--dangerously-skip-permissions`, which is what unattended autonomy costs:
   every role runs unconfirmed for the length of the run, so point
   `RUN_WORK_DIR` at a repo whose blast radius you accept.

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
  working agent by accident — decide and type in the same breath, because a
  pane judged idle a minute ago may not be. Workers report only to their
  spawner. Keep one deliberate second tier (`send --wake`) for what must not
  wait a cycle: the one-tier rule assumes every recipient has a next cycle,
  and a turn-based manager or an agent whose wakeup was lost does not.
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
- **Prove the check could have failed, before trusting that it passed.** In one
  night five checks turned out to be *incapable* of failing: a pre-commit that
  reported clean four times without the linter that was failing, a schema too
  simple to express the bug, a rehearsal substrate with no redundancy to
  collapse, a selector that silently matched a different test, a skip that read
  as a pass. Print the skip count next to the pass count, and assert that a
  mutated input turns the check red.
- **A correct measurement plus a wrong inference is the commonest defect, and
  it does not feel like one.** "I found a mechanism that produces this" reads
  as an answer when it is only a candidate. The missing step is always the
  same: **construct the case where your mechanism and its likeliest rival
  disagree, and run that** — against the other party's actual inputs, not a
  case of your own. Across a night of cross-checking, no two agents ever
  disagreed about a measurement; they disagreed three times about what someone
  else had measured, and every underlying number was right.
- **Grepping to confirm something is *there* is safe — a hit cannot lie.
  Grepping to confirm it is *gone* must collapse whitespace first**, because a
  line break manufactures exactly the absence being claimed (and `grep -F --`
  for anything dash-prefixed).
- **An import failure has two ends.** Name the remover *and* the importer: a
  `git log -S` found the commit that deleted a symbol and a reviewer stopped
  there and ruled the failing tests obsolete — the tests never referenced it,
  and the real cause was two checkouts disagreeing. Whether the test file was
  even collected is part of the question.
- **A ref name is not a spelling of a commit.** Re-pin immediately before
  *reporting*, not only before starting; fifteen minutes of analysis was once
  reported against a head that had moved twice underneath it.
- Where a run keeps finding the same class of defect, say so as a **convention**
  ("every write says what it did"; "a real value must be distinguishable from
  an absent one") — a convention is adoptable, six fixes are just six fixes.
  You can then *measure* the adoption: when eight branches that had never
  shared a tree were merged, they needed one fix-commit to compose, against six
  for the previous train. Seams that are not there to find is what a convention
  taking hold looks like.

## Comparing two directions

A run that builds two implementations to choose between them is measuring, and
measurement has its own discipline — most of a night was lost relearning it.

- **Pre-register what the criteria mean, and that a tie is a valid result**,
  before either branch is built. Scoring invented afterwards will punish the
  track that turned out to be right, and everyone will be able to explain why.
- **Freeze one canonical base and put both tracks on it.** A base that moves
  under a comparison turns every difference into an argument. Check that the
  base does not already contain one track's architecture, or you have measured
  the base.
- **Run the null comparison first** — the same thing against itself. If A vs A
  shows a difference, the harness is what you are measuring.
- **Interleave the measurements**, never batch them: a shared machine's load is
  not constant, and A-then-B measures the afternoon.
- **Print a digest of the output next to every timing.** Otherwise a speedup
  can be paid for with quietly changed output — one was, and the digest is what
  caught the base silently rendering unfiltered results.
- Measure at the **real data shape**. A fixture is uniform and small, which is
  exactly where a per-item cost hides; a green suite is no evidence about speed.

## Integration

- **Prove nothing *moved*, not that nothing *conflicted*.** A clean rebase says
  git found no textual disagreement; it says nothing about whether your content
  survived. If the base fast-forwarded, `diff(old base → old head)` must be
  byte-identical to `diff(new base → new head)`. If the base was rewritten that
  comparison differs for uninteresting reasons — use per-commit `git patch-id`,
  which normalises them away.
- **Which comparisons survive being quoted**: a commit sha never (it embeds a
  timestamp); a tree sha only for identical content, and not for a conflicted
  `merge-tree`, whose files carry marker text; stage blobs always.
- **A loud conflict is a cheap one.** The expensive case is two changes that
  break each other with no file in common, so audit merge *order* by behaviour
  and not by counting conflicts.

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
  killing the window. Killing the window alone leaves the agent running: where
  the pane is a `docker exec`, one run accumulated 85 orphans and 33 GB of
  memory in six days. Kill **by a pid you recorded**, verified by process tree
  and working directory — never by a name pattern, which is how two separate
  sweeps killed live workers belonging to someone else. And never close a
  worker whose work is still open; park it on standby, because reviving it
  costs more than leaving it idle.
- **The machinery's own checks need checking, and they fail the same way:
  answering "yes" forever.** A liveness test that a zombie passes, a wakeup
  armed against a window that does not exist, a heartbeat that creates a window
  where the agent never starts — each one keeps every downstream thing looking
  healthy while the run quietly stops. Validate at arm time rather than at fire
  time, and give the watchdog a step that checks itself.
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
- **Test a handover by using it, not by reviewing it.** Spawn an agent whose
  instruction is to follow the documentation *literally* and never repair it in
  its head: run the commands as written, in the order written, and record every
  stuck point plus what a newcomer would plausibly do next. "Obviously you'd
  also need to…" is the finding, and reviewing cannot produce it — the
  reviewers already know the answers. It found a setup command that answered
  200 from the wrong backend, and a deployment section that would have taken
  the stack down.
- **Budget a real multi-hour close-out** from the start: re-open every item
  against live truth rather than trusting old summaries, exercise the basic
  flow once more, then write. The first run's shallow finalization changed
  conclusions when redone properly.
- A long-lived report that outlives its phase needs a **staleness banner and a
  known-stale list** at the top, naming what supersedes it. Two runs reopened
  a closed report, and a reader cannot tell which half is current.
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
| `message.sh send [--wake]\|read\|log` | inboxes and event logs; `--wake` types the nudge whatever the recipient is doing |
| `wakeup.sh <tag> <delay> <role> [text]` | self-nudge, replacing any pending wakeup with the same tag |
| `time_status.sh` | deadline, elapsed/remaining, usage vs linear target, machine load |
| `heartbeat.sh` | detached loop that respawns a fresh checker session every beat |

The usage figures come from the snapshot the agent's status line writes (see
`setup/agents/claude/statusline.sh`); without it every other line still works.
`wakeup.sh` needs `resume-agent` from this repo's `config/bin` on `PATH`.
`templates/` holds `PROTOCOL.md`, `WORKER_PROTOCOL.md`, `STATUS.md`,
`role_prompt.md` and `heartbeat_check.md` — `run.sh init` copies them into the
run — plus `ATTENDED.md` and `recovery.md`, which are copied in when needed.
