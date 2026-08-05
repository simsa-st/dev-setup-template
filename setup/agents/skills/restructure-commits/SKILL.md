---
name: restructure-commits
description: Use when asked to restructure, split, squash, reorder, or otherwise clean up commits in a feature branch so the branch is easy to review commit by commit. Works in both Claude Code and pi.
---

# restructure-commits

Goal: make the branch as easy as possible to review commit by commit.

## Commit principles

- Make commits as small as practical.
- Keep each commit self-contained: code, tests, config, parameters, migrations,
  docs, and usage should be introduced together when needed for that commit to
  work and make sense.
- Keep tests and implementation in the same commit.
- Introduce a parameter/config/API and use it in the same commit.
- Do not go ad absurdum: many tiny commits for related typo fixes or mechanical
  cleanups are usually worse than one clear cleanup commit.
- Breaking self-containment is acceptable when it significantly reduces commit
  size and the reason for the partial change is obvious.
- Put the "why" in the extended commit message. Prefer `docs/` when the branch
  already has or needs documentation for the change.

## Restructuring workflow

1. Check that the working directory is clean before starting.
2. Create a backup branch pointing at the original branch state.
3. Do not rebase onto the base branch unless explicitly asked; never mix an
   upstream rebase with commit restructuring.
4. Review `git log --stat` for the branch. Use the original messages and stats
   as context, especially where a later commit removes or fixes an earlier one.
   Do not cling to the original commit boundaries.
5. Squash all branch commits into one working-tree/index state.
6. Inspect the full branch diff and split it into logical commits following the
   principles above.
7. Verify the new commits one by one:
   - inspect each diff;
   - check that each commit is working and self-contained;
   - run the relevant hooks/tests for that commit when practical;
   - look for inconsistencies caused by splitting, such as a required change
     missing from a file that was only touched later;
   - decide whether a commit can be usefully split further without making
     review harder.
8. Use subagents/subtasks when helpful for per-commit review or further splitting.
9. Check that the final tree matches the backup branch. Report any intentional
   difference clearly.
10. If final adjustments are needed, fix them directly or with fixup commits,
    then autosquash.
