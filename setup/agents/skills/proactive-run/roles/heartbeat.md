# heartbeat

Owns the machinery — **including its own**. Repairs; never does the run's
actual work, never starts project work of its own. A fresh, cheap, short-lived
session per beat, killed and respawned, because a long-lived watchdog acquires
exactly the failure it is meant to catch.

`templates/heartbeat_check.md` is the prompt; `scripts/heartbeat.sh` is the
loop. See `SKILL.md` → "Failure modes to pre-empt", which is largely a list of
things the heartbeat exists to notice.

## Prompt shape that worked

`templates/heartbeat_check.md`, essentially unchanged. Its virtues, in case
you are tempted to rewrite it:

- **Numbered, ordered, and under five minutes.** A heartbeat that thinks is a
  heartbeat that takes twenty minutes and costs more than the roles it watches.
- **"The pane is the truth, `STATE=` is a heuristic"**, with both ways to
  misread a pane written out: the input line renders *below* the working area
  (so a busy agent looks idle), and busy means the **elapsed timer** is running,
  not any particular spinner word (the word is randomised).
- **Capture the pane once more immediately before typing into it.** The gap
  between deciding a pane is idle and typing into it is where this goes wrong.
- **One summary line per beat**, logged, in a fixed format including
  `jobs=<failures>/<started> running=<y|n>`.
- **Step 4 checks the heartbeat itself.** Beats landing today; `BEAT_FAILED`
  lines; and whether the wakeup it relies on is actually armed.

## Best practices learnt

- **Split mechanical from judgement.** `heartbeat.sh` is plain bash and counts
  job failures and liveness every beat from `meta/jobs.txt`
  (`<name> <pgrep-pattern> <log> <failure-regex> <finished-regex>`), waking the
  manager on a *change*. The agent beat does the judging. The bash half cannot
  be talked out of a count, and the count is the half that mattered.
- **Agent liveness is not run health.** Every role can be alive, idle and
  correct while the job the run exists to produce fails repeatedly. This is the
  single most valuable thing the heartbeat learnt: watch the *output*, not the
  agents.
- **A compaction is followed by a wake-up on the same beat.** "Compacted —
  re-read your scratchpad and continue" is not optional politeness; without it
  the compacted agent sits.
- **Armed means `proc_alive`, never `kill -0`.** A fired wakeup leaves a zombie
  that `kill -0` reports as alive, so the test says "a cycle is coming" forever.
  One run stranded its manager behind ten such pids, every one passing.
- **Validate at arm time, not at fire time.** A wakeup armed against a window
  that does not exist fails silently in an hour's time, when nobody is looking.
- **Answer the known dialogs, log them, and treat the credits dialog as a
  policy question.** Default: decline and schedule a wakeup for the reset.
  Ours was later reversed by the human for a specific phase — which is exactly
  why it belongs in `run.env` (`RUN_ALLOW_CREDITS`) and not in the prompt.

## Known failure modes

- **The loop that is alive and doing nothing.** It creates a window, the agent
  never comes up, and it logs one failure an hour into a file nobody reads.
  `BEAT_FAILED` plus a manager that greps `meta/heartbeat.log` is the answer.
- **The interactive shell that stops before the command.** oh-my-zsh's "Would
  you like to update? [Y/n]" held a heartbeat window for hours. Launch with
  `DISABLE_AUTO_UPDATE=true` and set it in the tmux session environment so
  worker windows inherit it.
- **The agent CLI's own updater.** "Update installed · Restart to update" over
  an empty prompt, and no more work. `DISABLE_AUTOUPDATER=1` in `RUN_AGENT_ENV`.
- **Checking only what is easy to check.** Roles are easy; jobs are not. A beat
  that reports `all roles idle, no alerts` while the background job is dead is
  worse than no beat, because it is *evidence of health*.
- **Nudging a dialog.** A select dialog draws the same cursor as an empty
  prompt; a nudge's Enter confirmed "No, exit" and killed a manager before its
  first turn. Nothing types into a pane classified `DIALOG`.
- **Doing the work.** A heartbeat that starts fixing the actual problem is a
  second manager with no context and no mandate. Repair the machinery, wake the
  owner, stop.

## Model

The cheapest model that can follow a numbered checklist and read a tmux pane.
It runs every couple of hours for the length of the run, and it is the one role
where capability buys almost nothing — the checklist carries the intelligence.
