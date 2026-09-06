#!/usr/bin/env python3
"""Remove the Codex backing and enlarge the original mark. Requires Pillow."""

from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / "Resources/IconSources/codex-color.png").convert("RGBA")
width, height = source.size
pixels = source.load()
exterior = Image.new("L", source.size)
mask = exterior.load()
queue = deque([(0, 0)])

# Only remove white connected to the outside; keep the enclosed white >_ glyph.
while queue:
    x, y = queue.popleft()
    if not (0 <= x < width and 0 <= y < height) or mask[x, y]:
        continue
    r, g, b, a = pixels[x, y]
    if a == 255 and min(r, g, b) < 250:
        continue
    mask[x, y] = 255
    queue.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))

edge = exterior.filter(ImageFilter.MaxFilter(5))
result = source.copy()
output = result.load()
for y in range(height):
    for x in range(width):
        if mask[x, y]:
            output[x, y] = (0, 0, 0, 0)
        elif edge.getpixel((x, y)):
            # Undo the white matte on antialiased outer edges, using a nearby
            # interior gradient color so dark backgrounds have no white fringe.
            neighbors = [
                pixels[nx, ny]
                for ny in range(max(0, y - 2), min(height, y + 3))
                for nx in range(max(0, x - 2), min(width, x + 3))
                if not mask[nx, ny]
            ]
            color = min(neighbors, key=lambda p: min(p[:3]))
            coverage = (255 - min(pixels[x, y][:3])) / max(1, 255 - min(color[:3]))
            output[x, y] = (*color[:3], round(255 * min(1, coverage)))

bounds = result.getchannel("A").getbbox()
assert bounds is not None
mark = result.crop(bounds)
# Match the other icons' 640 px canvas, leaving layout padding to BrandTile.
canvas = mark.resize((640, 640), Image.Resampling.LANCZOS)
for theme in ("light", "dark"):
    canvas.save(ROOT / f"Resources/icons/{theme}/codex-color.png", optimize=True)
print(f"Source bounds: {bounds}; output bounds: {canvas.getchannel('A').getbbox()}")
