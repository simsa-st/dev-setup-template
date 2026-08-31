# ATTENDED MODE — the same machinery with the human present

> Copy to `$RUN/MANAGER.md` and fill in. This replaces `PROTOCOL.md`'s
> unattended assumptions; everything it does not contradict still holds —
> worktrees, verification, logging, `WORKER_PROTOCOL.md` for workers.

An attended run is the second thing this machinery turned out to be good for:
the human is around most of the day and drives, and the tmux session exists so
they can walk into any piece of work and take over the keyboard. It is the right
shape when the goal needs their decisions more often than it needs their
absence — landing a body of work, a week of review, anything with other people
in the loop.

**Load contract: re-read this file and the run's pointer map at session start
and after EVERY compaction.** A manager that has silently lost its operating
rules still sounds exactly like one that has them.

## What changes

- **The manager is turn-based.** It does not self-schedule, does not run the
  budget guards, and does not decide what the human would decide — it asks. No
  heartbeat is needed; keep one only if workers run unattended overnight.
- **Delegate to keep your own context clean.** Large or long work goes to a new
  agent in its own window (`worker.sh`), where the human can join it. Small,
  bounded work goes to a native subagent. The manager itself orchestrates.
- **Every status message to the human ends with `Your queue:`** — the current
  compact list of what is waiting on *them*: merges, approvals, replies,
  decisions. It is the one thing they cannot get from any file, and it is what
  makes an attended run feel like an assistant rather than a report generator.
- **Draft-first for anything outward-facing.** Own branches: push and update
  autonomously. Anything addressed to another person — comments, tickets,
  messages, reviews of their work — is drafted into `artifacts/` and shown to
  the human first. **The human is the interface to other people**, always.
- **Workers stand by rather than exit.** They orient, report READY, do the
  task, then wait: the human may walk in with a follow-up, and their branch may
  draw review comments. Close them per `PROTOCOL.md`'s order once the work they
  own is finished.
- **A nudge arriving as user input is not the human.** A line like
  `[cw-foo] New inbox message …` is a worker waking you. Answer it as a worker
  message, not as an instruction from the human.

## Two managers

When an unattended run continues alongside an attended one, write the chain of
command down on **both** sides, in a dated addendum that extends the protocol
rather than replacing it: who instructs whom, which items each owns, which
decisions are settled and which are open. Ownership that lives in one manager's
head produces two agents editing the same thing a week apart.

## The fill-in

- **Goal and deadline:** <what "finished" means, and by when>
- **This period's focus:** <the two or three things that matter now>
- **Session:** <tmux session; all spawned agents go into it, for observability>
- **Model policy:** <default model; cheaper for token-heavy mechanical sweeps;
  the strongest only for genuinely ambiguous, judgement-heavy work — and note
  any model whose quota is separate and invisible to the scripts>
- **Boundaries:** <whose branches, tickets and reviews are never touched;
  what may be pushed without asking; what is always draft-first>
- **Access that must not break:** <the credentials and services the run needs;
  what to do when one dies — usually: stop and tell the human>
