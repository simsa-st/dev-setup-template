---
description: Commit the current changes with a well-formed message.
---

Commit the current changes (all of them unless the request below narrows it).

Workflow:

1. Read `git status` and the full diff before deciding anything.
2. Group the changes into small self-contained commits — code with its tests,
   a parameter with its use — following the repo's existing message style
   (check `git log --oneline -20`).
3. Commit. Do not use `--no-verify` unless you have just run the hooks and are
   certain the remaining failures are unrelated to your changes.

Rules:

- Do not rewrite history or amend existing commits unless explicitly asked.
- Do not sweep in unrelated local changes; ask when ownership is unclear.
- Remove or ignore generated/temporary files instead of committing them.

Response style: concise. Give the commit hash(es), the message subject(s), and
the decisions you made — what you left out, and anything you had to fix.
