# experiments/

One folder per experiment, named `YYMMDD_short_name` — dated so the folder
listing is a timeline, and never renamed afterwards, because links and notes
point at it.

An experiment folder is a self-contained record: what was tried, the scripts
that ran it, and enough of a runbook to repeat it months later. It is not
library code. When something graduates into a reusable tool, move it out.

## Rules

- **Copy, do not import.** Start from `_template/`, then crib from the two or
  three most recent experiments. Experiments are allowed to duplicate each
  other; coupling them means an old experiment breaks when a new one changes.
- **Dependencies are local.** A nontrivial experiment is its own uv project with
  its own `pyproject.toml`. Experiment-only dependencies never go in the root
  project.
- **`data/` and `screen_logs/` are gitignored.** Everything reproducible —
  downloads, generated datasets, model outputs, checkpoints — goes in `data/`.
  Long-running job output goes in `screen_logs/`. Commit neither.
- **Every experiment has a `README.md`** stating the question, how to rerun it,
  and what the answer turned out to be. Write the answer down when you get it;
  that is the part you will come back for.
- **Notebooks are committed as `.nb.py`** (jupytext percent format), not
  `.ipynb`, so diffs are readable and outputs stay out of git.

## Checks

Root `ruff` formats and lints everything, experiments included, so all this code
shares one style. Root `ty` skips experiment folders — an experiment should not
be blocked by a type error in a throwaway script — but a changed experiment that
has a `pyproject.toml` is type-checked in its own environment by
`scripts/check_affected_experiments_ty.sh` in pre-commit. Tests are manual: put
shared tests in the root `tests/`, experiment tests in the experiment's own
`tests/`.

## Finishing one

Archive rather than delete: move finished experiments you no longer touch into
`archive/` once the folder list gets long. The pre-commit config excludes it, so
old code does not have to keep passing today's linter.
