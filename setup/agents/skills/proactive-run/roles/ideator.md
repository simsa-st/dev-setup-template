# ideator

Produces a **ranked, mechanism-verified backlog**. Proposes; never implements.
The role exists because the dominant failure of an unattended run is a queue
that drains into "needs the human" — and because the second-dominant failure is
a queue of plausible-sounding items nobody can act on.

`SKILL.md` → "Budget and pacing" explains why a deep pre-authorised backlog is
the thing that keeps a run spending honestly; `roles/README.md` has the common
prompt shape.

## Prompt shape that worked

- **"Ranked" and "mechanism-verified" are both load-bearing.** Every item
  carries: what it would show, **the mechanism by which it would show it**, what
  it costs, and what would make it not worth doing. An item without a mechanism
  is a topic, not a task.
- **Diversity is a stated criterion**, with the dimensions named — otherwise
  ten items arrive that are one item at different sizes. Ours named vertical,
  size, region, messiness and coverage of the states that mattered.
- **"You never implement"**, explicitly, and "your output is a file, not a
  change".
- **Depth target, in numbers**: "at least N items, ranked, at all times". A
  backlog is a stock, not a flow; if it is ever empty the run stalls at 3 a.m.
- **Pre-authorised spend categories** to rank against, so surplus budget has
  somewhere honest to go: adversarial self-review against real systems,
  re-verification of worker claims, test strengthening, comparing directions.

## Best practices learnt

- **Front-load it.** The backlog should be deep *before* the run starts, with
  the gate decisions already made in writing — including the ones you would
  rather defer. Every question left open becomes a stall at the worst hour.
- **Rank by what the answer changes**, not by interest. The item whose two
  possible outcomes lead to the same next action is not worth running, however
  interesting it is.
- **An idea's mechanism is checkable before the idea is.** Most bad items die
  on "how would this show up in the data?" — which costs a paragraph, not a run.
- **Keep the rejected items, with the reason.** They come back, and the reason
  is the expensive part. A run re-proposed the same three dead ends twice
  because the rejections lived in a conversation.
- **Re-rank on every real result.** A backlog ranked once is a plan, and the
  point of the role is that the run is not following a plan.

## Known failure modes

- **Plausible, unfalsifiable items.** "Investigate whether X matters" survives
  any outcome. Force the mechanism and the decision it changes.
- **Implementing.** The ideator that starts writing code stops producing the
  thing nobody else produces, and it always thinks this is the responsible
  choice in the moment.
- **Ranking by novelty.** The highest-value item in a stalled run is almost
  always "verify the thing we already believe", and it ranks last on novelty.
- **A backlog written for the author.** Items must be executable by a worker
  with no context; if an item only makes sense to the ideator, it is a note.

## Model

A capable but cheaper model than the manager's works well: the role rewards
breadth and fluency more than depth, and its output is filtered by the manager
before anything is spent on it. Give it a different model from the researcher's
if you can — correlated blind spots are the thing to avoid.
