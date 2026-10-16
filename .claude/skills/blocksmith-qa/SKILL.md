---
name: blocksmith-qa
description: The Blocksmith find-fix loop. Use for any Blocksmith bug hunting, QA, playtest follow-up, polish pass, "what's broken", nightly QA review, or when a session needs its next highest-value item. Bugs are found by machines (oracles, checkers, bots, image checks, a blind critic), never by asking Remington.
---

# Blocksmith QA: the find-fix loop

Remington plays; he is not the bug finder. Every cycle, the machines look for whole *classes* of bugs, a fix
removes the class (not one instance), and a check keeps it gone. Quality and fidelity over new features.

## Ground rules
- No Swift toolchain in cloud sessions: CI (`.github/workflows/mac.yml`, macos-14) is the compiler and the test
  rig. Before every push run `python3 tools/precheck.py` (brace balance, unseeded randomness, type-check risks).
  Batch commits; a push cancels the running CI run. Read results from the `ci-snaps-claude-blocksmith-playtest`
  branch (`git fetch origin ci-snaps-claude-blocksmith-playtest; git show FETCH_HEAD:<file>`).
- Evidence before claims (vendored `verification-before-completion`): "fixed" means the oracle that caught it now
  passes on CI, quoted with numbers. Debug with `systematic-debugging`: reproduce (replay / harness flags) before
  fixing; one discriminating rerun separates a harness fault from a product bug.
- Honest evidence (adapted from jamescockburn47/game-development-skills, evidence-probes): a teleport proves a
  destination, not the route; granted items prove a transaction, not acquisition; fixed-step acceleration proves
  simulation pacing, not feel. Every bot start position is a disclosed fixture; bots walk, never fly.
- Absence of bugs is a measurement, not a compliment (adapted from fagemx/gstack-game, game-qa): report "0 issues
  in N doors over M instances", never "looks good".

## The loop (each cycle)
1. **Read the machines** (latest ci-snaps): `snap.log` (harness lines `mobtests:`, `padtest:`, `physicstest:`,
   `structcheck:`, `agent ...`), `structcheck.md`, `agent_*.md`, `playthrough.log`, `bench.md`, `smoke.log`.
2. **Look at pixels yourself**: open at least 8 snapshots per cycle (rotate through tours, interiors, night,
   underwater, caves, villages, menus) and write down everything that looks wrong next to a polished commercial
   game. Run the visual oracles' findings first (missing/magenta textures, sky through terrain, black frames).
3. **Blind critic** (adapted from oh-ashen-one/claude-code-game-builder, critic protocol): every few cycles, a
   fresh subagent that has seen no commit messages or notes scores a fixed shot list 0-10 per axis against
   `docs/qa/REFERENCE_SPEC.md` (numeric targets, ranges not points) and names the single biggest gap as a testable
   instruction. Include a progress pair (this round vs the last published round). Spot-check its claims on the
   actual PNG before acting; critics may not contradict a spec line unless they measure it.
4. **Classify** each finding into a bug class in `BUGS.md` (class, oracle that caught it, instances, fix, status).
   New class without an oracle? Write the oracle first (a harness check, a bot goal, an image check), see it fail.
5. **Fix the class** at its root (generator, AI, physics, renderer), keep the change minimal, precheck, push.
6. **Confirm** on the next CI run: the oracle's count for that class drops to 0 (or the expected floor). Then make
   the check strict (`--strict`) so CI fails if the class comes back.
7. Log routine actions in STATUS.md's session log; keep PR #9's what's-new list and known issues current.

## Machines (all headless; flags in main.swift)
| Tool | Finds | Where |
|---|---|---|
| `--structcheck` | blocked / step-up / unreachable doors, unreachable beds and job sites, mobs spawned in blocks, broken beds, floating walls, over every structure kind and dimension | StructCheck.swift, snaps/structcheck.md |
| `--agent village` | buildings a walking player can't enter (opens doors with use) | AgentBots.swift |
| `--agent explorer` | routes the pathfinder accepts but the body can't walk (`path_stuck`), unreachable targets, never swimming | AgentBots.swift |
| `--agent monkey --minimize` | crashes, NaN, inside-solid, fell out, stuck, suffocation damage, entity explosions, tick spikes, menus that won't close; shrinks the replay | Agent.swift / AgentRun.swift |
| `--agent replay F --verify` | reproduces a finding; checks determinism | AgentRun.swift |
| `--mobtests`, `--pathtest`, `--padtest`, `--physicstest`, `--playthrough`, `--bugnotetest` | mob rules, navigation, controller/UI, ships, spawn-to-credits progression | see CLAUDE.md |
| tours (`snap.sh`) | anything visual; read them | snaps/*.png |

## Game-feel lens (adapted from Lagunaswift/GameDevelopmentAudit, game-feel-audit; and gstack-game feel-pass)
For core verbs (mine, place, hit, shoot, jump, land, pick up): list the feedback channels that fire (sound,
particles, camera, knockback, flash, rumble). Under two channels is a finding. Screen shake and flashes must stay
behind the accessibility toggles.

## Not adopted (and why)
Human-in-the-loop questionnaires and approval gates (Remington asked for automation), monetization/retention
lenses (not this game), multi-model GPU orchestration tooling (we render on CI).
