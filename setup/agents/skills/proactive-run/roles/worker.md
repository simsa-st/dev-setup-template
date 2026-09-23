# worker (`cw-*`)

One task, one prompt file, one result file, one window, disposable. Workers are
where the run's work actually happens; every other role exists to aim them.

`templates/WORKER_PROTOCOL.md` is how a worker behaves; its own prompt file is
what the task is; `SKILL.md` binds both. Keep those three separate — a run that
inlines the protocol into each prompt cannot fix the protocol.

## Prompt shape that worked

A worker prompt is a **contract**, and every field below was added because its
absence cost something:

1. **The task, in one paragraph**, and then the acceptance criterion stated as
   *behaviour on a real artefact* — not "tests pass".
2. **The paths you own**, disjoint from every other live worker. For foreign
   repos, the worktree and the branch, by name.
3. **What you may not touch**, verbatim from the protocol. Not paraphrased.
4. **What evidence your result must contain**: which command, run where, with
   what output. "Report that it works" gets you a report that it works.
5. **Where the result goes** — `artifacts/worker_<you>_result.md` — and that
   nothing important may live only in the worker's conversation.
6. **How to report**: file message for routine, `--wake` for DONE/FAILED/hard
   blocker, one log line per meaningful step.
7. **Stand by when done. Your spawner closes your window.**

Plus a pre-DONE checklist the worker runs over its own work. Ours
(`prompts/WORKER_CHECKLIST.md`) is eight items and catches the class of bug
that cost this run more time than every other class combined: **an instrument
that reports success exactly where it is blind.** Its first item is a table of
every place a value meaning *"I do not know"* was recorded as a precise,
reassuring number — a `cost_usd: 0.0` for an unpriced call, an unsupported
capability marked "pass", a `usage: {0,0,0}` — one row per instance, each in a
different module, each written by someone who had got it right elsewhere.

## Best practices learnt

- **One git worktree per concurrent code-writing worker.** Always. Watch for
  editable installs that silently shadow a worktree, so the worker tests the
  wrong checkout; the symptom is regenerated files showing no diff.
- **Ask for the refusal.** The best worker result this run produced was a
  *refusal*: I asked for a competence range, and the worker replied that the
  generator computes no statistic of its own and a range would have to be
  invented. Prompts should say, in as many words, **"if the task as specified
  is wrong, say so and do the correct thing instead"**. Workers that cannot
  refuse will fabricate.
- **A worker reviewing the spawner's work finds things the spawner cannot.**
  The same worker caught a test I had broken and believed I had verified.
  Budget one worker per phase whose job is to check the manager.
- **Make one assertion fail on purpose, once, per test file**, and say in the
  result that you did it. A test that cannot fail proves nothing — this run
  nearly published a verdict whose check was incapable of going red.
- **Workers finish without telling anyone.** A moved branch head or a written
  result file is the real completion signal; do not wait for the message.
- **Never close a worker whose work is still open.** Park it on standby.
  Reviving it costs more than leaving it idle.

## Known failure modes

- **Silent success.** The dominant one. See the checklist above.
- **Reporting a pass from a hand-built fixture**, or a failure from a stack
  missing a sibling's changes. Verify both directions.
- **Scope expansion.** "Finding more to do is a message to your spawner, not a
  licence" belongs in the protocol verbatim; without it a worker asked for one
  fix returns with a refactor.
- **Two workers, one file.** Disjoint paths, enforced by the spawner at prompt
  time, because the workers cannot see each other.
- **Killed by a name pattern.** Two separate sweeps in past runs killed live
  workers belonging to someone else. Kill by a **pid you recorded**, verified
  by process tree and working directory, and only through the stop script.
- **The worker that reads its prompt and not the protocol.** Put the protocol
  read in step one of the prompt, with the path.

## Model

Match the model to the task, not to the role. Hard, well-specified engineering
(a harness implementation, a tricky debug, a proxy) rewards the strongest
model — or a second CLI on a separate quota, which is also how you spread load.
Mechanical, well-bounded work (fixture generation, a sweep, a render check)
runs fine on a cheap model and is where a run's budget is most easily saved.
Judgement-heavy or ill-specified work should not be delegated at all until it
is specified.
