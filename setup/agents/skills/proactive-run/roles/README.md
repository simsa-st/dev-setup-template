# roles/ — the library of roles a proactive run can staff

`SKILL.md` is the authority: the run layout, the operating rules, budget
pacing, the verification discipline and the failure modes belong there and are
not repeated here. This directory answers the next question down — **for this
particular role, what does its prompt have to say, what did we learn about
running it, and how does it fail?**

Read `SKILL.md` first, then `KICKOFF.md` (the ordered checklist for standing a
run up), then the two or three role files you are actually staffing.

| File | Role | Staff it when |
|---|---|---|
| `manager.md` | direction, tasking, pacing, integration, commits | always — a run without one drifts |
| `heartbeat.md` | the machinery, including its own | always, at any size |
| `worker.md` | one task, disposable, own window | always — this is where the work happens |
| `presenter.md` | the report and the webapp as products | when a human will read the output more than once |
| `researcher.md` | methodology: what a number means and what it supports | when the run produces measurements |
| `reviewer.md` | code/design quality, deletion bias, the path to production | when the run writes code that should survive it |
| `tester.md` | the product as a *user* meets it | when there is something a person operates |
| `ideator.md` | a ranked, mechanism-verified backlog | when the space of what to try is larger than the time |
| `attacker.md` | adversarial generation against real targets | when the goal is "find the failure modes", not "build the thing" |

**Scale down freely.** A small run is manager + heartbeat + workers, and
nothing here says otherwise. Every role you add is a context window to keep
warm, an inbox to service and a way for the run to disagree with itself. The
question is never "which roles exist?" but **"which role owns a decision that
would otherwise go unmade?"** — if the manager can make it, do not staff it.

## The shape every role prompt shares

Each file below gives its own prompt outline, but all of them carry these
seven parts, and a prompt missing one of them has failed in a run already:

1. **Who you are and what you own** — one paragraph, and an explicit list of
   what you do *not* own. Ownership overlaps are how two agents edit one file.
2. **Where the authority is** — `PROTOCOL.md` binds you; your prompt does not
   override it. Name the sections that bind hardest (external actions,
   decisions, budget).
3. **The first action on every restart** — scratchpad → inbox → time status,
   in that order, before anything else. Write the literal commands.
4. **The cycle** — what you do each time you wake, in order, ending with
   "re-arm your wakeup". A role without a cycle stops after one turn.
5. **What counts as evidence** for the claims this role makes. This is the
   part that differs most per role and matters most.
6. **Reporting triggers** — what makes you message the manager (or the human)
   *now* versus at the next milestone. Absent this, roles either spam or go
   silent for a day.
7. **The standing prohibitions** — verbatim, not paraphrased, and repeated in
   every worker prompt. A prohibition summarised is a prohibition negotiated.

## The one rule that produced this directory

**Verify claims; never trust summaries** — including the summaries in these
files. Where a role file says "this worked", it means it worked in a run whose
transcript exists. Your run is not that run.
