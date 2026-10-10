#!/bin/bash
# Run a command holding one of 2 machine-wide build slots (8 GB Mac: never more than 2 compiles at once, across all
# worktrees and helper agents). Usage: tools/bs-slot.sh ./build.sh   |   tools/bs-slot.sh tools/quest-local.sh --no-run
while :; do
  for s in 1 2; do
    d=/tmp/bs-build-slot-$s
    if mkdir "$d" 2>/dev/null; then
      echo $$ > "$d/pid"; trap 'rm -rf "$d"' EXIT INT TERM
      "$@"; rc=$?; rm -rf "$d"; exit $rc
    fi
    # reclaim a slot whose holder died
    p=$(cat "$d/pid" 2>/dev/null); [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null && rm -rf "$d"
  done
  sleep 10
done
