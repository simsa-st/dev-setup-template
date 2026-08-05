---
name: tmux-subtasks
description: Use when work should be split into independent subtasks run by separate agent processes in tmux windows, whether parallel or sequential — especially to keep the parent agent's context small. Works with pi or Claude Code as the subagent CLI.
---

# tmux-subtasks

Runs subtasks as real agent processes in tmux windows. Two reasons to reach for
it: parallelism, and keeping bulky work (log trawling, wide refactors, review
passes) out of the parent's context. Each subtask gets its own conversation log
and its own result file, so a failed one can be inspected or resumed by hand.

Scripts live next to this file in `scripts/`.

## Workflow

1. Create a task directory:

```bash
TASK_DIR=$(~/.claude/skills/tmux-subtasks/scripts/create_task_dir.sh "short task summary")
```

It is created under `$TMPDIR`/`/tmp`, never inside the repo, and holds
`prompts/`, `results/`, and `progress.log`.

2. Split the work into focused subtasks with short slug names (`backend-review`,
   `test-fix`, `doc-pass`) — the names become tmux window names and filenames.

3. Start one agent per subtask:

```bash
scripts/start_subtask.sh "$TASK_DIR" backend-review "Inspect the backend path and summarize issues."
scripts/start_subtask.sh --model <cheap-model> "$TASK_DIR" doc-pass "Find outdated docs."
```

Options before the task dir: `--agent <cmd>` (default `$SUBTASK_AGENT`, else
`pi`), `--model <name>`, and repeated `--agent-arg <arg>` for anything else.
Match the model to the subtask: a cheap one for mechanical sweeps, a strong one
for design or debugging. When a subtask returns something unusable, the model
choice is the first thing to revisit.

4. Wait for completion:

```bash
scripts/watch_subtasks.sh "$TASK_DIR" 20 30 backend-review doc-pass
```

Arguments: task dir, poll interval (s), max polls, subtask names. Poll slowly
enough that you are not burning context on status checks, and no slower than the
work actually takes.

5. Read `$TASK_DIR/results/<name>.md`. Do not read the conversation JSONL unless
   a subtask failed and you need to see what it did.

## Contract given to each subagent

Every rendered prompt ends with the same contract, so results are uniform:

- write the answer to `results/<name>.md` — that file is the deliverable, not
  the chat output;
- append `STATUS: DONE|FAILED|BLOCKED` plus one line of context to
  `progress.log` when finishing;
- stay inside the stated scope; report scope problems instead of widening.

Windows for `DONE` subtasks are closed automatically; `FAILED`, `BLOCKED` and
crashed ones are left open for inspection.
