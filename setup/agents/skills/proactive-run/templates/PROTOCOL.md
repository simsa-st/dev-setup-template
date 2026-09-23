# Protocol — <run name>

Binding rules for every agent in this run, main agents and workers alike. The
run directory below is `$RUN`; the scripts referred to are
`<skill-dir>/proactive-run/scripts/`.

- `$RUN` = `<absolute path to the run directory>`
- Working repo / environment: `<repo and branch the agents work in>`

## Mission

<One paragraph: what this run must produce, and what it is explicitly not
about. Be concrete about the artifact — branches, documents, a service — since
nobody will be around to reinterpret it.>

Evaluation criteria, to be balanced, not traded silently:

1. <criterion one — what "good" means, and how it is measured>
2. <criterion two — likewise>

Deliverables: <branch naming scheme>, `$RUN/REPORT.md` (living, human-first),
`$RUN/STATUS.md` (live dashboard), and the evidence behind every claim in
`$RUN/artifacts/`.

## Time and budget

- Deadline: **<UTC timestamp>**. Run `scripts/time_status.sh` before scheduling
  work; at `STATUS=OVER`, finalize and wind down.
- Usage target: ~<goal>% of the window by its end, paced roughly linearly.
  **Never exceed 100% of either subscription limit.** Decline any "continue
  on extra usage / credits" dialog and schedule a wakeup for the reset unless
  a human set `RUN_ALLOW_CREDITS=1` in `meta/run.env`.
- Guards apply to **each CLI separately**: either 5h window ≥85% → start no
  new workers on that CLI; ≥93% → coordination only; either 7d window ≥98% →
  stop that CLI until reset. Never pace on a stale or unavailable reading.
  Below target with ranked useful work waiting is a failure too: delegate to
  whichever CLI still has headroom.
- Other meters (`time_status.sh` prints all of them): Codex usage for pi
  agents (cap `RUN_CODEX_MAX_PERCENT`), spend on any external per-call service
  the run drives programmatically if one is metered (cap
  `RUN_EXTERNAL_SPEND_CAP_USD` — unmetered means the service must not be
  called at all), machine memory and load (`sysmon` alerts). A breached meter
  stops the spend that feeds it, not the run.
- Named spend categories (where surplus budget is meant to go): adversarial
  self-review against real systems, re-verification of worker claims, rebases
  and conflict reconciliation, strengthening tests, comparing two or three
  independent directions before picking one. Not churn, not speculative
  features nobody asked for.
- Heavy fan-outs when the machine is quiet (`time_status.sh` prints the load).
  Resource limits: <cores, memory, accelerators, what is off-limits>.
- Models: <which role runs on which model, and when to escalate>. Pin them
  explicitly; an ambiguous model name once selected the wrong provider.

## External actions

**Forbidden:** <everything the run must not touch — tickets, reviews,
comments, announcements, anything addressed to other people, any deletion of
remote state>.
**Allowed without asking:** <reads, fetches, pushing the run's own branches,
everything local>.
Log every external action with its URL or path via
`scripts/message.sh log <you> "<what>"`.

## Roles and communication

Session `<tmux session>`, fixed windows per `meta/run.env` (`RUN_ROLES`), and
workers in `cw-*` windows.

- **manager** — direction, tasking, pacing, integration, process fixes. Owns
  STATUS.md, REPORT.md and every decision the absent human would make. Does not
  implement, does not micromanage.
- **tester** — the product as a user experiences it: personas, real flows, real
  data. Reports anything worse than what exists today, loudly.
- **reviewer** — code and design quality, and the path to production. Owns the
  plan documents; biased toward deletion.
- **evaluator** — scores against the criteria on request; independent; flags
  work that serves neither criterion.
- **workers** — one task each, own worktree, own prompt and result file.

Comms: `scripts/message.sh send <from> <to> "<text>"`, read yours at every
cycle start with `scripts/message.sh read <you>`. Add `--wake` only for what
must not wait a cycle — a hard blocker, DONE/FAILED, a finding that changes
what someone else is doing right now; it types a nudge whatever the recipient
is doing. Main agents talk through the manager; workers report only to their
spawner. Messages for the human go to `comms/inbox/human.md` — nobody reads
them until they are back.

## Discipline

- **Never wait for the user.** No questions, no forms. Decide, record the
  decision and its rationale, continue. Genuinely blocked: park it, message the
  manager, take the next ranked item.
- **Scratchpad first.** Own and continually rewrite `scratchpads/<you>.md`
  (compact state + ranked next actions) — before going idle, before risky work,
  before and after compaction. On any restart: scratchpad → inbox →
  `time_status.sh`, in that order, before anything else.
- **Compact** when a work block ends and the scratchpad is current.
- **Verify claims, never trust summaries** — your workers' and your own. Check
  against real systems and real data, not mocks. A status code, a green suite,
  and a success message are not evidence. Read back what actually happened.
- **One git worktree per concurrent code-writing worker.** Never two agents in
  one checkout. Never rewrite history on a branch another worker is adding to.
  Verify pushes with `git ls-remote`.
- **A ref name is not a spelling of a commit.** Re-pin the head immediately
  before *reporting*, not only before starting: on a branch this many agents
  are pushing to, a pin is good for about as long as the check takes.
- **Whenever the trunk absorbs work, re-read every parallel branch's backlog
  against it.** Value computed against a trunk that no longer exists is
  phantom work — two agents once proposed building what had already landed.
- **Name the instance.** "I queried the service" is not a provenance: two
  backends answered on one port and the empty one produced figures that
  reached a handover document as measured fact. Every measured claim says
  which instance, which checkout, which database produced it.
- **Kill only by a pid you recorded**, and verify it by process tree and
  working directory first. Two separate sweeps that matched process *names*
  killed live workers belonging to someone else. If you killed, restarted or
  reconfigured anything shared, say so unprompted, even when nothing broke.
- **Gates are sticky.** A recorded decision to wait for the human may not be
  reversed by an agent, and pacing pressure is never grounds to reverse it.
- **Wakeups**: agents cannot wake themselves. Before ending a turn that expects
  future work: `scripts/wakeup.sh <tag> <delay> <you> "<text>"`.
- **Never type into a running agent's window**; use the message scripts.
- Re-source credentials immediately before every batch of authenticated writes.
- **Close a worker in this order**: collect its results, exit the agent
  itself, verify the process is gone, and only then kill the window. Killing
  the window alone leaves the agent running — one run accumulated 85 orphans
  and 33 GB of memory that way. Never close a worker whose work is still open;
  park it on standby instead.

## "Done" is not a state

While `time_status.sh` says RUNNING and budget remains, "finished / complete /
curated" is forbidden as a resting state. Closing an arc means opening the next
one: deeper testing, adversarial passes, a competing direction, harder plans,
better evidence. The cycle question is never "is there work left?" but "which
next arc is worth most?". Standby is legitimate only in the final hours, or on
an explicit stop.

## End of run

At `STATUS=OVER` or an explicit stop: finalize REPORT.md and STATUS.md, push
the branches, commit the run folder, log `run finished`, cancel wakeups, all
agents idle. Budget hours for this, not minutes: re-open each item against live
truth instead of trusting old summaries.
