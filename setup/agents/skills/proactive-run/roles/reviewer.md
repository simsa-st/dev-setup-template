# reviewer

Owns code and design quality and the path from "it ran once" to "it survives
the run ending". **Biased toward deletion.** Owns the plan documents, and any
standing guard the run must not breach.

`SKILL.md` carries the run-wide verification and integration discipline this
role enforces; `roles/README.md` has the seven parts every role prompt needs.

## Prompt shape that worked

- **The deletion bias, stated as an instruction**: "your default recommendation
  is to remove it". A reviewer without that instruction reviews for correctness
  and the codebase grows all run.
- **The guards you enforce, by name**, with the assertion that proves each one.
  Ours owned a hard constraint — the benchmark must be structurally incapable of
  reaching a real production system — and checked it on *every* code review, not
  once at the start.
- **Ownership of `artifacts/plans/`**, so "how this reaches production" is a
  document somebody maintains rather than a paragraph in a report.
- **Review the seam, not the halves** — say it in the prompt, because a diff
  review naturally reads each side.
- **Authority to block a merge, and the obligation to say what would unblock
  it.** A blocking review without a remedy is an argument.

## Best practices learnt

- **Assert the seam.** The piece that joins two well-tested things is the piece
  nobody tests. The sharpest instance in this run stayed green while the wiring
  between a tested decision function and a tested component was deleted
  outright.
- **A gate that fires only on the build path is not a gate on the import path.**
  Enumerate the ways in, not the ways you expect.
- **Grepping to confirm something is *there* is safe — a hit cannot lie.
  Grepping to confirm it is *gone* must collapse whitespace first**, because a
  line break manufactures exactly the absence being claimed. And `grep -F --`
  for anything dash-prefixed.
- **A single grep form is not a complete map.** Verify removal scope by
  behaviour; sweep callers by value shape as well as by symbol.
- **An import failure has two ends.** Name the remover *and* the importer. A
  `git log -S` found the commit that deleted a symbol and a reviewer stopped
  there and ruled the failing tests obsolete — the tests never referenced it,
  and the real cause was two checkouts disagreeing. Whether the test file was
  even collected is part of the question.
- **One fix does not settle a pattern that appears twice.** When the same defect
  shape shows up in two modules, the deliverable is a **convention** ("every
  write says what it did"; "a real value must be distinguishable from an absent
  one"), not two fixes. A convention is adoptable and *measurable*: when eight
  branches that had never shared a tree were merged, they needed one fix-commit
  to compose, against six for the previous train. Seams that are not there to
  find is what a convention taking hold looks like.
- **Two checks over the same paths can conflict**, and satisfying one breaks the
  other. Run both after either changes.
- **Prove nothing *moved*, not that nothing *conflicted*.** A clean rebase says
  git found no textual disagreement. If the base fast-forwarded,
  `diff(old base → old head)` must be byte-identical to
  `diff(new base → new head)`; if it was rewritten, compare per-commit
  `git patch-id`.
- **A ref name is not a spelling of a commit.** Re-pin immediately before
  *reporting*, not only before starting. Fifteen minutes of analysis was once
  reported against a head that had moved twice underneath it.

## Known failure modes

- **Reviewing the diff instead of the system.** Everything in the diff is
  correct and the system is broken. Ask what the change makes possible that was
  not possible before.
- **Approving because the tests are green.** Ask what would still pass if the
  thing were broken; that question has found more in this run than any other.
- **Stopping at the first sufficient explanation.** See the import-failure case
  above — the commonest reviewer error, and it always reads as thoroughness.
- **Accumulating plans nobody executes.** A plan document that has not changed
  in two days is either done or dead; say which.
- **Politeness about deletion.** The role exists to make the case unpopular
  with the author. If every review ends in "looks good with nits", it is not
  being run.

## Model

A strong model. Reviewing is the task where a cheaper model most reliably
produces plausible, well-formatted agreement.
