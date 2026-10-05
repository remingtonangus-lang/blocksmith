# Blind critic protocol

Purpose: an honest, repeatable score of how far each system is from the reference tier, so the work queue always
attacks the biggest gap. Critics are fresh subagents with **no builder notes**: they see only `frontier/QUALITY_BAR.md`
and an evidence pack.

## Evidence pack (`tools/critic_pack.sh DIR`)
- Screenshots: the CI/llvmpipe tour (vista, street, mountains, desert, plains, lake fog, night, storm), menu/HUD shots,
  feature shots (vegetation lineup, characters, horse, weapons, interiors) when they exist.
- `bots.txt`: bot oracle results (road, explore, town, gunfight, hunt, missions, systems) with failures.
- `bench.txt`: benchmark percentiles and memory, with the hardware they were measured on.
- `features.txt`: a factual inventory of what the build contains (counts: species, weapons, missions, NPC types,
  dialogue lines, sounds) generated from the code/data — no adjectives, no intentions, no "planned".
- Never include: status notes, design docs, commit messages, agent reports.

## Critic prompt (template)
> You are a senior reviewer of open-world games. Grade this build against QUALITY_BAR.md using only the evidence in
> DIR. For each of the 14 systems give a score 0-10 (10 = indistinguishable from the reference tier on that axis,
> 7 = strong AA, 5 = competent indie, 3 = prototype, 1 = placeholder, 0 = absent), a one-paragraph justification
> citing specific evidence files, and the three concrete changes that would raise the score most. Missing evidence
> for a system scores it at most 2. Be blunt; do not grade on effort or potential. Output JSON:
> {"scores": {system: n}, "notes": {system: text}, "fixes": {system: [3 items]}, "top_gaps": [ranked list of
> {system, gap = weight × (10 − score), why}]}.

## Cadence
After every major merge (or every ~6 hours of work): build the pack, run 2 critics independently, average scores,
record the round in `docs/status/frontier.md` (Ranked gaps), and take the top gap next.
