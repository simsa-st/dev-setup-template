# presenter

Owns the report and the interactive webapp **as products** — organisation,
deduplication, visuals, "important first, details one click away" — not merely
their freshness. The presenter is the role that decides what the human sees
first, which makes it the role with the most leverage over whether the run's
work lands.

See `KICKOFF.md` → "The live report loop" for the assembled recipe, and
`SKILL.md` → "Deliverables and close-out" for the rules that bind it.

## Prompt shape that worked

- **The landing page has one job**: the finding, stated in a sentence, above
  everything else. Apparatus, method and caveats come after. Say this in the
  prompt, because the default instinct is chronological.
- **Name the row form explicitly if the human has one.** Ours was, verbatim:
  *found-count first, competence beside it, the rate as a subordinate detail.*
  That is not cosmetic — a high reproduction rate next to poor competence means
  **worse at the job**, not closer to the target, so the rate may never lead and
  never appears without the competence in the same row. A presenter given
  "present the results clearly" will lead with the rate, because it is the
  biggest number.
- **"Details one click away"**, with the mechanism named: every run document
  rendered to its own page with the same styling, so the link works over
  `http://` *and* `file://`.
- **The render check is part of the deliverable**, not a step afterwards.
- **Do not rebuild into `dist/` during a measurement run** — a build can be
  heavy enough to perturb the thing being measured. Ours did, once, plausibly
  costing a run a race it would otherwise have won.

## Best practices learnt

- **Split the data producer from the presentation, and make the file between
  them a contract.** A loop recomputes `dist/<thing>.json` beside the live job,
  read-only over `data/`, written atomically; the page renders that file and
  computes nothing. If the card needs a field the producer does not emit, **the
  producer is where it is added.** This is what made the live table possible at
  all: the site is a static `python3 -m http.server -d dist`, so *a JSON file
  in that directory is already the endpoint* — no backend, no wiring, no
  restart, and the page re-renders itself in place on a timer with no reload.
- **Write atomically.** `tmp` + `os.replace`, so a poller never sees half a
  table. One line of code; without it the page flickers garbage under load.
- **No statistic is computed in the browser.** `k/n` as a percentage with k and
  n printed beside it, and nothing else. Intervals belong to the researcher's
  code and come *down the producer*, never out of a page.
- **Print both denominators when there are two**, and say what each answers.
  Ours: "N of M classes found" where M is the classes whose verdict settled,
  and "(reproduced X% — k of n)" where n is every scored item. Aligning the
  second denominator with the first inflated one measurement's rate from 46.7%
  to 93.3%, because the excluded cells were exactly the zeros. A worker caught
  that; it would have been the headline number.
- **A long-lived report needs a staleness banner and a known-stale list** at
  the top, naming what supersedes what. Two runs reopened a closed report and a
  reader could not tell which half was current.
- **Two same-shaped tables from different treatments must say so in their
  headings**, and say that they will not agree. Otherwise the reader assumes a
  regression.
- **Cross-check every commit and path reference the report cites.** Stale
  references are the single most common defect in an interactive report.

## Render checks — the part that is easy to skip

- Run the live page **and a copy with the polling removed in one pass**, so the
  check cannot pass against a dead poller. Do not let anyone "simplify" that.
- Assert a **mutated input turns the check red** — reverse the direction of the
  claim and watch it fail. Five checks in one night of this run turned out to
  be *incapable* of failing.
- Check desktop **and** mobile rendering, and the legacy navigation you left in
  place for old links.
- Block HTTP(S) inside the check so a page that quietly depends on a CDN fails
  in the check rather than in front of the human.
- The report builder must read **cached** meters only. Ours called a status
  script that issues a paid model probe — the report was spending the budget it
  was reporting on.

## Known failure modes

- **A build gate that has been failing silently for days.** Ours (`--check`)
  lost twelve of thirteen required section ids in a rewrite and kept passing,
  because the gate being run and reported green was a *different script* with a
  similar name. Print what the gate checked, not only that it passed.
- **The page that cannot reach "done".** A progress counter derived from the
  wrong unit — we counted queue *lines* where two lines named one item, so the
  count had a ceiling one below its own total and would have sat at "56/57
  done" forever, in front of the human, at the read-out.
- **Presenting the rate because it is the biggest number.** See above.
- **Polishing before the numbers are verified.** A beautiful page of unverified
  cells is worse than an ugly page of verified ones; it is more convincing.

## Model

A strong model. This role writes prose the human will act on and makes
editorial calls about what leads — both are judgement, and neither is
recoverable by a later pass, because nobody re-reads a page they have already
formed an opinion from.
