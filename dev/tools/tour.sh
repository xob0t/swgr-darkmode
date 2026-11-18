#!/bin/bash
# Scripted tour of known front-end screens from the main menu (Campaign tab focused).
# Usage: tour.sh <outdir-name>     -> dev/out/tours/<name>/NN_label.png + contact.png
T=/c/Users/admin/src/swgr-darkmode/dev/tools
OUT=/c/Users/admin/src/swgr-darkmode/dev/out/tours/${1:-tour_$(date +%H%M%S)}
mkdir -p "$OUT"
k() { powershell -NoProfile -ExecutionPolicy Bypass -File "$T/keys.ps1" -Keys "$1" -Delay 700 >/dev/null; }
s() { sleep "${2:-2.5}"; powershell -NoProfile -ExecutionPolicy Bypass -File "$T/winshot.ps1" -Out "$(cygpath -w "$OUT")\\$1.png" >/dev/null; echo "$1"; }

k "Q,Q,Q";            s 01_campaign
k "E";                s 02_scenarios
k "E";                s 03_arcade
k "E";                s 04_multiplayer 4
k "Tab";              s 05_settings_gameplay 4
k "E";                s 06_settings_audio
k "E";                s 07_settings_visuals
k "E";                s 08_settings_controls
k "E";                s 09_settings_accessibility
k "E";                s 10_settings_extras
k "Esc";              s 11_back_main 3
k "Q,Q,Q";            s 12_campaign_again 1.5
k "Right";            s 13_focus_logbook 1.5
k "Enter";            s 14_logbook_main 5
k "E";                s 15_logbook_parts 3
k "E";                s 16_logbook_abilities 3
k "Esc";              s 17_back_from_logbook 3

uv run --with pillow python - "$OUT" <<'EOF'
import glob, os, sys
from PIL import Image, ImageDraw
d = sys.argv[1]
fs = sorted(glob.glob(d + "/[0-9]*.png"))
w, h, cols = 688, 288, 3
W = Image.new("RGB", (w * cols, h * ((len(fs) + cols - 1) // cols)), "black")
for k, f in enumerate(fs):
    im = Image.open(f).convert("RGB").resize((w, h)); dr = ImageDraw.Draw(im)
    dr.rectangle((0, 0, w, 14), fill="black"); dr.text((3, 1), os.path.basename(f), fill="yellow")
    W.paste(im, ((k % cols) * w, (k // cols) * h))
W.save(d + "/contact.png")
print(d + "/contact.png")
EOF
