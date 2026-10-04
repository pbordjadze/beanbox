#!/usr/bin/env python3
"""Renders the app icon: an origami masu box seen from above, full of jelly beans.

    python3 tools/icon/make_icon.py <out.png>

Needs Pillow. Drawn at 4× and downscaled, so edges come out smooth.
"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersampled canvas; downscaled to 1024
BACKGROUND = (236, 233, 226)
# The box: paper colour for the rim, with each inner wall shaded by how it faces the light
# (from the top left).
RIM = (226, 84, 44)
WALLS = {"top": (150, 46, 22), "left": (172, 56, 28), "right": (204, 72, 36), "bottom": (214, 78, 40)}
FLOOR = (122, 36, 18)
BEANS = [
    (228, 40, 48), (250, 196, 30), (60, 170, 74), (246, 128, 26), (120, 62, 170), (252, 244, 232),
    (238, 110, 150), (40, 120, 214), (30, 30, 34), (170, 214, 60), (140, 78, 40), (246, 222, 120),
]


def bean(center, length, width, angle, color):
    """A bean as its own RGBA tile: a slightly kidney-shaped body, a soft shadow and a glint."""
    pad = int(length * 0.9)
    tile = Image.new("RGBA", (pad * 2, pad * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    cx = cy = pad
    # Two overlapping lobes and a waist make the kidney outline.
    half = length / 2
    for dx, dy, r in ((-half * 0.42, width * 0.04, width * 0.52), (half * 0.42, width * 0.04, width * 0.52), (0, -width * 0.05, width * 0.5)):
        draw.ellipse((cx + dx - r * 1.22, cy + dy - r, cx + dx + r * 1.22, cy + dy + r), fill=color + (255,))
    shade = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    ImageDraw.Draw(shade).ellipse((cx - half * 1.3, cy + width * 0.05, cx + half * 1.3, cy + width * 1.1), fill=(0, 0, 0, 70))
    shade = shade.filter(ImageFilter.GaussianBlur(width * 0.18))
    tile = Image.composite(Image.alpha_composite(tile, shade), tile, tile.getchannel("A"))
    glint = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    ImageDraw.Draw(glint).ellipse(
        (cx - half * 0.62, cy - width * 0.36, cx - half * 0.05, cy - width * 0.14), fill=(255, 255, 255, 150))
    tile = Image.alpha_composite(tile, glint.filter(ImageFilter.GaussianBlur(width * 0.05)))
    return tile.rotate(angle, resample=Image.BICUBIC), (int(center[0] - pad), int(center[1] - pad))


def main(out):
    image = Image.new("RGB", (S, S), BACKGROUND)
    draw = ImageDraw.Draw(image)

    outer = S * 0.13          # box edge, from the canvas edge
    rim = S * 0.035           # folded paper edge
    wall = S * 0.085          # how far each inner wall slopes in
    a, b = outer, S - outer
    # Shadow under the box.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((a + S * 0.012, a + S * 0.03, b + S * 0.012, b + S * 0.03), radius=S * 0.02, fill=(60, 40, 30, 120))
    image.paste(shadow.filter(ImageFilter.GaussianBlur(S * 0.02)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(S * 0.02)))
    draw.rounded_rectangle((a, a, b, b), radius=S * 0.012, fill=RIM)
    ia, ib = a + rim, b - rim            # inner edge of the rim
    fa, fb = ia + wall, ib - wall        # the floor
    draw.polygon([(ia, ia), (ib, ia), (fb, fa), (fa, fa)], fill=WALLS["top"])
    draw.polygon([(ia, ia), (fa, fa), (fa, fb), (ia, ib)], fill=WALLS["left"])
    draw.polygon([(ib, ia), (ib, ib), (fb, fb), (fb, fa)], fill=WALLS["right"])
    draw.polygon([(ia, ib), (fa, fb), (fb, fb), (ib, ib)], fill=WALLS["bottom"])
    draw.rectangle((fa, fa, fb, fb), fill=FLOOR)

    # Beans, bottom layer first; laid out on a jittered grid so the box reads as full.
    rng = random.Random(7)
    length, width = S * 0.150, S * 0.084
    spots = []
    span = fb - fa
    for layer, (rows, cols, inset) in enumerate(((5, 4, 0.02), (4, 3, 0.14))):
        for r in range(rows):
            for c in range(cols):
                x = fa + span * (inset + (1 - 2 * inset) * (c + 0.5 + (0.5 if r % 2 else 0) * 0.5) / (cols + 0.25))
                y = fa + span * (inset + (1 - 2 * inset) * (r + 0.5) / rows)
                spots.append((layer, x + rng.uniform(-1, 1) * S * 0.012, y + rng.uniform(-1, 1) * S * 0.012))
    colors = BEANS * 4
    rng.shuffle(colors)
    for i, (layer, x, y) in enumerate(spots):
        tile, at = bean((x, y), length, width, rng.uniform(0, 180), colors[i])
        image.paste(tile, at, tile)

    # The walls cast a soft shadow onto the beans along the lit-from-top-left edges.
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    edraw = ImageDraw.Draw(edge)
    edraw.polygon([(ia, ia), (ib, ia), (ib, ia + wall * 1.5), (ia, ia + wall * 1.5)], fill=(40, 12, 6, 110))
    edraw.polygon([(ia, ia), (ia + wall * 1.4, ia), (ia + wall * 1.4, ib), (ia, ib)], fill=(40, 12, 6, 80))
    edge = edge.filter(ImageFilter.GaussianBlur(S * 0.022))
    inside = Image.new("L", (S, S), 0)
    ImageDraw.Draw(inside).rectangle((fa, fa, fb, fb), fill=255)
    image.paste(edge, (0, 0), Image.composite(edge.getchannel("A"), Image.new("L", (S, S), 0), inside))

    # Redraw the rim over anything that spilled, with the crease lines of the folds.
    for x0, y0, x1, y1 in ((a, a, b, ia), (a, ib, b, b), (a, a, ia, b), (ib, a, b, b)):
        draw.rectangle((x0, y0, x1, y1), fill=RIM)
    crease = (188, 64, 30)
    for p, q in (((a, a), (ia, ia)), ((b, a), (ib, ia)), ((a, b), (ia, ib)), ((b, b), (ib, ib))):
        draw.line([p, q], fill=crease, width=int(S * 0.004))
    draw.rectangle((ia, ia, ib, ib), outline=crease, width=int(S * 0.003))

    image.resize((1024, 1024), Image.LANCZOS).save(out)


if __name__ == "__main__":
    main(sys.argv[1])
