---
name: experiments
description: Use when working on dated experiments in this repo — creating an experiment folder, writing its scripts, handling its data, or committing the results. Works in both Claude Code and pi.
---

# experiments

Experiments live in `${DEV_REPO_DIR}/experiments/<YYMMDD_short_name>/`. Read
`experiments/README.md` for the full policy; this skill is the operating summary.

## Creating one

- Use the folder the user named, or create `experiments/{YYMMDD_short_name}/`.
- Copy `experiments/_template/` as the starting point, then look at the two or
  three most recent experiments and reuse their scripts — that is where the
  current way of running things lives.
- A nontrivial experiment is its own uv project: its own `pyproject.toml` with
  its runtime dependencies and a `README.md` runbook that states how to rerun
  it. Never add experiment-only dependencies to the repo root project.

## Data and logs

- Everything reproducible — downloads, generated datasets, checkpoints, exports
  — goes under the experiment's `data/`. Long-running job output goes to
  `screen_logs/`. Both are gitignored.
- Do not read files under `data/` unless explicitly asked; they can be huge.
  For `screen_logs/`, read the first or last few lines only.
- Before committing, check for accidentally staged large files
  (`git status --short --untracked-files=all`, `find . -size +1M`) and move them
  to `data/` instead of committing them.

## Checks

- Root `ruff` runs across the whole repo, experiments included.
- Root `ty` excludes experiment folders; changed experiments that have a
  `pyproject.toml` are type-checked in their own environment by
  `scripts/check_affected_experiments_ty.sh`.
- Pytest is not part of the experiment hook. Put shared tests in the root
  `tests/`, experiment-specific tests in the experiment's own `tests/`, and run
  them manually while developing.

## Committing

- Commit when the experiment is done or after a big coherent chunk of work;
  prefer focused commits over leaving finished work uncommitted.
- Message style: a short lowercase scope prefix — `experiment: {YYMMDD_name}`
  for a single experiment, otherwise `setup:`, `agents:`, `docs:`. Keep
  unrelated setup/agent/experiment changes in separate commits.
- After committing, try `git push origin main` from `${DEV_REPO_DIR}`. If the
  push fails (unavailable or non-clean upstream), say so rather than retrying.
