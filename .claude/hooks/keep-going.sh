#!/bin/bash
# Stop hook (TIERS, Oct 15): in remote (cloud) sessions, keep working while an open item of the current tier remains.
# When the current tier is empty, advance docs/roadmap/TIER to the next tier (in order) that has open items and point
# the thread at that tier's skill (.claude/skills/tier-<tier>, which sets the effort level). Stop only when every tier is empty.
# Escape hatches: .claude/ALLOW_STOP, or a non-remote session.
set -uo pipefail
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] || [ -f "$dir/.claude/ALLOW_STOP" ]; then exit 0; fi
tierfile="$dir/docs/roadmap/TIER"; backlog="$dir/docs/roadmap/backlog.md"
tier=$(sed -n 's/^current: *//p' "$tierfile" 2>/dev/null | head -1)
[ -z "$tier" ] && exit 0
count() { grep -E "^[A-Z][A-Za-z0-9-]*\. " "$backlog" 2>/dev/null | grep -F "[T:$1]" | grep -v -E "\[DONE|DONE\]" | grep -vc "CLAIMED"; }
open=$(count "$tier")
if [ "${open:-0}" -gt 0 ]; then
cat <<JSON
{"decision": "block", "reason": "Do not stop: $open open [T:$tier] item(s) remain in docs/roadmap/backlog.md. Keep the tier-$tier skill loaded and take the next one top to bottom: claim, lettered parts, build every part, compile, one quick check, push, self-merge, mark DONE naming each part. When no [T:$tier] item is left, end with: TIER EMPTY: $tier"}
JSON
exit 0
fi
next=""
for t in low med high xhigh; do
  if [ "$t" != "$tier" ] && [ "$(count "$t")" -gt 0 ]; then next="$t"; break; fi
done
[ -z "$next" ] && exit 0
printf 'current: %s\norder: low, med, high, xhigh\n' "$next" > "$tierfile"
n=$(count "$next")
cat <<JSON
{"decision": "block", "reason": "Tier $tier is empty, so the tier is now $next (docs/roadmap/TIER updated; commit and push that change first). Load the tier-$next skill with the Skill tool now: it sets your effort for this tier. Then work the $n open [T:$next] item(s) top to bottom the same way, and end with: TIER EMPTY: $next"}
JSON
