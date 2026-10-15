---
name: tier-med
description: Work the Blocksmith backlog's [T:med] items at medium effort. Load this when docs/roadmap/TIER says "current: med" or the stop hook tells you the tier moved to med.
effort: medium
---

# Tier med

You are working the **[T:med]** items in docs/roadmap/backlog.md (TIERS rule at the top). This skill sets your effort to **medium** for the tier.

1. Pull claude/quest-port. Confirm docs/roadmap/TIER says `current: med`.
2. Take the open [T:med] items top to bottom (open = no DONE, not CLAIMED by another thread). For each: check it against current code first (he may have played an older build; if it is already fixed, mark it DONE with "already fixed by <commit>").
3. Otherwise: claim it, write its lettered parts (his intent first, then your own concrete objectives), build every part, compile, run its one quick check, push, self-merge, and mark it DONE naming each part. One and done, no helper agents, no test work.
4. If an item is harder than med, retag it one tier up with a one-line reason and move on.
5. When no [T:med] item is left, end your turn with "TIER EMPTY: med". The stop hook then moves the tier forward and tells you which tier skill to load next.
