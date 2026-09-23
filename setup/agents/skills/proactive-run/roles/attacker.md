# attacker

Red-teaming: generates scenarios and adversarial versions, runs them against
**real targets**, and turns what it finds into reproduction packs somebody else
can re-run. Where the ideator proposes, the attacker executes — the split is
worth keeping, because generating and executing reward different dispositions.

`SKILL.md` → "Comparing two directions" and "Verification discipline" bind
every number this role produces; `roles/README.md` has the common prompt shape.

## Prompt shape that worked

- **The target set, frozen and named by digest.** An attacker measuring against
  a moving target produces results nobody can reproduce.
- **"A finding is a reproduction pack, not an anecdote."** Every finding ships
  with the environment, the trigger, the expected behaviour, the observed
  behaviour, and the command that runs it again. Findings that cannot be re-run
  do not enter the table.
- **Rules of engagement, verbatim and unmissable.** What is in scope, what is
  categorically forbidden, and what must never appear in any deliverable. Ours
  had a hard rule that no deliverable could reproduce source material verbatim
  beyond short attributed excerpts — so the attacker wrote scenarios in
  *derived, generalised* form: mechanism, environment condition, trigger
  pattern, expected behaviour, observed rate, with paraphrased triggers and our
  own seeds' names and numbers.
- **Adversarial review of the inputs themselves** is part of the job — ours
  reviewed the generated environments for confusable artefacts that would have
  made a finding ambiguous.
- **Report negative results.** A scenario that fails to reproduce anything is
  data, and an attacker judged on hits will stop reporting them.

## Best practices learnt

- **Build the small fixture early.** Three times in this run a defect argued
  about for hours narrowed in minutes under one synthetic fixture.
- **Interleave against the frozen set**, never batch per target, for the same
  reason a benchmark interleaves: load is not constant.
- **A failure class is worth more than a failure.** One reproduction is an
  anecdote; the class — the condition under which it reproduces — is what
  transfers. Push every finding up to its class before reporting it.
- **The seventh thing you build to fail in a specific way will fail in a
  different one**, and that is a result. Ours did, and the wreckage was more
  useful than the narration would have been.
- **Keep the floor case.** A deliberately weak target that should fail
  everything calibrates the instrument, and when it behaves like a floor you
  have evidence the instrument discriminates at all.
- **Distinguish "not found" from "not measured" from "too few tries".** An
  attacker that reports zeros without saying which kind will have its table
  misread.

## Known failure modes

- **Optimising for hits.** The attacker that reports only reproductions makes
  the target look worse than it is and the run's numbers unusable.
- **A finding that depends on the attacker's own harness.** Run the null case:
  the attack against a target it should not affect. If that reproduces, you are
  measuring your harness.
- **Leaking the source material.** Where inputs are sensitive, the derived form
  must be enforced at review time, not trusted at generation time.
- **Chasing the interesting failure past its value.** A class is established;
  the twelfth reproduction of it costs the same as the first of the next class.

## Model

A strong model — generating a genuinely diverse attack set is the hardest
generative task in a run, and a weaker model produces variations on one idea
while appearing productive.
