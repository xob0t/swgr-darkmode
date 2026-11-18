"""Labeled contact sheet for a run folder: contact.py <dir> [cols]"""
import glob, sys
from PIL import Image, ImageDraw
d = sys.argv[1]; cols = int(sys.argv[2]) if len(sys.argv) > 2 else 4
n = len(glob.glob(d + "/step_*.png"))
labels = dict(l.split("\t", 1) for l in open(d + "/labels.tsv", encoding="utf-8").read().splitlines() if "\t" in l)
w, h = 516, 216
W = Image.new("RGB", (w * cols, h * ((n + cols - 1) // cols)), "black")
for k in range(n):
    im = Image.open(f"{d}/step_{k+1}.png").convert("RGB").resize((w, h))
    dr = ImageDraw.Draw(im); dr.rectangle((0, 0, w, 16), fill="black"); dr.text((4, 2), f"{k+1} " + labels.get(str(k + 1), ""), fill="yellow")
    W.paste(im, ((k % cols) * w, (k // cols) * h))
W.save(d + "/contact.png")
