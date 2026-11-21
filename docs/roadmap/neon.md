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
- Push first: the watchdog reads your issue, your branch or PR diff and the files you name straight from GitHub and
  pastes them to Neon as text (Neon has no repo access of its own and no 17 MB of code in its head). Name the files
  and functions you want looked at.
- The answer arrives as a comment on your issue, usually within the hour, and the label becomes `neon-answered`.
  Close the issue when you are done with it.

## What Neon also gets

- Every playtest: his voice-note audio (Neon is the source of truth for what he said) and docs/playtests/<date>/.
- With every plan rewrite: CLAUDE.md, the backlog, the last two days of commits, open PRs and issues, the plan issue's
  comments, the bug ledger's tail, the newest playtest notes and an index of every code file; then the code files it asks
  for, which it reviews in a comment on the plan issue.
