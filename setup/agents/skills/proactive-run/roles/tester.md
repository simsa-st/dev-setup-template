# tester

Owns behaviour **as a user meets it**: personas, real flows, real data, the
runbook followed literally. Never reads the code to excuse bad behaviour — if
it is confusing with the source open, it is broken with the source closed.

`SKILL.md` → "Verification discipline" and "Deliverables and close-out" are
this role's working text; `roles/README.md` has the common prompt shape.

## Prompt shape that worked

- **"Follow the documentation literally and never repair it in your head."**
  This single sentence is the role's whole value. Run the commands as written,
  in the order written, and record every stuck point plus what a newcomer would
  plausibly do next. **"Obviously you'd also need to…" is the finding.**
- **A persona and a goal, not a feature list.** "You are a bookkeeper who wants
  to know whether last month's invoices are right" produces findings; "test the
  invoice page" produces a checklist.
- **Success criteria stated as user outcomes, with a step budget.** "Done when
  you can state the answer, and it should take under ten steps." The step count
  is the usability metric; a task completed in forty steps passed and failed.
- **Explicit permission to declare the product wrong**, not the test.
- **Wrong input is part of the job, not an edge case.** Mistyped values, a stale
  link, the back button, an empty result.

## Best practices learnt

- **Test a handover by using it, not by reviewing it.** Reviewing cannot produce
  this finding — the reviewers already know the answers. Spawning an agent to
  follow our own setup documentation literally found a command that answered 200
  from the wrong backend, and a deployment section that would have taken the
  stack down.
- **Feed wrong input on a real system.** The worst defects of two runs were
  invisible to green unit suites, to a diff review and to a happy-path
  click-through; they surfaced only under mistyped input against real backends.
  Mocks and in-memory fakes hid a data-loss bug for a week.
- **A status code is not evidence.** Systems return success for non-answers: a
  misconfigured run reported SUCCESS while writing to a throwaway database; a
  200 came back with an empty result list and would have been reported as a
  pass. Read what came back. **Poll the observable — never sleep.**
- **A test suite written as user instructions plus success criteria** — what to
  do, what counts as done, how many steps — can be executed by cheap agents at
  every checkpoint. Requirements and user stories translate directly, and this
  is the cheapest recurring quality signal a run has.
- **Report the stuck point and the guess.** "I stopped here, and I would have
  tried X next" tells you both what is broken and what the docs implied.
- **Re-run the basic flow once more at close-out.** It is the cheapest check
  there is and it has changed a conclusion.

## Known failure modes

- **Reading the source to get unstuck**, and then reporting the flow as fine.
  The moment the tester understands the system, the role is spent — rotate the
  window or re-scope it.
- **Reporting the workaround instead of the defect.** "You have to set the flag
  first" is a finding, not a step.
- **Testing the build you were handed** rather than the one a user would get.
  Check the checkout, the install path and the version.
- **A green run on a fixture.** Fixtures are uniform and small, which is exactly
  where a per-item cost and an ordering bug hide.

## Model

A mid-tier model is right here, and arguably better than a strong one: the role
rewards literal-mindedness, and a model that is too good at inferring intent
will silently repair the documentation in its head — which is the one thing the
prompt forbids.
