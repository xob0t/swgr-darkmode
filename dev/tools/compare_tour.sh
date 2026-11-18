#!/bin/bash
# compare_tour.sh <run>   drive the front-end menus and screenshot fixed screens to dev/out/compare/<run>/
# Run once with the mod off ("before") and once with it on ("after"); the file names match.
# Starts on the main menu. Never confirms anything (the quit dialog is cancelled).
T=/c/Users/admin/src/swgr-darkmode/dev/tools
OUT=/c/Users/admin/src/swgr-darkmode/dev/out/compare/${1:?run name}
mkdir -p "$OUT"
k() { powershell -NoProfile -ExecutionPolicy Bypass -File "$T/keys.ps1" -Keys "$1" -Delay 700 >/dev/null; }
s() { sleep "${2:-2.5}"; powershell -NoProfile -ExecutionPolicy Bypass -File "$T/winshot.ps1" -Out "$(cygpath -w "$OUT")\\$1.png" >/dev/null; echo "$1"; }

k "Right"; k "Left"                      # first keys after a launch can be dropped
k "Q,Q,Q";      s main_campaign 3
k "E";          s main_scenarios
k "Enter";      s scenario_details 5
k "Esc";        sleep 3
k "Tab";        s settings_gameplay 4
k "E,E";        s settings_visuals
k "Esc";        sleep 3
k "Q,Q,Q";      sleep 1.5
k "Right";      sleep 1
k "Enter";      s logbook 5
k "E";          s logbook_parts 3
k "Esc";        sleep 3
k "Esc";        s quit_dialog 2
k "Down";       k "Enter"                # Cancel
sleep 2
