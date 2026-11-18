#!/bin/bash
# shot.sh <name> [keys...]   send keys (optional), wait, screenshot to dev/out/tour/<name>.png
T=/c/Users/admin/src/swgr-darkmode/dev/tools
OUT=/c/Users/admin/src/swgr-darkmode/dev/out/tour; mkdir -p "$OUT"
name=$1; shift
if [ $# -gt 0 ]; then powershell -NoProfile -ExecutionPolicy Bypass -File "$T/keys.ps1" -Keys "$(IFS=,; echo "$*")" -Delay 900 >/dev/null; fi
sleep "${WAIT:-2.5}"
powershell -NoProfile -ExecutionPolicy Bypass -File "$T/winshot.ps1" -Out "$(cygpath -w "$OUT")\\$name.png" >/dev/null && echo "$OUT/$name.png"
