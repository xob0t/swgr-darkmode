"""List light, unsaturated images classified as 'art' (or nil) across screen dumps, grouped by
widget name + resource. These are candidates for new panel patterns.
usage: light_art.py <dump.txt> [...]"""
import re, sys
from collections import Counter

pat = re.compile(r"^\s*I (\S+) (\w+)\*? \(([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)\) (\S+)")
cnt = Counter()
for path in sys.argv[1:]:
    for line in open(path, encoding="utf-8", errors="replace"):
        m = pat.match(line)
        if not m:
            continue
        name, kind, r, g, b, a, res = m.groups()
        r, g, b, a = map(float, (r, g, b, a))
        luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        sat = max(r, g, b) - min(r, g, b)
        if kind == "art" and luma > 0.3 and sat < 0.15 and a > 0.35:
            cnt[(name, res, f"{luma:.2f}")] += 1
for (name, res, l), n in cnt.most_common(60):
    print(f"{n:4d}  {name:32s} {res:50s} luma {l}")
