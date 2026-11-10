"""Painted VFX textures: flipbook atlases and decals for the ability and proc art.

The effects used to be built from two procedurally generated 64 px dots - one
soft circle for sparks, one noisy blob for smoke - which is why fire read as a
ring of orange dots and a ward read as a hoop of boxes. This module paints the
real thing: flame and smoke as animated flipbooks, sparks and embers as an atlas
of distinct shapes, and the decals (crescent, shock ring, rune ring, splat,
blade glint) as single images the effects can lay down.

Everything here is generated: value noise, radial fields, shape masks and a
colour ramp per texture. Same file, same pixels, on every machine. The palette
follows the game: ember orange into white hot, cold steel, bone green, blood.

Usage:
    python tools/fx_textures.py
    python tools/fx_textures.py --sheet        # a contact sheet for review
    python tools/fx_textures.py --fix-imports  # set mipmaps + no VRAM compress

Output (assets/vfx/):
    flame_8x1.png     8 frames x 128   fire plume, white-hot base
    smoke_8x1.png     8 frames x 128   rolling smoke
    spark_4x4.png     4x4 x 64         ember / glint / ash / chip / drop
    crescent.png      512 x 256        tapered blade crescent
    glint.png         512 x 256        upright swing streak
    shock_ring.png    512 x 512        force ring
    rune_ring.png     512 x 512        ward rune circle
    splat.png         256 x 256        blood splat
    vfx_textures.json                  manifest
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "vfx"

FRAME = 128
FRAMES = 8


# --- noise ------------------------------------------------------------------

def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(0xF1A3E ^ (seed * 7919))


def value_noise(width: int, height: int, cells: int, seed: int) -> np.ndarray:
    grid = rng(seed).random((max(2, cells) + 3, max(2, cells) + 3)).astype(np.float32)
    layer = Image.fromarray((grid * 255).astype(np.uint8), "L")
    layer = layer.resize((width, height), Image.BICUBIC)
    return np.asarray(layer, dtype=np.float32) / 255.0


def fbm(width: int, height: int, seed: int, cells: int = 6, octaves: int = 4,
        persistence: float = 0.55, stretch: float = 1.0) -> np.ndarray:
    total = np.zeros((height, width), dtype=np.float32)
    norm = 0.0
    amp = 1.0
    c = max(2, cells)
    for octave in range(octaves):
        layer = value_noise(width, max(2, int(height / max(stretch, 0.01))), c,
                            seed + octave * 131)
        if layer.shape[0] != height:
            layer = cv2.resize(layer, (width, height), interpolation=cv2.INTER_LINEAR)
        total += amp * layer
        norm += amp
        amp *= persistence
        c = max(2, int(round(c * 2.0)))
    return total / max(norm, 1e-6)


def domain_warp(field: np.ndarray, amount: float, seed: int) -> np.ndarray:
    """Push a field around with two noise channels: curls and torn edges."""
    h, w = field.shape
    dx = (fbm(w, h, seed + 17, cells=4) - 0.5) * 2.0 * amount
    dy = (fbm(w, h, seed + 29, cells=4) - 0.5) * 2.0 * amount
    grid_x, grid_y = np.meshgrid(np.arange(w, dtype=np.float32),
                                 np.arange(h, dtype=np.float32))
    return cv2.remap(field, grid_x + dx, grid_y + dy, cv2.INTER_LINEAR,
                     borderMode=cv2.BORDER_REPLICATE)


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def radial(height: int, width: int, cx: float, cy: float, rx: float,
           ry: float) -> np.ndarray:
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    return np.sqrt(((xs - cx) / max(rx, 1e-3)) ** 2 +
                   ((ys - cy) / max(ry, 1e-3)) ** 2)


# --- colour ramp ------------------------------------------------------------

def ramp(value: np.ndarray, stops: list[tuple[float, tuple[float, float, float]]]
         ) -> np.ndarray:
    """Map 0..1 to RGB through the given stops."""
    out = np.zeros(value.shape + (3,), dtype=np.float32)
    for channel in range(3):
        points = [s[0] for s in stops]
        colours = [s[1][channel] for s in stops]
        out[..., channel] = np.interp(value, points, colours)
    return out


def save(path: Path, rgba: np.ndarray) -> None:
    image = Image.fromarray((np.clip(rgba, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8),
                            "RGBA")
    image.save(path, optimize=True)
    print(f"wrote {path.relative_to(ROOT)} {image.size[0]}x{image.size[1]}")


# --- flame and smoke flipbooks ---------------------------------------------

def flame_frames() -> list[np.ndarray]:
    """A plume per frame: tongues wobble, the base stays white-hot."""
    frames = []
    h = w = FRAME
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xs / (w - 1.0)
    v = ys / (h - 1.0)
    for frame in range(FRAMES):
        phase = frame / FRAMES * math.tau
        warp = fbm(w, h, seed=500 + frame * 7, cells=4, octaves=4, stretch=0.55)
        warp = domain_warp(warp, 6.0 + 1.5 * math.sin(phase), 900 + frame)

        # Three licking tongues of different heights, each waving on its own phase.
        plume = np.zeros((h, w), dtype=np.float32)
        for index, (cx, height, spread, speed) in enumerate((
                (0.50, 0.94, 0.30, 1.0), (0.38, 0.66, 0.20, -0.7),
                (0.63, 0.74, 0.22, 0.5))):
            sway = 0.045 * math.sin(phase * speed + index)
            body = np.clip(1.0 - radial(h * 2, w, cx * w + sway * w, h * 2,
                                         spread * w, height * h * 2), 0.0, 1.0)
            body = body ** 0.7
            plume = np.maximum(plume, body[0:h, :])
        # The core is narrower and hotter than the body.
        core = np.clip(1.0 - radial(h * 2, w, 0.50 * w, h * 2, 0.16 * w, 0.42 * h * 2),
                       0.0, 1.0) ** 0.8
        core = core[0:h, :]
        energy = np.clip(plume * (0.55 + 0.75 * warp), 0.0, 1.0)
        energy = np.clip(energy + core * 0.55 * (1.0 - v) ** 0.5, 0.0, 1.0)
        energy *= smoothstep(0.02, 0.22, v) ** 0.35
        alpha = np.clip(energy * 1.25 - 0.10, 0.0, 1.0) * smoothstep(0.0, 0.12, v)

        colour = ramp(np.clip(energy * 1.15, 0.0, 1.0), [
            (0.00, (0.30, 0.02, 0.01)),
            (0.22, (0.72, 0.09, 0.02)),
            (0.48, (1.00, 0.34, 0.04)),
            (0.72, (1.00, 0.68, 0.18)),
            (0.90, (1.00, 0.94, 0.72)),
            (1.00, (1.00, 1.00, 0.96)),
        ])
        # The base is opaque, the tips dissolve: additive blending needs the alpha
        # to fall off much faster than the colour does.
        rgba = np.dstack([colour, alpha])
        frames.append(rgba)
    return frames


def smoke_frames() -> list[np.ndarray]:
    frames = []
    h = w = FRAME
    for frame in range(FRAMES):
        phase = frame / FRAMES * math.tau
        base = fbm(w, h, seed=1400 + frame * 11, cells=3, octaves=5,
                   persistence=0.62)
        base = domain_warp(base, 10.0, 1700 + frame)
        cloud = np.clip(1.0 - radial(h, w, 0.50 * w, 0.56 * h, 0.46 * w, 0.42 * h),
                        0.0, 1.0) ** 0.8
        density = np.clip((base - 0.28) * 2.1, 0.0, 1.0) * cloud
        density *= 0.75 + 0.25 * math.sin(phase)
        alpha = np.clip(density * 1.35, 0.0, 0.85)
        shade = 0.55 + 0.45 * density
        colour = np.dstack([shade * 0.62, shade * 0.64, shade * 0.70])
        frames.append(np.dstack([colour, alpha]))
    return frames


# --- spark atlas -------------------------------------------------------------

def spark_atlas() -> np.ndarray:
    tile = 64
    atlas = np.zeros((tile * 4, tile * 4, 4), dtype=np.float32)
    ys, xs = np.mgrid[0:tile, 0:tile].astype(np.float32)
    cx = cy = (tile - 1) * 0.5
    for index in range(16):
        row, column = divmod(index, 4)
        kind = index % 4
        if kind == 0:  # ember: a hot round seed with a soft halo
            r = radial(tile, tile, cx, cy, tile * 0.20, tile * 0.20)
            core = np.clip(1.0 - r, 0.0, 1.0) ** 2.2
            halo = np.clip(1.0 - r / 2.2, 0.0, 1.0) ** 3.0
            energy = np.clip(core + halo * 0.5, 0.0, 1.0)
            colour = ramp(energy, [(0.0, (0.9, 0.2, 0.03)), (0.6, (1.0, 0.6, 0.2)),
                                   (1.0, (1.0, 0.98, 0.9))])
            alpha = np.clip(energy * 1.2, 0.0, 1.0)
        elif kind == 1:  # glint: a four-point star
            dx = np.abs(xs - cx) / (tile * 0.46)
            dy = np.abs(ys - cy) / (tile * 0.46)
            star = np.clip(1.0 - (dx ** 0.6 + dy ** 0.6) * 0.5, 0.0, 1.0) ** 2.0
            core = np.clip(1.0 - radial(tile, tile, cx, cy, tile * 0.10,
                                        tile * 0.10), 0.0, 1.0) ** 1.6
            energy = np.clip(star + core, 0.0, 1.0)
            colour = ramp(energy, [(0.0, (0.55, 0.75, 1.0)), (0.7, (0.9, 0.97, 1.0)),
                                   (1.0, (1.0, 1.0, 1.0))])
            alpha = np.clip(energy * 1.3, 0.0, 1.0)
        elif kind == 2:  # ash flake: an irregular chip
            noise = fbm(tile, tile, seed=210 + index, cells=5, octaves=3)
            flake = np.clip(1.0 - radial(tile, tile, cx, cy, tile * 0.26,
                                         tile * 0.34), 0.0, 1.0)
            flake = np.clip((flake * 1.3 - 0.28) + (noise - 0.5) * 0.9, 0.0, 1.0)
            shade = 0.45 + 0.25 * noise
            colour = np.dstack([shade, shade * 0.97, shade * 0.92])
            alpha = np.clip(flake * 3.0, 0.0, 0.9)
        else:  # chip: a splinter of bone or stone
            angle = 0.6 + index * 0.4
            dx = (xs - cx) * math.cos(angle) + (ys - cy) * math.sin(angle)
            dy = -(xs - cx) * math.sin(angle) + (ys - cy) * math.cos(angle)
            splinter = ((np.abs(dx) < tile * 0.07) &
                        (np.abs(dy) < tile * (0.30 + 0.02 * index))).astype(np.float32)
            splinter = cv2.GaussianBlur(splinter, (0, 0), 1.6)
            shade = 0.80
            colour = np.dstack([shade, shade * 0.95, shade * 0.84]) * np.ones((tile,
                                                                              tile, 3))
            alpha = np.clip(splinter * 1.4, 0.0, 1.0)
        atlas[row * tile:(row + 1) * tile, column * tile:(column + 1) * tile] = \
            np.dstack([colour, alpha])
    return atlas


# --- decals -----------------------------------------------------------------

def crescent(width: int = 512, height: int = 256) -> np.ndarray:
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    u = xs / (width - 1.0)
    v = (ys / (height - 1.0)) * 2.0 - 1.0
    # A crescent in the local XZ plane: radius 1, thickness tapering to the tips.
    angle = (u - 0.5) * math.pi * 1.35
    radius = 0.82
    half = 0.30 * (0.25 + 0.75 * np.sin(np.pi * u) ** 0.6)
    dist = np.abs(np.hypot(v / 0.62 - 0.0, (u - 0.5) * 1.0) - radius)
    band = np.clip(1.0 - dist / np.maximum(half, 0.02), 0.0, 1.0)
    band *= np.sin(np.pi * np.clip(u, 0.0, 1.0)) ** 0.35
    glow = cv2.GaussianBlur(band, (0, 0), 9.0) * 0.7
    energy = np.clip(band + glow, 0.0, 1.0)
    colour = ramp(energy, [(0.0, (0.45, 0.68, 1.0)), (0.55, (0.82, 0.94, 1.0)),
                           (1.0, (1.0, 1.0, 1.0))])
    return np.dstack([colour, np.clip(energy * 1.1, 0.0, 1.0)])


def glint(width: int = 512, height: int = 256) -> np.ndarray:
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    u = xs / (width - 1.0)
    v = (ys / (height - 1.0)) * 2.0 - 1.0
    # An upright swing: a lens-shaped streak whose ends are cut on the diagonal.
    body = np.clip(1.0 - np.abs(v) / (0.16 + 0.5 * u), 0.0, 1.0) ** 0.8
    body *= smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.72, 1.0, u))
    core = np.clip(1.0 - np.abs(v) / 0.05, 0.0, 1.0) ** 1.4
    core *= smoothstep(0.0, 0.10, u) * (1.0 - smoothstep(0.55, 0.95, u))
    energy = np.clip(body * 0.85 + core, 0.0, 1.0)
    colour = ramp(energy, [(0.0, (0.55, 0.78, 1.0)), (0.6, (0.88, 0.96, 1.0)),
                           (1.0, (1.0, 1.0, 1.0))])
    return np.dstack([colour, np.clip(energy * 1.15, 0.0, 1.0)])


def shock_ring(size: int = 512) -> np.ndarray:
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = (size - 1) * 0.5
    angle = np.arctan2(ys - cy, xs - cx)
    radius = np.hypot(xs - cx, ys - cy) / (size * 0.5)
    wobble = 0.012 * np.sin(angle * 9.0) + 0.008 * np.sin(angle * 17.0 + 1.3)
    ring = np.clip(1.0 - np.abs(radius - (0.78 + wobble)) / 0.055, 0.0, 1.0) ** 1.6
    echo = np.clip(1.0 - np.abs(radius - (0.70 + wobble)) / 0.020, 0.0, 1.0) * 0.5
    glow = cv2.GaussianBlur(ring, (0, 0), 14.0) * 0.8
    energy = np.clip(ring + echo + glow, 0.0, 1.0)
    colour = ramp(energy, [(0.0, (0.60, 0.42, 0.20)), (0.55, (1.0, 0.78, 0.40)),
                           (1.0, (1.0, 0.98, 0.90))])
    return np.dstack([colour, np.clip(energy * 1.1, 0.0, 1.0)])


def rune_ring(size: int = 512, count: int = 12) -> np.ndarray:
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = (size - 1) * 0.5
    canvas = np.zeros((size, size), dtype=np.float32)
    angle = np.arctan2(ys - cy, xs - cx)
    radius = np.hypot(xs - cx, ys - cy) / (size * 0.5)
    thin = np.clip(1.0 - np.abs(radius - 0.86) / 0.010, 0.0, 1.0)
    canvas = np.maximum(canvas, thin)
    inner = np.clip(1.0 - np.abs(radius - 0.62) / 0.007, 0.0, 1.0) * 0.7
    canvas = np.maximum(canvas, inner)
    # Rune blocks: three strokes each, deterministic per seat.
    for index in range(count):
        seat = index / count * math.tau + 0.13
        strokes = rng(700 + index).integers(-1, 2, size=(3, 2))
        for stroke in strokes:
            width = 0.055
            t = (angle - seat + math.pi) % math.tau - math.pi
            along = np.abs(t) < width * 0.5
            radial_band = (radius > 0.68) & (radius < 0.80)
            block = (along & radial_band).astype(np.float32)
            dx = float(stroke[0]) * 0.05
            dy = float(stroke[1]) * 0.06
            shifted = cv2.warpAffine(block, np.float32([[1, 0, dx * size / 8],
                                                       [0, 1, dy * size / 8]]),
                                     (size, size))
            canvas = np.maximum(canvas, shifted * 0.95)
    glow = cv2.GaussianBlur(canvas, (0, 0), 10.0) * 0.55
    energy = np.clip(canvas + glow, 0.0, 1.0)
    colour = ramp(energy, [(0.0, (0.35, 0.85, 0.75)), (0.6, (0.60, 1.0, 0.90)),
                           (1.0, (1.0, 1.0, 1.0))])
    return np.dstack([colour, np.clip(energy * 1.05, 0.0, 1.0)])


def splat(size: int = 256) -> np.ndarray:
    base = np.zeros((size, size), dtype=np.float32)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    r = radial(size, size, 0.5 * size, 0.52 * size, 0.26 * size, 0.24 * size)
    blob = np.clip(1.0 - r, 0.0, 1.0) ** 0.7
    noise = fbm(size, size, seed=3300, cells=5, octaves=4)
    blob *= 0.65 + 0.7 * noise
    base = np.maximum(base, np.clip(blob * 1.6 - 0.25, 0.0, 1.0))
    for index in range(14):
        seat = rng(3400 + index)
        angle = seat.random() * math.tau
        distance = 0.30 + seat.random() * 0.16
        px = (0.5 + math.cos(angle) * distance) * size
        py = (0.52 + math.sin(angle) * distance * 0.9) * size
        radius = (0.010 + seat.random() * 0.026) * size
        drop = np.clip(1.0 - radial(size, size, px, py, radius, radius * (0.8 + 0.6 *
                                                                        seat.random())),
                       0.0, 1.0) ** 0.7
        base = np.maximum(base, drop)
    edge = cv2.GaussianBlur(base, (0, 0), 1.6)
    energy = np.clip(edge, 0.0, 1.0)
    colour = ramp(energy, [(0.0, (0.30, 0.01, 0.01)), (0.55, (0.62, 0.05, 0.04)),
                           (1.0, (0.86, 0.14, 0.08))])
    alpha = np.clip(energy * 1.4, 0.0, 0.95)
    return np.dstack([colour, alpha])


# --- packing ----------------------------------------------------------------

def flipbook(frames: list[np.ndarray]) -> np.ndarray:
    height = frames[0].shape[0]
    return np.concatenate(frames, axis=1)


MANIFEST = [
    ("flame_8x1.png", "flame", 8, 1, "fire plume flipbook, white-hot base"),
    ("smoke_8x1.png", "smoke", 8, 1, "rolling smoke flipbook"),
    ("spark_4x4.png", "spark", 4, 4, "ember, glint, ash, chip"),
    ("crescent.png", "crescent", 1, 1, "tapered blade crescent"),
    ("glint.png", "glint", 1, 1, "upright swing streak"),
    ("shock_ring.png", "shock_ring", 1, 1, "force ring"),
    ("rune_ring.png", "rune_ring", 1, 1, "ward rune circle"),
    ("splat.png", "splat", 1, 1, "blood splat"),
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sheet", action="store_true")
    parser.add_argument("--fix-imports", action="store_true")
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    save(OUT / "flame_8x1.png", flipbook(flame_frames()))
    save(OUT / "smoke_8x1.png", flipbook(smoke_frames()))
    save(OUT / "spark_4x4.png", spark_atlas())
    save(OUT / "crescent.png", crescent())
    save(OUT / "glint.png", glint())
    save(OUT / "shock_ring.png", shock_ring())
    save(OUT / "rune_ring.png", rune_ring())
    save(OUT / "splat.png", splat())

    manifest = {
        "generator": "tools/fx_textures.py",
        "license": "CC BY-NC-SA 4.0 (section 3 of LICENSE.md)",
        "textures": [
            {"file": name, "id": ident, "h_frames": h, "v_frames": v, "use": use}
            for name, ident, h, v, use in MANIFEST
        ],
    }
    (OUT / "vfx_textures.json").write_text(json.dumps(manifest, indent=2) + "\n",
                                           encoding="utf-8")
    print(f"wrote {OUT / 'vfx_textures.json'}")

    if args.sheet:
        tiles = []
        for name, _, _, _, _ in MANIFEST:
            with Image.open(OUT / name) as image:
                sheet = image.convert("RGB")
                sheet.thumbnail((512, 512), Image.LANCZOS)
                tiles.append(sheet)
        width = max(t.width for t in tiles)
        height = sum(t.height + 8 for t in tiles)
        contact = Image.new("RGB", (width, height), (14, 18, 20))
        y = 0
        for tile in tiles:
            contact.paste(tile, (0, y))
            y += tile.height + 8
        contact.save(ROOT.parent / "vfx_textures_sheet.png")
        print("wrote contact sheet")

    if args.fix_imports:
        for name, _, _, _, _ in MANIFEST:
            import_file = OUT / f"{name}.import"
            if not import_file.exists():
                print(f"skip {name}.import (import in the editor first)")
                continue
            text = import_file.read_text(encoding="utf-8")
            text = text.replace("mipmaps/generate=false", "mipmaps/generate=true")
            text = text.replace("detect_3d/compress_to=1", "detect_3d/compress_to=0")
            import_file.write_text(text, encoding="utf-8")
            print(f"fixed {name}.import")


if __name__ == "__main__":
    main()
