# YYMMDD_short_name

**Question:** what this experiment is trying to find out, in one or two lines.

**Answer:** fill this in when you have it — even a partial or negative result.
This is the line future-you reads.

## Setup

```bash
uv sync                 # this folder is its own uv project
cp .env.example .env    # if the experiment needs credentials
```

## Running

```bash
./run_task.sh baseline              # starts a detached run, logs to screen_logs/
./tail_running_screens.sh           # last line of every running job
tail -f screen_logs/baseline.txt    # follow one
```

## Layout

| Path | Contents |
|---|---|
| `run_task.sh` | launches one detached run; edit per experiment |
| `data/` | inputs and outputs, gitignored |
| `screen_logs/` | job logs, gitignored |
| `notebooks/` | analysis as `.nb.py` (jupytext percent format) |

## Log

Dated notes as the experiment goes — what was run, what came out, what changed.
