# Template porting ledger (copy into an instantiation)

Keep the filled-in copy **only in this instantiation** at `docs/porting-ledger.md`.
Do not put names, paths, commits, or other details of instantiations in the
public template. Keep a separate ledger in each instantiation; this is not a
registry of all copies.

The template and an instantiation have independent histories. A port is a
translation, not a merge: hashes cannot be compared by ancestry. Review both
directions separately. For each direction, list reviewed **source ranges** in
chronological order (`git log --reverse <previous>..<end>`). Every source
commit in a range must be accounted for by a mapping or a documented decision
(specific-only, already present, or deferred). A deferred item is still open:
keep it in the queue below until resolved. Do not mark a whole interval reviewed
just because its last commit was ported. If an earlier audit cannot establish a
continuous range, record only its verified mappings and leave the checkpoint
unknown.

## Reviewed ranges

| Direction | Source commits reviewed (exclusive start → inclusive end) | Date | Notes / outcome entries |
|---|---|---|---|
| instantiation → template | — | — | Not audited yet |
| template → instantiation | — | — | Not audited yet |

## Decisions and mappings

| Direction | Source commit(s) | Outcome (ported / already present / specific-only / deferred) | Target commit(s) | Note |
|---|---|---|---|---|
| — | — | — | — | — |

## Deferred / next review

- instantiation → template: review from the last verified range end (or audit history if none).
- template → instantiation: review from the last verified range end (or audit history if none).

When porting, update this ledger **in the instantiation** alongside its change.
If the target commit is not yet known, add it in the next ledger update; do not
invent a hash. Do not publish or push template changes without explicit approval.
