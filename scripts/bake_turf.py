"""Bake the racecourse's photographic turf and sand textures.

Everything is drawn here from random blades and grains; no photo or outside
asset is used. Each texture tiles seamlessly.

  godot/assets/turf/turf_albedo.png   1 m of mown turf seen from above
  godot/assets/turf/turf_normal.png   its blade relief (OpenGL, +Y up)
  godot/assets/turf/sand_albedo.png   3 m x 3 m of harrowed sand, lines along X
  godot/assets/turf/sand_normal.png

Run: python scripts/bake_turf.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "godot" / "assets" / "turf"
SIZE = 1024
# Blades are drawn at twice the size and filtered down, which antialiases them.
SUPER = 2


def wrap_offsets(x: float, y: float, reach: float, size: int):
    """Every copy of a shape near an edge, so the tile has no seam."""
    xs = [0]
    ys = [0]
    if x < reach: xs.append(size)
    if x > size - reach: xs.append(-size)
    if y < reach: ys.append(size)
    if y > size - reach: ys.append(-size)
    return [(dx, dy) for dx in xs for dy in ys]


def tile_noise(rng: np.random.Generator, size: int, cells: int) -> np.ndarray:
    """Smooth value noise that repeats every tile: `cells` lattice steps across."""
    lattice = rng.random((cells, cells))
    t = np.arange(size) * cells / size
    i = t.astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    j = (i + 1) % cells
    a = lattice[np.ix_(i, i)]
    b = lattice[np.ix_(i, j)]
    c = lattice[np.ix_(j, i)]
    d = lattice[np.ix_(j, j)]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def normal_map(height: np.ndarray, strength: float) -> Image.Image:
    """OpenGL normal map from a tiling height field (wraps at the edges)."""
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * .5 * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * .5 * strength
    # Image rows run down while +Y on the map points up the texture.
    n = np.dstack([-dx, dy, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return Image.fromarray(((n * .5 + .5) * 255).round().astype(np.uint8), "RGB")


def srgb(hex_color: str) -> np.ndarray:
    return np.array([int(hex_color[i:i + 2], 16) for i in (1, 3, 5)], float)


def bake_turf() -> None:
    rng = np.random.default_rng(20261001)
    size = SIZE * SUPER
    # Thatch and soil between the blades.
    soil = np.zeros((size, size, 3))
    floor = tile_noise(rng, size, 24) * .6 + tile_noise(rng, size, 96) * .4
    for k, c in enumerate(srgb("#2c3412")):
        soil[..., k] = c * (.75 + floor * .5)
    color = Image.fromarray(soil.clip(0, 255).astype(np.uint8), "RGB")
    height = Image.new("F", (size, size), 0.0)
    paint = ImageDraw.Draw(color)
    lift = ImageDraw.Draw(height)
    # Lush patches carry more, slightly bluer blades; others are a touch yellower.
    lush = tile_noise(rng, SIZE, 6)
    low = srgb("#24420e")
    mid = srgb("#4f7a1c")
    top = srgb("#9cba3e")
    dry = srgb("#b8b064")
    blue = srgb("#3d6a2a")
    count = 34000
    heights = np.sort(rng.random(count) ** .8)
    for h in heights:
        x, y = rng.random(2) * size
        patch = lush[int(y / SUPER) % SIZE, int(x / SUPER) % SIZE]
        # Seen from above an upright blade is a short stroke; taller ones lean further.
        angle = rng.random() * np.pi * 2
        length = (10 + 26 * h + rng.random() * 10) * SUPER
        width = (2.2 + rng.random() * 2.2) * SUPER
        tone = mid + (top - mid) * h if h > .5 else low + (mid - low) * (h * 2)
        tone = tone * (.86 + rng.random() * .28)
        roll = rng.random()
        if roll < .035 + (1 - patch) * .03:
            tone = dry * (.7 + h * .35)
        elif roll < .12 + patch * .1:
            tone = tone * .55 + blue * .45
        direction = np.array([np.cos(angle), np.sin(angle)])
        side = np.array([-direction[1], direction[0]])
        # Three segments light up from the shaded base to the sunlit tip.
        steps = 3
        for dx, dy in wrap_offsets(x, y, length + width, size):
            origin = np.array([x + dx, y + dy])
            for s in range(steps):
                a = s / steps
                b = (s + 1) / steps
                wa = width * (1 - a * .7) * .5
                wb = width * (1 - b * .7) * .5
                p0 = origin + direction * length * a
                p1 = origin + direction * length * b
                quad = [tuple(p0 - side * wa), tuple(p1 - side * wb), tuple(p1 + side * wb), tuple(p0 + side * wa)]
                shade = .72 + .38 * b
                paint.polygon(quad, fill=tuple(int(v) for v in np.clip(tone * shade, 0, 255)))
                lift.polygon(quad, fill=float(h * (.55 + .45 * b)))
    color = color.resize((SIZE, SIZE), Image.LANCZOS)
    height = np.asarray(height.resize((SIZE, SIZE), Image.BOX), float)
    # Darken the deep gaps a little more: light barely reaches the thatch.
    occlusion = np.asarray(Image.fromarray((height * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), float) / 255
    rgb = np.asarray(color, float) * (.78 + .22 * np.clip(height * .5 + occlusion, 0, 1))[..., None]
    Image.fromarray(rgb.clip(0, 255).round().astype(np.uint8), "RGB").save(OUT / "turf_albedo.png", optimize=True)
    normal_map(height, 7.0).save(OUT / "turf_normal.png", optimize=True)


def bake_sand() -> None:
    rng = np.random.default_rng(20261002)
    size = SIZE
    # Long harrow furrows along X, wandering slightly, with raked crests.
    y = np.arange(size)[:, None] / size
    wander = tile_noise(rng, size, 5) * .012 + tile_noise(rng, size, 17) * .004
    tines = 56
    phase = (y + wander) * tines
    furrow = np.abs(np.sin(phase * np.pi)) ** .6
    depth = tile_noise(rng, size, 9) * .5 + .5
    height = furrow * depth * .5
    # Sand grains: fine speckle at two scales.
    grain = rng.random((size, size))
    grain = np.asarray(Image.fromarray((grain * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(.7)), float) / 255
    coarse = tile_noise(rng, size, 64)
    height += grain * .35 + coarse * .15
    # Hoof prints: shallow oval dents, about 12 cm long on the 3 m tile.
    prints = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(prints)
    for _ in range(150):
        px, py = rng.random(2) * size
        r = 15 + rng.random() * 7
        for dx, dy in wrap_offsets(px, py, r * 2, size):
            draw.ellipse((px + dx - r, py + dy - r * .8, px + dx + r, py + dy + r * .8), fill=255)
    prints = np.asarray(prints.filter(ImageFilter.GaussianBlur(3.5)), float) / 255
    height -= prints * .45
    mottle = tile_noise(rng, size, 7) * .6 + tile_noise(rng, size, 23) * .4
    light = srgb("#e3c49b")
    dark = srgb("#a77e57")
    shade = np.clip(.35 + furrow * .35 + grain * .25 + mottle * .25 - prints * .35, 0, 1)
    rgb = dark + (light - dark) * shade[..., None]
    # Scattered darker grit and a few pale stones.
    flecks = rng.random((size, size))
    rgb[flecks > .996] *= .62
    rgb[flecks < .0015] = srgb("#efe4cf")
    Image.fromarray(rgb.clip(0, 255).round().astype(np.uint8), "RGB").save(OUT / "sand_albedo.png", optimize=True)
    normal_map(height, 3.2).save(OUT / "sand_normal.png", optimize=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    bake_turf()
    bake_sand()
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.png"))))
