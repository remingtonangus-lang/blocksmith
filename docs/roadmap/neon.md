# Neon: the lead (Remington, Nov 21 2026)

Fable is off. Neon (Gemini 4 Neon, High, in the Gemini app on Remington's account) is now the project's lead and
supervisor: it sets the plan, reviews code, hunts bugs and brings ideas. Opus lanes do all the coding. Decisions about
money, design taste and store submissions still go to Remington, and his own instructions always win over Neon's.

Neon cannot see the project chat. Everything goes through GitHub, carried by the hourly watchdog on the Mac (:17).

## The plan

- The pinned issue labelled `neon-plan` ("Neon plan") is the work list. Lanes take work from it, top down, unless
  Remington has asked for something else.
- When you finish or start an item, leave a one-line comment on the plan issue (item, PR number, state). Neon reads
  those comments when it rewrites the plan.
- The watchdog asks Neon for a fresh plan whenever claude/quest-port has moved since the last one, and replaces the
  issue body with it.

## Asking Neon

- Open an issue with the label `neon`. Title: `[lane name] short question`. Body, self-contained: what you want
  (ideas, a review, pick between options, a second opinion on a bug), branch and commit, files and functions, numbers
  you measured, what you already tried, and what you want back.
- For a review, give the PR number; the watchdog pastes Neon the diff.
- Push first: Neon reads the code from branch `neon/code`, a text-only mirror of claude/quest-port (100 MB import
  limit) that the watchdog refreshes right before each relay. Unmerged work: say which branch and the watchdog adds
  the diff.
- The answer arrives as a comment on your issue, usually within the hour, and the label becomes `neon-answered`.
  Close the issue when you are done with it.

## What Neon also gets

- Every playtest: his voice-note audio (Neon is the source of truth for what he said) and docs/playtests/<date>/.
- docs/neon/RECENT.md in the mirror: the last two days of commits on claude/quest-port, open PRs and open issues.
