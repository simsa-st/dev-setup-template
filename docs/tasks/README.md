# docs/tasks/

Short design notes for changes big enough that the work should be thought
through before it starts — a new install step, a reworked clipboard path, a
migration across machines.

- One file per task, named `YYMMDD_short_name.md`.
- Write the problem, the options considered, and the decision. The options you
  rejected are the part worth keeping; the code shows the one you took.
- Move a note to `done/` when the change ships. Keep it: it is the answer to
  "why is it like this?" a year later.
- Delete a note instead if the design ended up captured somewhere better (a
  README, a skill) — two sources of truth is worse than none.

These are also the natural handover unit for a coding agent: point it at the
note, not at a paragraph of chat.
