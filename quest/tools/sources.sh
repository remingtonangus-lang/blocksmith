#!/bin/bash
# Prints the shared Sources/*.swift files the Quest build compiles: everything except the Mac platform files
# listed in quest/mac-only.txt (window/input/Metal renderer/audio engine/test harness entry points).
cd "$(dirname "$0")/../.."
skip=" $(grep -v '^#' quest/mac-only.txt | awk 'NF {print $1}' | tr '\n' ' ') "
for f in Sources/*.swift; do
  case "$skip" in *" $(basename "$f") "*) ;; *) echo "$f" ;; esac
done
