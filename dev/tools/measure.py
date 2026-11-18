"""Mean luminance (0-255) of background patches in each step_*.png."""
import glob, re, sys
from PIL import Image
REGIONS = {"top-left": (100, 100, 600, 500), "top-right": (2900, 150, 3300, 450),
           "mid-left": (200, 700, 700, 1000), "floor": (100, 1250, 900, 1400), "frame": None}
labels = dict(l.split("\t", 1) for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if "\t" in l)
print(f"{'step':<32}" + "".join(f"{k:>11}" for k in REGIONS))
for p in sorted(glob.glob(sys.argv[2] + "/step_*.png"), key=lambda s: int(re.findall(r"\d+", s)[-1])):
    n = re.findall(r"\d+", p)[-1]
    im = Image.open(p).convert("L")
    row = []
    for k, box in REGIONS.items():
        c = im.crop(box) if box else im
        h = c.histogram(); total = sum(h)
        row.append(sum(i * v for i, v in enumerate(h)) / total)
    print(f"{n + ' ' + labels.get(n, '?'):<32}" + "".join(f"{v:>11.1f}" for v in row))
