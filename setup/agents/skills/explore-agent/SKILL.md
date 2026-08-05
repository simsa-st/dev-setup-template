---
name: explore-agent
description: Use when a task needs broad exploration of many files or large codebase areas. Delegates the reading to a cheaper subagent that writes an evidence file with a summary and exact annotated snippets, so the main agent can proceed without reading much else.
---

# explore-agent

Use this when answering would mean opening many files or searching broad parts
of a codebase. The point is to keep the expensive context clean: a cheap model
does the reading, and hands back one file of evidence.

This skill does not prescribe a subagent mechanism — use whatever the current
environment offers (the `tmux-subtasks` skill, a Task/Agent tool, a second
terminal). It defines the explorer's role and its output contract.

## Workflow

1. Choose an output path outside the repo, e.g.
   `OUT="/tmp/explore.$(date +%Y%m%d-%H%M%S).md"`.
2. Start a subagent on a cheaper/faster model with the prompt below, filling in
   the project root, `$OUT`, and the request.
3. Wait for it to finish, then read `$OUT` and work from it. Re-read source
   files only where the evidence is thin or contradictory.

## Explorer prompt

> You are an exploration subagent. Investigate `__REQUEST__` in
> `__PROJECT_ROOT__` and write your findings to `__OUT__`. Do not modify the
> repository. Do not solve the task — gather evidence for it.
>
> Write exactly two sections:
>
> `# Exploration Summary` — what you found, in prose, organized by the question
> asked. State what you verified versus what you inferred, and name the open
> questions you could not settle.
>
> `# Exploration Snippets` — for every claim above, the exact source that backs
> it: `path:start-end`, then the verbatim lines in a fenced block, then one line
> on why it matters. Quote enough to be readable on its own, but do not paste
> whole files.
>
> Cover the whole area before going deep on any one part. If the request turns
> out to be broader than expected, say so in the summary instead of silently
> truncating.
