---
description: Find drift between the original request, the design docs, the rules and the code.
---

Review, for the work in progress:

- **(p)** the initial prompt / request,
- **(d)** all design docs, including READMEs and plans,
- **(r)** the rules (skills, CLAUDE.md, contributing docs),
- **(c)** the code.

List every discrepancy between them in a numbered table, and for each row
recommend which side you believe is correct. Include cases where several paths
exist to do the same thing and arguably only one should.

Then stop and wait: I will correct you by row (`2d`, `5r`, ...).

After my corrections, fix the inconsistencies — using subagents where the work
is separable — and while you are in each file, remove stale content: completed
tasks whose design is already captured elsewhere, duplicate or superseded
sections, and fallbacks or dead code that nothing needs.
