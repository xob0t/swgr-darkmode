#!/bin/bash
# Waits for the next "[DarkMode] reloaded", then screenshots every "[DarkMode] step N: label"
# ~2.5 s after it appears. Each run gets its own folder under runs/ (never deleted).
# Stops at a "done" step, on a compile/load error, or if the game exits.
LOG="/c/Program Files (x86)/Steam/steamapps/common/STAR WARS Galactic Racer/Griffin/Binaries/Win64/ue4ss/UE4SS.log"
OUT=/c/Users/admin/src/swgr-re/darkmode/runs/${1:-run}_$(date +%H%M%S)
mkdir -p "$OUT"
echo "$OUT" > /c/Users/admin/src/swgr-re/darkmode/last_run.txt
echo "out: $OUT"
start=$(wc -l < "$LOG")
for t in $(seq 1 120); do
  r=$(tail -n +"$((start+1))" "$LOG" | grep -n "DarkMode\] reloaded" | tail -1 | cut -d: -f1)
  [ -n "$r" ] && break
  tail -n +"$((start+1))" "$LOG" | grep -m1 "DarkMode\] \(compile\|load\) error" && exit 1
  sleep 0.5
done
[ -z "$r" ] && { echo "no reload seen"; exit 1; }
start=$((start + r))
seen=0
for t in $(seq 1 600); do
  lines=$(tail -n +"$((start+1))" "$LOG" | grep "DarkMode\] step")
  n=$(printf "%s" "$lines" | grep -c .)
  while [ "$seen" -lt "$n" ]; do
    seen=$((seen+1))
    l=$(printf "%s\n" "$lines" | sed -n "${seen}p" | sed -E 's/.*step ([0-9]+): (.*)/\1\t\2/')
    echo "$l" | tee -a "$OUT/labels.tsv"
    sleep 2.5
    powershell -NoProfile -ExecutionPolicy Bypass -File "C:/Users/admin/src/swgr-re/winshot.ps1" -Out "$(cygpath -w "$OUT")\\step_${seen}.png" >/dev/null
    case "$l" in *done*) tail -n +"$((start+1))" "$LOG" | grep "DarkMode\] \(discovered\|apply error\)"; exit 0;; esac
  done
  tail -n +"$((start+1))" "$LOG" | grep -m1 "DarkMode\] \(compile\|load\) error" && exit 1
  tasklist //FI "IMAGENAME eq SWGR-Win64-Shipping.exe" | grep -qi SWGR-Win64 || { echo "GAME GONE"; exit 1; }
  sleep 0.5
done
echo "timed out"
