#!/bin/bash
# Gracefully close SWGR, relaunch via Steam, wait until UE4SS mods have started.
LOG="/c/Program Files (x86)/Steam/steamapps/common/STAR WARS Galactic Racer/Griffin/Binaries/Win64/ue4ss/UE4SS.log"
taskkill //IM SWGR-Win64-Shipping.exe >/dev/null 2>&1
for i in $(seq 1 30); do tasklist | grep -qi SWGR-Win64 || break; sleep 1; done
sleep 3
cmd //c start "" "steam://rungameid/4078430"
sleep 15
for i in $(seq 1 120); do grep -q "${1:-DarkModeDev] dev loader started}" "$LOG" 2>/dev/null && break; sleep 1; done
grep -E "PS scan|DarkMode|DarkProbe|rror" "$LOG" | cut -c1-200 | tail -8
