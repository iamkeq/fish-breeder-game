"""Cuts an animation strip (several frames of one object standing side by side
on a flat dark background, with see-through bubbles rising above) into a
transparent sheet of equal-sized frames, all aligned on the same bottom line.

    python tools/cut_animation.py <source.png> <out.png> [frames]

Prints the JSON to paste into an item: "frames" (rects in the new sheet),
"body_height" (pixels at the bottom of a frame that are the object itself,
used for sizing; the bubbles are drawn above it) and "sprite" (the last
frame's body only, for shop icons).

The background colour is read from the top-left pixel. Above each object the
background is "unmixed" from every pixel, so bubbles stay semi-transparent.
Around the object only background connected to the image edge is removed, so
dark parts of the object (an open chest's inside) stay solid.
"""
import json
import sys
from collections import deque

from PIL import Image

TOLERANCE = 14  # how far from the background colour still counts as background


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    want = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    im = Image.open(src).convert("RGB")
    W, H = im.size
    px = im.load()
    bg = px[0, 0]

    def dist(c):
        return max(abs(c[i] - bg[i]) for i in range(3))

    # Objects stand on warm sand: find them by columns of warm pixels.
    warm = [any(px[x, y][0] - px[x, y][2] > 30 and px[x, y][0] > 70 for y in range(H)) for x in range(W)]
    runs, start = [], None
    for x in range(W + 1):
        on = x < W and warm[x]
        if on and start is None:
            start = x
        elif not on and start is not None:
            if x - start > 20:
                runs.append((start, x - 1))
            start = None
    if want and len(runs) != want:
        sys.exit(f"found {len(runs)} objects, expected {want}: {runs}")

    # Each frame owns the columns halfway to its neighbours.
    bounds = []
    for i, (a, b) in enumerate(runs):
        left = 0 if i == 0 else (runs[i - 1][1] + a) // 2
        right = W - 1 if i == len(runs) - 1 else (b + runs[i + 1][0]) // 2
        bounds.append((left, right, a, b))

    # Body top: the highest row (going up from the bottom) where the object is
    # still solid across a good part of its sand width.
    def body_top(a, b):
        bottom = max(y for y in range(H) for x in range(a, b + 1, 3) if dist(px[x, y]) > TOLERANCE)
        top = bottom
        found = False
        for y in range(bottom, -1, -1):
            solid = sum(1 for x in range(a, b + 1) if dist(px[x, y]) > TOLERANCE) >= (b - a) * 0.25
            if solid:
                found = True
                top = y
            elif found:
                break
        return top, bottom

    # Background reachable from the image edge (through background pixels).
    outside = bytearray(W * H)
    q = deque((x, y) for x in range(W) for y in (0, H - 1))
    q.extend((x, y) for y in range(H) for x in (0, W - 1))
    while q:
        x, y = q.popleft()
        i = y * W + x
        if outside[i] or dist(px[x, y]) > TOLERANCE:
            continue
        outside[i] = 1
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < W and 0 <= ny < H and not outside[ny * W + nx]:
                q.append((nx, ny))

    def unmix(c):
        """Colour-to-alpha against the background."""
        a = 0.0
        for i in range(3):
            if c[i] > bg[i]:
                a = max(a, (c[i] - bg[i]) / (255 - bg[i]))
            elif c[i] < bg[i]:
                a = max(a, (bg[i] - c[i]) / bg[i])
        if a <= 0.02:
            return (0, 0, 0, 0)
        rgb = tuple(max(0, min(255, round(bg[i] + (c[i] - bg[i]) / a))) for i in range(3))
        return rgb + (round(a * 255),)

    cut = Image.new("RGBA", (W, H))
    cpx = cut.load()
    tops = []
    for left, right, a, b in bounds:
        top, bottom = body_top(a, b)
        tops.append((top, bottom))
        for y in range(H):
            for x in range(left, right + 1):
                c = px[x, y]
                if y < top - 2:
                    cpx[x, y] = unmix(c)
                elif outside[y * W + x]:
                    cpx[x, y] = (0, 0, 0, 0)
                else:
                    cpx[x, y] = c + (255,)

    # Content box of each frame, then one shared cell size, bottom-aligned
    # and centred on the sand.
    boxes = []
    for left, right, a, b in bounds:
        xs, ys = [], []
        for y in range(H):
            for x in range(left, right + 1):
                if cpx[x, y][3] > 20:
                    xs.append(x)
                    ys.append(y)
        boxes.append((min(xs), min(ys), max(xs), max(ys)))
    centres = [(a + b) / 2 for _, _, a, b in bounds]
    half = max(max(c - bx[0], bx[2] - c) for c, bx in zip(centres, boxes)) + 1
    cw = int(half * 2) + 2
    bottom = max(bx[3] for bx in boxes)
    top = min(bx[1] for bx in boxes)
    ch = bottom - top + 2

    sheet = Image.new("RGBA", (cw * len(bounds), ch))
    frames = []
    for i, c in enumerate(centres):
        x0 = int(c - cw / 2)
        piece = cut.crop((x0, top, x0 + cw, top + ch))
        # Only keep this frame's own columns.
        left, right = bounds[i][0], bounds[i][1]
        mask = Image.new("L", piece.size, 0)
        mask.paste(255, (max(0, left - x0), 0, min(cw, right - x0 + 1), ch))
        clean = Image.new("RGBA", piece.size)
        clean.paste(piece, (0, 0), mask)
        sheet.paste(clean, (i * cw, 0))
        frames.append([i * cw, 0, cw, ch])
    sheet.save(out)

    body_height = bottom - min(t for t, _ in tops) + 2
    last_top = tops[-1][0] - top
    print(json.dumps({
        "frames": frames,
        "body_height": body_height,
        "sprite": [frames[-1][0], last_top, cw, ch - last_top],
    }))


if __name__ == "__main__":
    main()
