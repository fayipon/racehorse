"""Grow the racecourse's trees, bushes and grass tufts.

Branches grow by space colonisation toward points scattered in a lumpy crown,
so every tree has a real limb structure; the foliage is cards cut from leaf
clusters this script paints. No photo or outside model is used.

  godot/assets/trees/leaves.png        2x2 atlas: two tree clusters, bush leaves, a flowering bush
  godot/assets/trees/bark.png          bark colour, tiles 0.6 m around and 1.2 m along
  godot/assets/trees/bark_normal.png
  godot/assets/trees/grass.png         two grass tufts side by side
  godot/assets/trees/<name>.gltf/.bin  trees, bushes and tufts; surface 0 bark (trees only), then foliage

Every mesh carries ambient occlusion in its vertex colour and, on foliage,
normals pointing out of the crown lump it belongs to, so the cards light as
one soft mass rather than as flat sheets.

Run: python scripts/bake_trees.py
"""
import json
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "godot" / "assets" / "trees"


# ---------------------------------------------------------------- textures

def tile_noise(rng, width, height, cx, cy):
    """Smooth value noise that repeats every tile, cx by cy lattice steps."""
    lattice = rng.random((cy, cx))
    tx = np.arange(width) * cx / width
    ty = np.arange(height) * cy / height
    ix, iy = tx.astype(int), ty.astype(int)
    fx, fy = tx - ix, ty - iy
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    jx, jy = (ix + 1) % cx, (iy + 1) % cy
    a = lattice[np.ix_(iy, ix)]
    b = lattice[np.ix_(iy, jx)]
    c = lattice[np.ix_(jy, ix)]
    d = lattice[np.ix_(jy, jx)]
    fx = fx[None, :]
    fy = fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def srgb(hex_color):
    return np.array([int(hex_color[i:i + 2], 16) for i in (1, 3, 5)], float)


def normal_map(height, strength):
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * .5 * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * .5 * strength
    n = np.dstack([-dx, dy, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return Image.fromarray(((n * .5 + .5) * 255).round().astype(np.uint8), "RGB")


def box_blur(array, radius):
    """Mean over a (2r+1) square window, edges clamped; works on float arrays."""
    out = array
    for axis in (0, 1):
        padded = np.pad(out, [(radius + 1, radius) if a == axis else (0, 0) for a in range(out.ndim)], mode="edge")
        summed = np.cumsum(padded, axis=axis)
        upper = np.take(summed, range(2 * radius + 1, summed.shape[axis]), axis=axis)
        lower = np.take(summed, range(0, summed.shape[axis] - 2 * radius - 1), axis=axis)
        out = (upper - lower) / (2 * radius + 1)
    return out


def bleed(image):
    """Spread colour into the transparent margin so mipmaps keep no dark halo."""
    rgba = np.asarray(image, float)
    alpha = rgba[..., 3:] / 255
    rgb = rgba[..., :3]
    weight = alpha.copy()
    acc = rgb * alpha
    for radius in (2, 6, 16, 40):
        blur_acc = box_blur(acc, radius)
        blur_w = box_blur(weight, radius)
        fill = np.where(blur_w > 1e-4, blur_acc / np.maximum(blur_w, 1e-4), 0)
        missing = weight < 1e-3
        rgb = np.where(missing & (blur_w > 1e-4), fill, rgb)
        weight = np.where(missing & (blur_w > 1e-4), 1.0, weight)
        acc = rgb * weight
    out = np.dstack([rgb, rgba[..., 3]])
    return Image.fromarray(out.clip(0, 255).round().astype(np.uint8), "RGBA")


def leaf_polygon(base, angle, length, width):
    """A pointed oval leaf from its stalk end, as polygon points."""
    direction = np.array([math.cos(angle), math.sin(angle)])
    side = np.array([-direction[1], direction[0]])
    points = []
    steps = 9
    for k in range(steps + 1):
        t = k / steps
        w = width * math.sin(math.pi * t) ** .75 * (1 - .25 * t)
        points.append(base + direction * length * t + side * w * .5)
    for k in range(steps, -1, -1):
        t = k / steps
        w = width * math.sin(math.pi * t) ** .75 * (1 - .25 * t)
        points.append(base + direction * length * t - side * w * .5)
    return [tuple(p) for p in points]


def paint_cluster(rng, size, count, leaf_len, palette, round_edge=.9, flowers=0, twig=True):
    """A ragged ball of leaves on a twig, lit from the upper left."""
    scale = 2
    s = size * scale
    image = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    center = np.array([s * .5, s * .52])
    radius = s * .44
    # The outline wanders so no card reads as a disc.
    lobes = rng.random(7) * 2 * math.pi
    def edge(angle):
        return radius * (round_edge + (1 - round_edge) * .5 * (1 + sum(math.sin(angle * (k + 2) + lobes[k]) for k in range(3)) / 3))
    if twig:
        stem = srgb("#4a3a2a")
        for k in range(5):
            a = -math.pi / 2 + rng.uniform(-1.3, 1.3)
            end = center + np.array([math.cos(a), math.sin(a)]) * edge(a) * rng.uniform(.5, .85)
            start = center + np.array([rng.uniform(-.05, .05) * s, s * .45])
            draw.line([tuple(start), tuple(end)], fill=tuple(int(v) for v in stem) + (255,), width=max(2, int(s * .008)))
    leaves = []
    for _ in range(count):
        a = rng.random() * 2 * math.pi
        # A few strays break the outline; the rest fill the ragged ball.
        r = math.sqrt(rng.random()) * edge(a) * (.92 if rng.random() > .12 else 1.08)
        pos = center + np.array([math.cos(a), math.sin(a)]) * r
        depth = rng.random()
        leaves.append((depth, pos, a))
    leaves.sort(key=lambda item: item[0])
    light_dir = np.array([-.55, -.83])
    for depth, pos, a in leaves:
        length = leaf_len * scale * rng.uniform(.75, 1.25)
        width = length * rng.uniform(.42, .58)
        # Leaves hang outward and a little down from where they grow.
        angle = a + rng.uniform(-.9, .9) + .25
        base = pos - np.array([math.cos(angle), math.sin(angle)]) * length * .45
        tone = palette[rng.integers(len(palette))] * rng.uniform(.85, 1.12)
        offset = (pos - center) / radius
        sun = .82 + .3 * float(np.dot(offset, light_dir))
        shade = (.55 + .55 * depth) * sun
        color = np.clip(tone * shade, 0, 255)
        draw.polygon(leaf_polygon(base, angle, length, width), fill=tuple(int(v) for v in color) + (255,))
        rib = np.clip(color * 1.18 + 8, 0, 255)
        tip = base + np.array([math.cos(angle), math.sin(angle)]) * length * .85
        draw.line([tuple(base), tuple(tip)], fill=tuple(int(v) for v in rib) + (255,), width=max(1, int(scale * .9)))
    for _ in range(flowers):
        a = rng.random() * 2 * math.pi
        r = math.sqrt(rng.random()) * edge(a) * .85
        pos = center + np.array([math.cos(a), math.sin(a)]) * r
        petal = srgb("#f2cf3a") * rng.uniform(.85, 1.08)
        for k in range(5):
            pa = k / 5 * 2 * math.pi + rng.random()
            p = pos + np.array([math.cos(pa), math.sin(pa)]) * leaf_len * scale * .16
            rr = leaf_len * scale * .14
            draw.ellipse((p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr), fill=tuple(int(v) for v in np.clip(petal, 0, 255)) + (255,))
        rr = leaf_len * scale * .07
        draw.ellipse((pos[0] - rr, pos[1] - rr, pos[0] + rr, pos[1] + rr), fill=(196, 132, 34, 255))
    return image.resize((size, size), Image.LANCZOS)


def bake_leaves():
    rng = np.random.default_rng(31)
    cell = 512
    atlas = Image.new("RGBA", (cell * 2, cell * 2), (0, 0, 0, 0))
    tree = [srgb(c) for c in ("#3b6a1e", "#4a7a24", "#5a8a2a", "#6b9a30", "#80aa38", "#668f2c", "#517a2c", "#8cae46")]
    bush = [srgb(c) for c in ("#2a4f1c", "#3a6224", "#4a742a", "#5a8330", "#3f5e26")]
    atlas.paste(paint_cluster(rng, cell, 760, 30, tree, round_edge=.55), (0, 0))
    atlas.paste(paint_cluster(rng, cell, 620, 34, tree, round_edge=.45), (cell, 0))
    atlas.paste(paint_cluster(rng, cell, 1000, 20, bush, twig=False), (0, cell))
    atlas.paste(paint_cluster(rng, cell, 800, 19, bush, twig=False, flowers=170), (cell, cell))
    bleed(atlas).save(OUT / "leaves.png", optimize=True)


def bake_bark():
    rng = np.random.default_rng(32)
    size = 512
    # Long vertical ridges split by wandering furrows, with a few short
    # cross-cracks between the plates.
    x = np.arange(size)[None, :] / size
    warp = tile_noise(rng, size, size, 6, 3) * 1.4 + tile_noise(rng, size, size, 14, 7) * .5
    phase = x * 9 + warp
    furrow = (1 - np.abs(np.sin(phase * np.pi))) ** 4
    plates = tile_noise(rng, size, size, 18, 5) * .6 + tile_noise(rng, size, size, 40, 14) * .4
    cracks = np.clip((tile_noise(rng, size, size, 9, 40) - .82) / .1, 0, 1) * (1 - furrow)
    fissure = np.clip(furrow + cracks * .6, 0, 1)
    grain = tile_noise(rng, size, size, 128, 16)
    height = plates * .35 + grain * .2 - fissure * 1.1
    light = srgb("#8a8174")
    dark = srgb("#4f463d")
    rgb = dark + (light - dark) * np.clip(.25 + plates * .55 + grain * .3, 0, 1)[..., None]
    rgb = rgb * (1 - fissure[..., None] * .6)
    moss = tile_noise(rng, size, size, 6, 3)
    rgb = rgb * (1 - .25 * np.clip(moss - .55, 0, 1)[..., None] * 2) + srgb("#4d5a2a") * (.25 * np.clip(moss - .55, 0, 1) * 2)[..., None]
    Image.fromarray(rgb.clip(0, 255).round().astype(np.uint8), "RGB").save(OUT / "bark.png", optimize=True)
    normal_map(height, 6.0).save(OUT / "bark_normal.png", optimize=True)


def paint_tuft(rng, width, height, blades, tall, spread):
    scale = 2
    w, h = width * scale, height * scale
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    base_dark = srgb("#2e4a18")
    tip_light = srgb("#86a03e")
    straw = srgb("#c2b273")
    order = sorted(range(blades), key=lambda _: rng.random())
    for _ in order:
        x0 = w * .5 + rng.normal(0, w * spread)
        blade_h = h * tall * rng.uniform(.45, 1.0)
        lean = rng.normal(0, w * .16)
        bend = rng.normal(0, w * .05)
        dry = rng.random() < .08
        segments = 8
        width0 = rng.uniform(5, 9) * scale * .5
        prev = None
        for k in range(segments + 1):
            t = k / segments
            x = x0 + lean * t * t + bend * math.sin(t * math.pi)
            y = h - blade_h * t
            point = (x, y)
            if prev is not None:
                tone = straw * (.75 + .3 * t) if dry else base_dark + (tip_light - base_dark) * (t ** .8)
                tone = tone * rng.uniform(.95, 1.05)
                draw.line([prev, point], fill=tuple(int(v) for v in np.clip(tone, 0, 255)) + (255,), width=max(1, int(width0 * (1 - t * .85))))
            prev = point
    return image.resize((width, height), Image.LANCZOS)


def bake_grass():
    rng = np.random.default_rng(33)
    atlas = Image.new("RGBA", (1024, 512), (0, 0, 0, 0))
    atlas.paste(paint_tuft(rng, 512, 512, 150, .8, .13), (0, 0))
    atlas.paste(paint_tuft(rng, 512, 512, 70, 1.0, .1), (512, 0))
    bleed(atlas).save(OUT / "grass.png", optimize=True)


# ---------------------------------------------------------------- geometry

class MeshBuilder:
    def __init__(self):
        self.positions, self.normals, self.uvs, self.colors, self.indices = [], [], [], [], []

    def vertex(self, p, n, uv, ao):
        self.positions.append(p)
        self.normals.append(n)
        self.uvs.append(uv)
        self.colors.append((ao, ao, ao, 1.0))
        return len(self.positions) - 1

    def triangle(self, a, b, c):
        self.indices.extend((a, b, c))

    def arrays(self):
        return (np.array(self.positions, np.float32), np.array(self.normals, np.float32),
                np.array(self.uvs, np.float32), np.array(self.colors, np.float32),
                np.array(self.indices, np.uint32))


def write_gltf(name, primitives):
    """primitives: list of (material name, MeshBuilder)."""
    binary = bytearray()
    views, accessors, prims, materials = [], [], [], []

    def add(array, target, component, kind, bounds=False):
        binary.extend(b"\0" * (-len(binary) % 4))
        offset = len(binary)
        data = array.tobytes()
        binary.extend(data)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        accessor = {"bufferView": len(views) - 1, "componentType": component, "count": int(len(array)), "type": kind}
        if bounds:
            accessor["min"] = [float(v) for v in array.min(0)]
            accessor["max"] = [float(v) for v in array.max(0)]
        accessors.append(accessor)
        return len(accessors) - 1

    for material, builder in primitives:
        positions, normals, uvs, colors, indices = builder.arrays()
        normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-6)
        attributes = {
            "POSITION": add(positions, 34962, 5126, "VEC3", True),
            "NORMAL": add(normals, 34962, 5126, "VEC3"),
            "TEXCOORD_0": add(uvs, 34962, 5126, "VEC2"),
            "COLOR_0": add(colors, 34962, 5126, "VEC4"),
        }
        prims.append({"attributes": attributes, "indices": add(indices, 34963, 5125, "SCALAR"), "material": len(materials)})
        materials.append({"name": material, "doubleSided": material != "Bark",
                          "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 1.0}})
    document = {
        "asset": {"version": "2.0", "generator": "racehorse scripts/bake_trees.py"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": prims}],
        "materials": materials,
        "buffers": [{"uri": name + ".bin", "byteLength": len(binary)}],
        "bufferViews": views, "accessors": accessors,
    }
    (OUT / (name + ".bin")).write_bytes(binary)
    (OUT / (name + ".gltf")).write_text(json.dumps(document, separators=(",", ":")), encoding="utf-8")
    triangles = sum(len(b.indices) // 3 for _, b in primitives)
    print(f"{name}: {triangles} triangles, {len(binary) // 1024} KB")


def crown_shade(point, lumps):
    """Ambient light reaching a point: dim deep inside a lump and under the crown."""
    best = 9.0
    for center, radius in lumps:
        best = min(best, np.linalg.norm(point - center) / radius)
    inside = .34 + .66 * min(1.0, max(0.0, (best - .2) / .85)) ** 1.4
    low = min(c[1] - r for c, r in lumps)
    high = max(c[1] + r for c, r in lumps)
    lift = .72 + .28 * min(1.0, max(0.0, (point[1] - low) / (high - low)))
    return inside * lift


def lump_normal(point, lumps):
    best, normal = 9.0, np.array([0.0, 1.0, 0.0])
    for center, radius in lumps:
        t = np.linalg.norm(point - center) / radius
        if t < best:
            best = t
            normal = (point - center) / max(np.linalg.norm(point - center), 1e-4)
    return normal


def add_cards(builder, rng, anchors, lumps, sizes, cells, count):
    """Leaf cards at the given anchor points, facing mostly out of the crown."""
    for k in range(count):
        anchor = anchors[k % len(anchors)] + rng.normal(0, .18, 3)
        size = rng.uniform(*sizes)
        out = lump_normal(anchor, lumps)
        facing = out * .35 + rng.normal(0, 1, 3) * .9
        facing /= np.linalg.norm(facing)
        helper = np.array([0.0, 1.0, 0.0]) if abs(facing[1]) < .9 else np.array([1.0, 0.0, 0.0])
        a = np.cross(facing, helper)
        a /= np.linalg.norm(a)
        b = np.cross(facing, a)
        spin = rng.random() * 2 * math.pi
        a, b = a * math.cos(spin) + b * math.sin(spin), b * math.cos(spin) - a * math.sin(spin)
        cx, cy = cells[rng.integers(len(cells))]
        corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        flip = rng.random() < .5
        ids = []
        for sx, sy in corners:
            p = anchor + a * sx * size * .5 + b * sy * size * .5
            # Inset from the cell's edge so mipmaps never borrow a neighbour.
            u = ((sx * (-1 if flip else 1) * .5 + .5) * .96 + .02) * .5 + cx * .5
            v = ((sy * .5 + .5) * .96 + .02) * .5 + cy * .5
            normal = lump_normal(p, lumps) * .8 + facing * .2
            ids.append(builder.vertex(p, normal, (u, v), crown_shade(p, lumps)))
        builder.triangle(ids[0], ids[1], ids[2])
        builder.triangle(ids[0], ids[2], ids[3])


def sweep(builder, path, radii, sides, lumps, start_v=0.0):
    """Bark tube along a path with per-point radius; returns nothing."""
    path = np.array(path)
    count = len(path)
    if count < 2:
        return
    across = None
    lengths = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))])
    repeats = max(1, round(2 * math.pi * radii[0] / .6))
    rings = []
    for i in range(count):
        before = path[max(i - 1, 0)]
        after = path[min(i + 1, count - 1)]
        tangent = after - before
        tangent /= max(np.linalg.norm(tangent), 1e-6)
        if across is None:
            helper = np.array([0.0, 1.0, 0.0]) if abs(tangent[1]) < .95 else np.array([1.0, 0.0, 0.0])
            across = np.cross(tangent, helper)
        else:
            across = across - tangent * np.dot(across, tangent)
        across /= np.linalg.norm(across)
        up = np.cross(tangent, across)
        ring = []
        for k in range(sides + 1):
            angle = 2 * math.pi * k / sides
            direction = across * math.cos(angle) + up * math.sin(angle)
            p = path[i] + direction * radii[i]
            ring.append(builder.vertex(p, direction, (k / sides * repeats, (start_v + lengths[i]) / 1.2), crown_shade(p, lumps) * .9))
        rings.append(ring)
    for i in range(count - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(sides):
            builder.triangle(a[k], a[k + 1], b[k + 1])
            builder.triangle(a[k], b[k + 1], b[k])


def grow_tree(name, seed, trunk_h, crown_y, crown_r, crown_ry, lumps_n, points_n, cards, card_size, base_radius, lean=.4):
    rng = np.random.default_rng(seed)
    # A lobed crown: a ring of leafy masses round a crown top, with sky showing
    # between them; the lowest masses hang just above the bare trunk.
    crown = np.array([0.0, crown_y, 0.0])
    lumps = [(crown + np.array([0, crown_ry * .3, 0]), crown_r * .48)]
    for k in range(lumps_n - 1):
        theta = k / (lumps_n - 1) * 2 * math.pi + rng.uniform(-.4, .4)
        phi = rng.uniform(-.4, .7)
        direction = np.array([math.cos(phi) * math.cos(theta), math.sin(phi), math.cos(phi) * math.sin(theta)])
        center = crown + direction * np.array([crown_r * .64, crown_ry * .62, crown_r * .64])
        lumps.append((center, crown_r * rng.uniform(.33, .45)))
    low = np.array([min(c[i] - r for c, r in lumps) for i in range(3)])
    high = np.array([max(c[i] + r for c, r in lumps) for i in range(3)])
    # Leaves live in the outer shell of each mass; limbs show inside.
    points = []
    while len(points) < points_n:
        p = low + rng.random(3) * (high - low)
        if p[1] < trunk_h + .4:
            continue
        if any(.4 < np.linalg.norm(p - c) / r < 1 for c, r in lumps):
            points.append(p)
    points = np.array(points)
    # The trunk rises with a slight lean to where the limbs part, and on only
    # if the crown is still out of reach.
    step = .5
    influence, kill = crown_r * .75, step * 2.2
    top = np.array([rng.uniform(-lean, lean), trunk_h, rng.uniform(-lean, lean)])
    segments = int(trunk_h / step)
    nodes = [top * (k / segments) + np.array([math.sin(k * .7) * .03, 0, math.cos(k * .5) * .03]) for k in range(segments + 1)]
    while np.sqrt(((points - nodes[-1]) ** 2).sum(1)).min() > influence * .8:
        nodes.append(nodes[-1] + np.array([0, step, 0]))
        segments += 1
    parents = [-1] + list(range(segments))
    alive = np.ones(len(points), bool)
    for _ in range(400):
        pos = np.array(nodes, np.float32)
        live = points[alive]
        if len(live) == 0:
            break
        d2 = (live ** 2).sum(1)[:, None] + (pos ** 2).sum(1)[None, :] - 2 * live @ pos.T
        nearest = d2.argmin(1)
        dist = np.sqrt(np.maximum(d2[np.arange(len(live)), nearest], 0))
        near = dist < influence
        if not near.any():
            break
        pull = live[near] - pos[nearest[near]]
        pull /= np.linalg.norm(pull, axis=1, keepdims=True)
        sums = np.zeros_like(pos)
        np.add.at(sums, nearest[near], pull)
        grown = np.nonzero(np.linalg.norm(sums, axis=1) > 1e-3)[0]
        added = []
        for n in grown:
            direction = sums[n] / np.linalg.norm(sums[n]) + np.array([0, .12, 0]) + rng.normal(0, .08, 3)
            direction /= np.linalg.norm(direction)
            new = pos[n] + direction * step
            if any(np.linalg.norm(nodes[c] - new) < step * .4 for c in range(len(nodes)) if parents[c] == n):
                continue
            added.append(new)
            nodes.append(new)
            parents.append(int(n))
        if not added:
            break
        added = np.array(added)
        idx = np.nonzero(alive)[0]
        close = ((points[idx][:, None, :] - added[None, :, :]) ** 2).sum(2).min(1) < kill * kill
        alive[idx[close]] = False
    nodes = np.array(nodes)
    count = len(nodes)
    children = [[] for _ in range(count)]
    for c in range(1, count):
        children[parents[c]].append(c)
    # Pipe model: a limb carries the cross-sections of everything it feeds,
    # scaled so the trunk has the asked-for girth. `rank` counts nodes back
    # from the nearest twig tip.
    tip, exponent = .02, 2.4
    radius = np.zeros(count)
    rank = np.zeros(count, int)
    for n in range(count - 1, -1, -1):
        if not children[n]:
            radius[n] = tip
        else:
            radius[n] = sum(radius[c] ** exponent for c in children[n]) ** (1 / exponent)
            rank[n] = min(rank[c] for c in children[n]) + 1
    radius = np.maximum(radius * base_radius / radius[segments], .012)
    # Roots flare where the trunk meets the ground.
    for n in range(segments + 1):
        radius[n] *= 1 + .7 * math.exp(-nodes[n][1] * 2.2)
    # Split into limbs: each node carries on into its thickest child.
    bark = MeshBuilder()
    stack = [(0, None)]
    anchors = []
    while stack:
        start, junction = stack.pop()
        path, radii = ([nodes[junction]], [radius[start]]) if junction is not None else ([], [])
        n = start
        while True:
            path.append(nodes[n])
            radii.append(radius[n])
            if rank[n] <= 3:
                anchors.append(nodes[n])
            kids = sorted(children[n], key=lambda c: -radius[c])
            if not kids:
                break
            for other in kids[1:]:
                stack.append((other, n))
            n = kids[0]
        path = np.array(path)
        # Smooth the colonisation's zig-zag, keeping the joint where it is.
        for _ in range(3):
            if len(path) > 2:
                path[1:-1] = path[1:-1] * .5 + (path[:-2] + path[2:]) * .25
        r0 = radii[0] if junction is None else radii[1]
        if r0 < .035:
            continue
        sides = 10 if r0 > .2 else 8 if r0 > .1 else 6 if r0 > .05 else 4
        keep = [0] + [i for i in range(1, len(path) - 1) if r0 > .1 or i % 2 == 0] + [len(path) - 1]
        sweep(bark, path[keep], [radii[i] for i in keep], sides, lumps)
    leaves = MeshBuilder()
    rng.shuffle(anchors)
    add_cards(leaves, rng, anchors, lumps, card_size, [(0, 0), (1, 0)], cards)
    write_gltf(name, [("Bark", bark), ("Leaves", leaves)])
    height = max(c[1] + r for c, r in lumps)
    return height


def bush(name, seed, lumps_n, size, cards, cells):
    rng = np.random.default_rng(seed)
    lumps = []
    for k in range(lumps_n):
        angle = k / lumps_n * 2 * math.pi + rng.uniform(-.5, .5)
        reach = size * (.0 if k == 0 else rng.uniform(.35, .6))
        r = size * rng.uniform(.45, .62) * (1.15 if k == 0 else 1)
        lumps.append((np.array([math.cos(angle) * reach, r * .8, math.sin(angle) * reach]), r))
    anchors = []
    for _ in range(cards * 2):
        center, r = lumps[rng.integers(len(lumps))]
        d = rng.normal(0, 1, 3)
        d /= np.linalg.norm(d)
        p = center + d * r * rng.uniform(.25, .8)
        if p[1] > .05:
            anchors.append(p)
    leaves = MeshBuilder()
    add_cards(leaves, rng, anchors, lumps, (size * .28, size * .42), cells, cards)
    write_gltf(name, [("Leaves", leaves)])


def tuft(name, cell, width, height, planes=3):
    builder = MeshBuilder()
    for k in range(planes):
        angle = k / planes * math.pi + .3
        a = np.array([math.cos(angle), 0, math.sin(angle)]) * width * .5
        facing = np.array([-math.sin(angle), 0, math.cos(angle)])
        ids = []
        for sx, sy in ((-1, 0), (1, 0), (1, 1), (-1, 1)):
            p = a * sx + np.array([0, height * sy - .02, 0])
            normal = np.array([0, 1.0, 0]) * .75 + facing * .25
            u = ((sx * .5 + .5) * .96 + .02) * .5 + cell * .5
            v = .99 - .98 * sy
            ids.append(builder.vertex(p, normal, (u, v), .55 + .45 * sy))
        builder.triangle(ids[0], ids[1], ids[2])
        builder.triangle(ids[0], ids[2], ids[3])
    write_gltf(name, [("Grass", builder)])


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    bake_leaves()
    bake_bark()
    bake_grass()
    sizes = {
        "tree_oak": grow_tree("tree_oak", 101, 3.0, 8.4, 6.6, 4.4, 9, 2200, 760, (1.1, 1.6), .42),
        "tree_elm": grow_tree("tree_elm", 102, 4.2, 11.0, 5.0, 6.4, 9, 2200, 760, (1.1, 1.6), .38),
        "tree_round": grow_tree("tree_round", 103, 2.6, 6.6, 4.8, 4.0, 7, 1700, 560, (1.0, 1.5), .32),
        "tree_young": grow_tree("tree_young", 104, 2.0, 4.8, 3.0, 2.9, 6, 1000, 320, (.8, 1.2), .18, lean=.25),
    }
    bush("bush_green", 201, 5, .9, 220, [(0, 1)])
    bush("bush_flowers", 202, 5, .85, 220, [(1, 1), (0, 1), (1, 1)])
    tuft("tuft_short", 0, .55, .42)
    tuft("tuft_tall", 1, .5, .75)
    (OUT / "heights.json").write_text(json.dumps({k: round(v, 2) for k, v in sizes.items()}, indent=1), encoding="utf-8")
