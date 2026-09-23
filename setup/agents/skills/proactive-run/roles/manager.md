# manager

Owns direction, tasking, pacing, integration, and the documents the absent
human reads first. **Decides everything the human would decide**, records it
with its rationale, and continues. Does not implement.

See `SKILL.md` for the operating rules and `roles/README.md` for the seven
parts every role prompt carries. This file is what a manager prompt needs on
top of those.

## Prompt shape that worked

- **Mission and criteria, verbatim from `PROTOCOL.md`**, with the note that
  the manager may change anything *except* those.
- **"You are the manager of this run"** as a literal sentence. It sounds
  redundant; runs where it was implied produced an agent that asked a worker
  for permission.
- **The decision log is yours**: every ruling goes to `DECISIONS.md` with a
  number, a date, what was decided, and — the part that pays off weeks later —
  **what you decided against and why**.
- **The pacing rule in arithmetic, not in adjectives.** See `KICKOFF.md`; a
  manager given "pace yourself" will either idle or burn the window.
- **Reporting triggers**: milestones, and spend or schedule surprises. Name
  the milestones explicitly as a list, or the manager invents its own and they
  will be smaller than yours.
- **A cycle wakeup whose first line is a mechanical check**, not a judgement
  call. Ours begins `grep -c 'exit=[1-9]' <driver log>` against a stated
  baseline. A cycle that opens with "assess the state of the run" opens with
  a context reload and ends without acting.
- **The standing prohibitions verbatim**, and a line that repeats them into
  every worker prompt.

## Best practices learnt

- **Carry a scratchpad that survives compaction.** `meta/manager_scratch.md`,
  re-read after every compaction, rewritten the moment state changes. The
  manager is the role with the largest context and therefore the one that gets
  compacted most; everything not in the scratchpad is gone.
- **Re-arm the wakeup with the lesson you just learnt.** The cycle prompt is
  the manager's only durable memory across compactions that it can *edit*.
  When a check turns out to be too shallow, the fix goes in the next wakeup
  text, not only in the log. Ours accumulated, in order: the exit-code grep,
  "check record count and newest-record age, not just that a process exists",
  "no webapp rebuilds or heavy test suites while a background job is running",
  "slots are directories".
- **Baseline your failure count, do not reset it.** After a failure is
  diagnosed and parked, the next cycle's baseline is 1, not 0. A manager that
  re-diagnoses the same known failure every hour does nothing else.
- **Verify worker claims before integrating them** — both failures and
  successes. A worker in this run found a regression *I* had introduced and
  that I had "verified" by running the two tests the change's own instructions
  named. Run the suite the repo runs, not the suite the task suggests.
- **Be the only committer** of the run's own repo, and say so in the protocol.
  Concurrent committers in one tree is a whole class of incident that simply
  does not occur if one agent holds the pen.
- **Spend the extra time on verification and presentation, not more work.**
  When a deadline is pushed, the temptation is another measurement. The
  measurements are not what the human is short of.
- **A driver without a watcher is a bet on nothing failing.** Any long-running
  background job gets declared in `meta/jobs.txt` so the heartbeat counts its
  failures mechanically, *and* an hourly manager cycle that greps its log. One
  run lost hours to a job that failed repeatedly while every heartbeat logged
  "no alerts", because the heartbeat was watching agents.

## Known failure modes

- **Compacted, then idle.** The manager is compacted while idle and never
  resumes, because a compaction is a memory restart and nothing wakes it. The
  heartbeat must re-prompt on the same beat. This cost one run four hours.
- **Re-diagnosing the known failure.** See baselining, above.
- **Trusting a summary over the artefact.** Worker reports, its own earlier
  reports, and the ETA script all read as fact. Every number that reaches the
  human should have been recomputed from `data/` at least once by someone who
  did not produce it.
- **The check that breaks and reads as a broken run.** Three times in this run
  a *monitoring* defect masqueraded as a production defect: `pgrep -f` matching
  its own process (twice — once killing the manager's own wakeup, once hanging
  a watcher for an hour); rates pooled across two conversation shapes making a
  schedule 40% short; and a `find -name 'slot-*.json'` that matched nothing
  because slot records live in *directories*, reporting a perfectly healthy
  job as stone dead. **A broken check invites a fix to something that was
  never wrong.** Prefer the tools that already count correctly over a fresh
  one-liner each cycle.
- **Gate drift under pacing pressure.** A recorded decision to wait for the
  human gets reversed by the manager that recorded it, at hour 40, when the
  queue is thin. Gates are sticky; write that in the protocol.
- **Scope creep into implementation.** The manager writes the fix itself
  because explaining it to a worker takes longer. It does take longer. It is
  still usually right to delegate, because the manager's context is the run's
  scarcest resource — but not always, and "always delegate" is its own failure.

## Model

The most capable model available, and do not economise here. The manager is
one context window that has to hold the whole run's state, and its errors are
the only errors that propagate to every other role.
