"""The ability icon forge: production glyphs rendered from distance fields.

The first icon set was drawn with PIL polygons, which is fine for a placeholder
and not fine for a game: flat fills have no form, so a blade read as a gold
arrow and a ward read as a ring of light. This module renders each icon the way a
painted icon is really made - a silhouette with a bevel, lit from one direction,
over a material that has grain in it - and does it deterministically from signed
distance fields so every edge stays crisp at any size.

The pipeline, per icon:

    compose()  ->  list[Layer]            shapes, in back-to-front order
    render()   ->  float32 RGBA at 1024   shaded, composited
    save()     ->  256 px PNG             Lanczos + a last sharpen

A `Layer` is a distance field plus a `Material`. Shading is computed from the
distance field itself: the bevel height, its normal, ambient occlusion in the
crevices, a Blinn-Phong specular lobe, a Fresnel rim, anisotropic grain in the
albedo, emissive cores with their own bloom, and an ink contour that keeps the
silhouette readable on a bright tile as well as a dark one.

Everything is generated: no downloaded art, one fixed light, seeded noise. The
same file produces the same pixels on every machine.

Usage:
    python tools/icon_forge.py                # all icons
    python tools/icon_forge.py --only fireball,dash
    python tools/icon_forge.py --sheet        # plus an 8x5 contact sheet
    python tools/icon_forge.py --preview 26   # plus a 26 px legibility strip
"""
from __future__ import annotations

import argparse
import math
import zlib
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ui" / "abilities"
MASTER = Path(__file__).resolve().parent.parent / ".runtime" / "icon-masters"

# --- canvas ----------------------------------------------------------------

SIZE = 1024
MASTER_SIZE = 512
SHIPPED = 256
SS = 2                     # polygon rasterisation supersample before the EDT

# --- the one light in the room --------------------------------------------

# Warm key from the upper left, cool fill from the lower right: the oldest trick
# in painting, and the reason a steel edge and a gold guard can both read as
# themselves in the same picture instead of averaging to the same grey.
LIGHT = np.array([-0.52, -0.85, 0.46], dtype=np.float32)
LIGHT /= np.linalg.norm(LIGHT)
FILL = np.array([0.62, 0.66, 0.30], dtype=np.float32)
FILL /= np.linalg.norm(FILL)
VIEW = np.array([0.0, 0.0, 1.0], dtype=np.float32)
HALF = (LIGHT + VIEW)
HALF /= np.linalg.norm(HALF)
KEY_COLOUR = np.array([1.00, 0.93, 0.82], dtype=np.float32)
FILL_COLOUR = np.array([0.34, 0.48, 0.80], dtype=np.float32)


# --- noise ------------------------------------------------------------------

def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(0xB100D ^ (seed * 7919))


def value_noise(size: int, cells: int, seed: int) -> np.ndarray:
    """Smooth value noise in 0..1, `cells` lattice cells across the canvas."""
    grid = _rng(seed).random((cells + 3, cells + 3), dtype=np.float32)
    layer = Image.fromarray((grid * 255).astype(np.uint8), "L")
    layer = layer.resize((size, size), Image.BICUBIC)
    return np.asarray(layer, dtype=np.float32) / 255.0


def fbm(size: int, seed: int, cells: int = 12, octaves: int = 4,
        persistence: float = 0.5) -> np.ndarray:
    total = np.zeros((size, size), dtype=np.float32)
    norm = 0.0
    amp = 1.0
    c = max(2, cells)
    for octave in range(octaves):
        total += amp * value_noise(size, c, seed + octave * 101)
        norm += amp
        amp *= persistence
        c = max(2, int(round(c * 2.0)))
    return total / max(norm, 1e-6)


_STREAK_CACHE: dict[tuple[int, str], np.ndarray] = {}


def streaks(size: int, seed: int, direction: str = "y",
            cells: int = 90) -> np.ndarray:
    """Brushed-metal grain: noise stretched along one axis. Cached: a material's
    grain is the same field whichever shape wears it."""
    key = (seed, direction)
    if key in _STREAK_CACHE:
        return _STREAK_CACHE[key]
    grid = _rng(seed).random((cells + 3, cells + 3), dtype=np.float32)
    layer = Image.fromarray((grid * 255).astype(np.uint8), "L")
    if direction == "y":
        layer = layer.resize((size // 24, size), Image.BICUBIC)
    else:
        layer = layer.resize((size, size // 24), Image.BICUBIC)
    if layer.size != (size, size):
        layer = layer.resize((size, size), Image.BICUBIC)
    field = np.asarray(layer, dtype=np.float32) / 255.0
    _STREAK_CACHE[key] = field
    return field


def blur(field: np.ndarray, sigma: float) -> np.ndarray:
    if sigma <= 0.0:
        return field
    return cv2.GaussianBlur(field, (0, 0), sigma, borderType=cv2.BORDER_REPLICATE)


# --- distance fields --------------------------------------------------------
#
# Convention: positive inside the shape, in pixels of the 1024 canvas. Every
# primitive returns float32 (SIZE, SIZE).

YA, XA = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)


def sdf_circle(cx: float, cy: float, radius: float) -> np.ndarray:
    return radius - np.hypot(XA - cx, YA - cy)


def sdf_ellipse(cx: float, cy: float, rx: float, ry: float,
                rot: float = 0.0) -> np.ndarray:
    cos, sin = math.cos(rot), math.sin(rot)
    x = (XA - cx) * cos + (YA - cy) * sin
    y = -(XA - cx) * sin + (YA - cy) * cos
    k = np.sqrt((x / rx) ** 2 + (y / ry) ** 2)
    return (1.0 - k) * min(rx, ry)


def sdf_capsule(ax: float, ay: float, bx: float, by: float,
                radius: float) -> np.ndarray:
    px, py = XA - ax, YA - ay
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = np.clip((px * dx + py * dy) / max(length2, 1e-6), 0.0, 1.0)
    qx, qy = px - dx * t, py - dy * t
    return radius - np.hypot(qx, qy)


def sdf_taper(ax: float, ay: float, bx: float, by: float, ra: float,
              rb: float) -> np.ndarray:
    """A capsule whose radius runs from `ra` at A to `rb` at B."""
    px, py = XA - ax, YA - ay
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = np.clip((px * dx + py * dy) / max(length2, 1e-6), 0.0, 1.0)
    qx, qy = px - dx * t, py - dy * t
    return ra + (rb - ra) * t - np.hypot(qx, qy)


def sdf_arc(cx: float, cy: float, radius: float, half_width: float,
            start: float, end: float) -> np.ndarray:
    """A swept band: the distance to an arc, with round caps at both ends."""
    px, py = XA - cx, YA - cy
    dist = np.hypot(px, py)
    angle = np.arctan2(py, px)
    span = (end - start) % (2.0 * math.pi)
    rel = (angle - start) % (2.0 * math.pi)
    inside_sweep = rel <= span
    best = np.empty_like(dist)
    # Radial distance when the point projects inside the sweep.
    radial = half_width - np.abs(dist - radius)
    # Otherwise the distance to whichever end cap is nearer.
    a0 = np.array([cx + math.cos(start), cy + math.sin(start)], dtype=np.float32)
    a1 = np.array([cx + math.cos(end), cy + math.sin(end)], dtype=np.float32)
    cap0 = half_width - np.hypot(XA - a0[0], YA - a0[1])
    cap1 = half_width - np.hypot(XA - a1[0], YA - a1[1])
    best = np.where(inside_sweep, radial, np.maximum(cap0, cap1))
    return best


def sdf_polygon(points, smooth: float = 0.0) -> np.ndarray:
    """Filled polygon -> signed distance, via a supersampled raster and an EDT."""
    canvas = np.zeros((SIZE * SS, SIZE * SS), np.uint8)
    pts = (np.asarray(points, dtype=np.float32) * SS).astype(np.int32)
    cv2.fillPoly(canvas, [pts], 255, lineType=cv2.LINE_AA)
    mask = canvas.astype(np.float32) / 255.0
    inside = cv2.distanceTransform((canvas > 127).astype(np.uint8), cv2.DIST_L2, 5)
    outside = cv2.distanceTransform(1 - (canvas > 127).astype(np.uint8), cv2.DIST_L2, 5)
    sd = (inside - outside) / SS
    sd = cv2.resize(sd, (SIZE, SIZE), interpolation=cv2.INTER_LINEAR)
    if smooth > 0.0:
        sd = blur(sd, smooth)
    return sd.astype(np.float32)


def sdf_box(cx: float, cy: float, hw: float, hh: float, rot: float = 0.0) -> np.ndarray:
    cos, sin = math.cos(rot), math.sin(rot)
    x = np.abs((XA - cx) * cos + (YA - cy) * sin) - hw
    y = np.abs(-(XA - cx) * sin + (YA - cy) * cos) - hh
    outside = np.hypot(np.maximum(x, 0.0), np.maximum(y, 0.0))
    return -(outside + np.minimum(np.maximum(x, y), 0.0))


def sdf_shift(field: np.ndarray, dx: float, dy: float) -> np.ndarray:
    """Translate a field by (dx, dy) pixels without resampling error."""
    transform = np.float32([[1.0, 0.0, dx], [0.0, 1.0, dy]])
    return cv2.warpAffine(field, transform, (SIZE, SIZE), flags=cv2.INTER_LINEAR,
                          borderMode=cv2.BORDER_REPLICATE)


def sdf_rotate(field: np.ndarray, angle: float, cx: float = SIZE * 0.5,
               cy: float = SIZE * 0.5) -> np.ndarray:
    rot = cv2.getRotationMatrix2D((cx, cy), math.degrees(angle), 1.0)
    return cv2.warpAffine(field, rot, (SIZE, SIZE), flags=cv2.INTER_LINEAR,
                          borderMode=cv2.BORDER_CONSTANT, borderValue=-4000.0)


def sdf_tapered_arc(center: tuple[float, float], radius: float,
                    width_start: float, width_end: float, start: float,
                    end: float, steps: int = 96) -> np.ndarray:
    """A crescent whose band thickens along the sweep: a swing, not a hoop.

    Built as a polygon from `steps` samples of the outer edge and back along the
    inner one, so the taper and the round ends are exact and the SDF stays
    crisp. `start`/`end` are radians.
    """
    cx, cy = center
    outer, inner = [], []
    for index in range(steps + 1):
        k = index / steps
        angle = start + (end - start) * k
        half = (width_start + (width_end - width_start) * k) * 0.5
        taper = math.sin(math.pi * min(1.0, max(0.0, k))) ** 0.45
        r = radius + half * taper
        outer.append((cx + math.cos(angle) * r, cy + math.sin(angle) * r))
        r = radius - half * taper
        inner.append((cx + math.cos(angle) * r, cy + math.sin(angle) * r))
    return sdf_polygon(outer + inner[::-1])


def sdf_union(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.maximum(a, b)


def sdf_subtract(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.minimum(a, -b)


def sdf_smooth_union(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    h = np.clip(0.5 + 0.5 * (b - a) / max(k, 1e-4), 0.0, 1.0)
    return b * (1.0 - h) + a * h + k * h * (1.0 - h)


# --- materials --------------------------------------------------------------
#
# A material is data, not a shader: albedo gradient stops, roughness, how metal
# it is, how much grain and in which direction, whether it emits, and the ink it
# is outlined with. Adding a material is one dictionary.

MATERIALS = {
    "steel": {
        "body": (0.84, 0.89, 0.95), "edge": (1.00, 1.00, 1.00), "core": (0.34, 0.39, 0.48),
        "rough": 0.30, "metal": 0.92, "grain": 0.055, "grain_dir": "y",
        "spec": 1.15, "rim": 0.85, "ink": (0.07, 0.09, 0.12),
        "bevel": 26.0, "depth": 1.0,
    },
    "steel_dark": {
        "body": (0.44, 0.49, 0.56), "edge": (0.80, 0.86, 0.94), "core": (0.20, 0.24, 0.30),
        "rough": 0.42, "metal": 0.90, "grain": 0.07, "grain_dir": "y",
        "spec": 0.9, "rim": 0.7, "ink": (0.05, 0.06, 0.09),
        "bevel": 24.0, "depth": 1.0,
    },
    "gold": {
        "body": (0.80, 0.58, 0.22), "edge": (1.00, 0.93, 0.70), "core": (0.44, 0.27, 0.07),
        "rough": 0.36, "metal": 0.88, "grain": 0.06, "grain_dir": "x",
        "spec": 1.25, "rim": 0.7, "ink": (0.16, 0.09, 0.02),
        "bevel": 24.0, "depth": 1.0,
    },
    "brass_dark": {
        "body": (0.52, 0.38, 0.16), "edge": (0.86, 0.70, 0.40), "core": (0.24, 0.16, 0.06),
        "rough": 0.44, "metal": 0.85, "grain": 0.05, "grain_dir": "x",
        "spec": 1.0, "rim": 0.6, "ink": (0.12, 0.07, 0.02),
        "bevel": 22.0, "depth": 1.0,
    },
    "iron": {
        "body": (0.30, 0.31, 0.33), "edge": (0.62, 0.64, 0.68), "core": (0.12, 0.13, 0.15),
        "rough": 0.55, "metal": 0.75, "grain": 0.09, "grain_dir": "x",
        "spec": 0.7, "rim": 0.5, "ink": (0.04, 0.05, 0.06),
        "bevel": 24.0, "depth": 1.0,
    },
    "leather": {
        "body": (0.16, 0.10, 0.07), "edge": (0.34, 0.22, 0.14), "core": (0.11, 0.07, 0.05),
        "rough": 0.78, "metal": 0.0, "grain": 0.14, "grain_dir": "y",
        "spec": 0.25, "rim": 0.25, "ink": (0.05, 0.03, 0.02),
        "bevel": 20.0, "depth": 1.0,
    },
    "bone": {
        "body": (0.78, 0.80, 0.68), "edge": (1.00, 1.00, 0.92), "core": (0.46, 0.49, 0.41),
        "rough": 0.62, "metal": 0.0, "grain": 0.10, "grain_dir": "y",
        "spec": 0.42, "rim": 0.45, "ink": (0.10, 0.12, 0.09),
        "bevel": 22.0, "depth": 0.9,
    },
    "stone": {
        "body": (0.40, 0.39, 0.37), "edge": (0.68, 0.66, 0.62), "core": (0.18, 0.18, 0.18),
        "rough": 0.86, "metal": 0.0, "grain": 0.16, "grain_dir": "x",
        "spec": 0.2, "rim": 0.3, "ink": (0.05, 0.05, 0.05),
        "bevel": 18.0, "depth": 1.0,
    },
    "ash": {
        "body": (0.46, 0.44, 0.41), "edge": (0.74, 0.71, 0.66), "core": (0.22, 0.22, 0.21),
        "rough": 0.80, "metal": 0.0, "grain": 0.12, "grain_dir": "y",
        "spec": 0.28, "rim": 0.32, "ink": (0.06, 0.06, 0.06),
        "bevel": 18.0, "depth": 0.9,
    },
    "ember": {
        "body": (0.95, 0.28, 0.06), "edge": (1.00, 0.78, 0.30), "core": (0.70, 0.12, 0.02),
        "rough": 0.45, "metal": 0.0, "grain": 0.05, "grain_dir": "y",
        "spec": 0.5, "rim": 0.9, "ink": (0.22, 0.05, 0.01),
        "emissive": (1.0, 0.62, 0.22), "emissive_strength": 0.55,
        "bevel": 18.0, "depth": 0.8,
    },
    "ember_hot": {
        "body": (1.00, 0.72, 0.28), "edge": (1.00, 0.97, 0.86), "core": (1.00, 0.44, 0.10),
        "rough": 0.35, "metal": 0.0, "grain": 0.03, "grain_dir": "y",
        "spec": 0.6, "rim": 1.0, "ink": (0.25, 0.08, 0.02),
        "emissive": (1.0, 0.86, 0.56), "emissive_strength": 1.05,
        "bevel": 16.0, "depth": 0.7,
    },
    "cinder": {
        "body": (0.42, 0.08, 0.04), "edge": (0.86, 0.26, 0.08), "core": (0.24, 0.05, 0.03),
        "rough": 0.62, "metal": 0.0, "grain": 0.10, "grain_dir": "y",
        "spec": 0.35, "rim": 0.5, "ink": (0.10, 0.02, 0.01),
        "emissive": (0.85, 0.22, 0.08), "emissive_strength": 0.30,
        "bevel": 18.0, "depth": 0.85,
    },
    "teal": {
        "body": (0.20, 0.56, 0.50), "edge": (0.66, 0.95, 0.86), "core": (0.12, 0.38, 0.36),
        "rough": 0.40, "metal": 0.1, "grain": 0.05, "grain_dir": "y",
        "spec": 0.7, "rim": 0.8, "ink": (0.04, 0.16, 0.15),
        "emissive": (0.42, 0.86, 0.76), "emissive_strength": 0.34,
        "bevel": 20.0, "depth": 0.9,
    },
    "teal_dark": {
        "body": (0.09, 0.28, 0.26), "edge": (0.28, 0.55, 0.50), "core": (0.05, 0.18, 0.17),
        "rough": 0.55, "metal": 0.1, "grain": 0.06, "grain_dir": "y",
        "spec": 0.45, "rim": 0.5, "ink": (0.02, 0.09, 0.08),
        "bevel": 18.0, "depth": 0.9,
    },
    "rot": {
        "body": (0.14, 0.30, 0.12), "edge": (0.44, 0.72, 0.30), "core": (0.08, 0.20, 0.08),
        "rough": 0.50, "metal": 0.0, "grain": 0.09, "grain_dir": "y",
        "spec": 0.4, "rim": 0.55, "ink": (0.03, 0.09, 0.02),
        "emissive": (0.34, 0.62, 0.20), "emissive_strength": 0.28,
        "bevel": 18.0, "depth": 0.9,
    },
    "lacquer": {
        "body": (0.18, 0.22, 0.27), "edge": (0.46, 0.56, 0.66), "core": (0.07, 0.09, 0.12),
        "rough": 0.34, "metal": 0.30, "grain": 0.03, "grain_dir": "y",
        "spec": 0.85, "rim": 0.9, "ink": (0.02, 0.03, 0.04),
        "bevel": 34.0, "depth": 0.7,
    },
    "blood": {
        "body": (0.34, 0.03, 0.03), "edge": (0.86, 0.14, 0.10), "core": (0.18, 0.02, 0.02),
        "rough": 0.42, "metal": 0.05, "grain": 0.06, "grain_dir": "y",
        "spec": 0.75, "rim": 0.6, "ink": (0.08, 0.01, 0.01),
        "bevel": 18.0, "depth": 0.85,
    },
}


class Layer:
    """One shape, its material, and the shading knobs that are not material."""

    __slots__ = ("sdf", "material", "bevel", "depth", "grain", "alpha", "grooves",
                 "gradient", "bloom", "outline", "offset")

    def __init__(self, sdf: np.ndarray, material: str = "steel", *,
                 bevel: float | None = None, depth: float = 1.0,
                 grain: float = 1.0, alpha: float = 1.0,
                 grooves: list[np.ndarray] | None = None,
                 gradient: tuple[float, float] | None = None,
                 bloom: bool = True, outline: float = 1.0,
                 offset: tuple[float, float] = (0.0, 0.0)):
        self.sdf = sdf
        self.material = material
        self.bevel = bevel
        self.depth = depth
        self.grain = grain
        self.alpha = alpha
        self.grooves = grooves or []
        self.gradient = gradient
        self.bloom = bloom
        self.outline = outline
        self.offset = offset


# --- shading ----------------------------------------------------------------

def _coverage(sd: np.ndarray) -> np.ndarray:
    """Analytic coverage from the distance field: 1 pixel of soft edge."""
    return np.clip(sd + 0.5, 0.0, 1.0)


def _profile(sd: np.ndarray, bevel: float,
             dome: float) -> tuple[np.ndarray, float]:
    """The cross-section of a piece: a beveled edge rising into a lens-shaped body.

    Two terms, because an icon needs both. The edge bevel gives every silhouette a
    lit fold (`sd / bevel`, saturating fast), and the lens gives the flat middle of
    a blade or a plate a real curvature (`sd / medial radius`, saturating only at
    the thickest point). Without the second term the interior is a plateau, its
    normals are all straight at the camera and the piece reads as a sticker - the
    exact failure the first pass had.
    """
    medial = float(np.clip(sd.max(), 5.0, SIZE * 0.34))
    edge = np.clip(sd / max(bevel, 1.0), 0.0, 1.0) ** 0.55
    lens = np.sqrt(np.clip(sd / medial, 0.0, 1.0))
    return (0.42 * edge + 0.58 * lens) * dome, medial


def _normal(height: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Normal of a height field given in pixels-per-pixel slope."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nx = -dx
    ny = -dy
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return nx / length, ny / length, nz / length


def _shade(layer: Layer, seed: int) -> tuple[np.ndarray, np.ndarray]:
    """Render one layer to premultiplied RGB and alpha."""
    spec = MATERIALS[layer.material]
    sd = layer.sdf
    if layer.offset != (0.0, 0.0):
        sd = sdf_shift(sd, layer.offset[0], layer.offset[1])
    bevel = layer.bevel if layer.bevel is not None else float(spec.get("bevel", 24.0))
    cover = _coverage(sd)

    # Height in pixels, so the normal below is a real slope rather than a scaled
    # abstraction: a 4% dome on a 1024 canvas is a 40 px rise, which is what a
    # cast piece of metal in an icon looks like.
    profile, medial = _profile(sd, bevel, layer.depth)
    # A thin blade must not dome as hard as a shield boss: the rise is capped by
    # the piece's own half-thickness, so the light crosses it once, not ten times.
    rise = min(medial * 0.62, SIZE * 0.055)
    height = profile * rise

    # Grooves cut into the surface, then re-derive the height so their walls catch
    # the light: an engraving is geometry, not a painted line.
    for groove in layer.grooves:
        cut = np.clip(groove / max(bevel * 0.5, 1.0), 0.0, 1.0)
        height = height * (1.0 - 0.55 * cut) - cut * SIZE * 0.006
    nx, ny, nz = _normal(height)
    dome_t = np.clip(sd / max(medial, 1.0), 0.0, 1.0)

    # Albedo: a body colour that darkens toward the deepest part of the piece, a
    # dark core in the fuller, and a bright highlight ring riding just inside the
    # silhouette. The ring is what makes a bevel read as a bevel instead of as a
    # gradient, and it is placed in *dome* space so it follows every shape.
    body = np.array(spec["body"], dtype=np.float32)
    edge = np.array(spec["edge"], dtype=np.float32)
    core = np.array(spec["core"], dtype=np.float32)
    highlight = np.exp(-np.square((dome_t - 0.145) / 0.085))
    darken = np.clip(dome_t / 0.75, 0.0, 1.0)[..., None]
    albedo = core + (body - core) * darken
    albedo = albedo + (edge - albedo) * highlight[..., None] * 0.9
    if spec.get("grain", 0.0) > 0.0:
        field = streaks(SIZE, seed, spec.get("grain_dir", "y"))
        amount = spec["grain"] * layer.grain
        albedo *= ((1.0 - amount) + amount * (0.35 + 1.3 * field))[..., None]
    albedo = np.clip(albedo, 0.0, 1.8)

    # Crevice occlusion: the blurred inverse of the coverage, only where the body
    # is low, so a groove darkens and a highlight does not.
    occlusion = 1.0 - 0.75 * blur(1.0 - cover, max(bevel * 0.8, 2.0)) * \
        np.clip(1.0 - dome_t, 0.0, 1.0)
    occlusion = np.clip(occlusion, 0.18, 1.0)

    ndh = np.clip(nx * HALF[0] + ny * HALF[1] + nz * HALF[2], 0.0, 1.0)
    shininess = max(6.0, 120.0 * (1.0 - spec["rough"]))
    glint = spec["spec"] * np.power(ndh, shininess)
    rim = spec["rim"] * np.power(1.0 - np.clip(nz, 0.0, 1.0), 2.2)

    # Metals keep their colour in the highlight and pick up a little of the room
    # in every direction; dielectrics lose the highlight to white and stay dark
    # where the light does not reach. That difference is most of why a gold guard
    # and a leather grip read as different substances.
    metal = float(spec["metal"])
    ndk = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0.0, 1.0)
    ndf = np.clip(nx * FILL[0] + ny * FILL[1] + nz * FILL[2], 0.0, 1.0)
    key = (0.42 + 1.32 * ndk) * (1.0 - 0.10 * metal)
    fill = (0.14 + 0.58 * ndf) * (1.0 - 0.25 * metal)
    illumination = KEY_COLOUR * key[..., None] + FILL_COLOUR * fill[..., None]
    rgb = albedo * illumination * occlusion[..., None]
    tint = albedo * 0.55 + edge * 0.45
    rgb += tint * (glint * occlusion)[..., None] * (1.75 + 1.35 * metal)
    rgb += FILL_COLOUR * (rim * occlusion)[..., None] * (0.32 + 0.55 * metal)

    if "emissive" in spec:
        energy = float(spec.get("emissive_strength", 0.5))
        core = np.clip(dome_t, 0.0, 1.0) ** 1.6
        emissive = np.array(spec["emissive"], dtype=np.float32)
        rgb += emissive * (energy * (0.30 + 1.0 * core))[..., None]

    # A near-black contour under the bevel keeps the silhouette legible on any
    # tile, the way an ink line does in a painted icon.
    if layer.outline > 0.0:
        ink = np.array(spec["ink"], dtype=np.float32)
        # The contour is a narrow dark band *outside* the silhouette only: the
        # distance field is positive inside, so anything that clamps it before
        # taking abs() puts the band across the whole shape and greys it out.
        outside = np.clip(-sd, 0.0, 6.0)
        band = np.where(sd < 0.0, np.exp(-np.square(outside / 2.0)), 0.0)
        band *= layer.outline
        rgb = rgb * (1.0 - 0.55 * band[..., None]) + ink * 0.60 * band[..., None]

    alpha = cover * layer.alpha
    return np.clip(rgb, 0.0, 4.0) * alpha[..., None], alpha


FAMILY_AURA = {
    "steel": (0.36, 0.56, 0.82), "gold": (0.86, 0.62, 0.26),
    "ember": (0.92, 0.34, 0.10), "bone": (0.44, 0.76, 0.50),
    "teal": (0.24, 0.72, 0.66), "ash": (0.52, 0.50, 0.46),
    "blood": (0.70, 0.14, 0.10),
}


def render(layers: list[Layer], seed: int = 0,
           aura: tuple[float, float, float] | None = None) -> Image.Image:
    """Composite the stack into a float buffer and return it as an RGBA image."""
    rgb = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    alpha = np.zeros((SIZE, SIZE), dtype=np.float32)
    bloom = np.zeros((SIZE, SIZE, 3), dtype=np.float32)

    if aura is not None:
        # A soft lit ground, off-centre so the object stands in front of a light
        # rather than on a bubble. It is what gives a bright steel edge something
        # to cut against at 26 px, where every small detail is gone.
        dist = np.hypot((XA - SIZE * 0.52) / (SIZE * 0.46),
                        (YA - SIZE * 0.48) / (SIZE * 0.42))
        falloff = np.clip(1.0 - dist, 0.0, 1.0) ** 1.6
        tint = np.array(aura, dtype=np.float32)
        glow = tint * (falloff * 0.55)[..., None]
        plate = np.clip(1.0 - dist * 1.25, 0.0, 1.0) ** 4.0 * 0.30
        rgb += glow + tint * 0.18 * plate[..., None]
        alpha = np.clip(alpha + (falloff * 0.42 + plate), 0.0, 0.92)

    for index, layer in enumerate(layers):
        colour, cover = _shade(layer, seed * 97 + index * 13)
        if layer.bloom and "emissive" in MATERIALS[layer.material]:
            energy = float(MATERIALS[layer.material].get("emissive_strength", 0.5))
            bloom += colour * (energy * 0.7)
        # Source-over with premultiplied colour.
        rgb = rgb * (1.0 - cover[..., None]) + colour
        alpha = alpha * (1.0 - cover) + cover

    if bloom.any():
        glow = np.stack([blur(bloom[..., c], 26.0) for c in range(3)], axis=-1)
        glow += np.stack([blur(bloom[..., c], 7.0) for c in range(3)], axis=-1) * 0.55
        rgb = rgb + glow * alpha[..., None]

    # A soft contact shadow under the whole glyph: invisible on the dark hotbar,
    # and the reason the icon still sits on the page when the UI is bright.
    if alpha.any():
        shadow = blur(alpha, 16.0)
        shadow = sdf_shift(shadow * 255.0, 5.0, 9.0) / 255.0
        shadow = np.clip(shadow - alpha, 0.0, 1.0) * 0.42
        rgb = rgb * (1.0 - shadow[..., None])
        alpha = np.clip(alpha + shadow, 0.0, 1.0)

    # A whisper of grain over the whole glyph: the last thing that separates a
    # painted icon from a vector export.
    fine = fbm(SIZE, seed + 501, cells=180, octaves=3)
    rgb *= (0.985 + 0.03 * fine)[..., None]

    rgba = np.concatenate([np.clip(rgb, 0.0, 1.0), alpha[..., None]], axis=-1)
    image = Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), "RGBA")
    return image


# --- output -----------------------------------------------------------------

def downsample(image: Image.Image, size: int) -> Image.Image:
    """Lanczos to the shipped size, then a small unsharp to keep the bevels."""
    small = image.resize((size, size), Image.LANCZOS)
    arr = np.asarray(small, dtype=np.float32) / 255.0
    rgb, alpha = arr[..., :3], arr[..., 3:]
    rgb = cv2.GaussianBlur(rgb, (0, 0), 0.6)
    rgb = np.clip(arr[..., :3] * 1.22 - rgb * 0.22, 0.0, 1.0)
    out = np.concatenate([rgb, alpha], axis=-1)
    return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


# --- composition helpers ----------------------------------------------------
#
# Compositions are written in a 0..1 design grid and multiplied by SIZE, so an
# icon is a drawing rather than a pile of pixel constants.

def P(x: float, y: float) -> tuple[float, float]:
    return x * SIZE, y * SIZE


def U(v: float) -> float:
    return v * SIZE


def poly(*pairs: tuple[float, float]) -> np.ndarray:
    return sdf_polygon([P(x, y) for x, y in pairs])


def cap(a: tuple[float, float], b: tuple[float, float], r: float) -> np.ndarray:
    ax, ay = P(*a)
    bx, by = P(*b)
    return sdf_capsule(ax, ay, bx, by, U(r))


def taper(a: tuple[float, float], b: tuple[float, float], ra: float,
          rb: float) -> np.ndarray:
    ax, ay = P(*a)
    bx, by = P(*b)
    return sdf_taper(ax, ay, bx, by, U(ra), U(rb))


def disc(c: tuple[float, float], r: float) -> np.ndarray:
    cx, cy = P(*c)
    return sdf_circle(cx, cy, U(r))


def ellipse(c: tuple[float, float], rx: float, ry: float,
            rot: float = 0.0) -> np.ndarray:
    cx, cy = P(*c)
    return sdf_ellipse(cx, cy, U(rx), U(ry), rot)


def arc(c: tuple[float, float], r: float, half_width: float, start: float,
        end: float) -> np.ndarray:
    cx, cy = P(*c)
    return sdf_arc(cx, cy, U(r), U(half_width), math.radians(start),
                   math.radians(end))


def box(c: tuple[float, float], hw: float, hh: float, rot: float = 0.0) -> np.ndarray:
    cx, cy = P(*c)
    return sdf_box(cx, cy, U(hw), U(hh), rot)


def rot(field: np.ndarray, degrees: float) -> np.ndarray:
    return sdf_rotate(field, math.radians(degrees))


def shift(field: np.ndarray, dx: float, dy: float) -> np.ndarray:
    return sdf_shift(field, U(dx), U(dy))


def blade(tip: tuple[float, float], guard: tuple[float, float], width: float,
          hollow: float = 0.0) -> np.ndarray:
    """A double-edged blade: two tapered edges meeting at the tip."""
    tx, ty = tip
    gx, gy = guard
    mx, my = (tx + gx) * 0.5, (ty + gy) * 0.5
    body = sdf_polygon([P(tx, ty), P(mx + (gy - ty) * width, my + (tx - gx) * width),
                        P(gx, gy), P(mx - (gy - ty) * width, my - (tx - gx) * width)])
    if hollow > 0.0:
        spine = taper((mx, my), (gx, gy), hollow, hollow * 0.4)
        body = sdf_subtract(body, spine)
    return body


def SPEED_HZED() -> int:  # kept out of the shading path; see `_shade`
    return 0


def leaf(tip: tuple[float, float], base: tuple[float, float], half_max: float,
         taper: float = 0.85, base_flat: float = 0.45,
         samples: int = 26) -> np.ndarray:
    """A blade: a straight spine from base to tip and an edge that swells.

    Written as a sampled polygon rather than two capsules because a blade's read
    is its edge curve - the way the width runs from the base, peaks about a third
    of the way out, and draws down to the point. `half_max` is in the 0..1 design
    grid; `taper` sharpens the point; `base_flat` widens the heel so a hilt sits
    on it.
    """
    tx, ty = tip
    bx, by = base
    dx, dy = tx - bx, ty - by
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux
    edge = []
    spine = []
    for index in range(samples + 1):
        k = index / samples
        swell = math.sin(math.pi * min(1.0, 0.18 + 0.82 * k)) ** 0.55
        half = half_max * (1.0 - k) ** taper * (base_flat + (1.0 - base_flat) * swell)
        ex = bx + dx * k + px * half
        ey = by + dy * k + py * half
        sx = bx + dx * k - px * half
        sy = by + dy * k - py * half
        edge.append((ex, ey))
        spine.append((sx, sy))
    points = edge + spine[::-1]
    return sdf_polygon([P(x, y) for x, y in points])


def quillons(center: tuple[float, float], angle: float, span: float,
             thickness: float, flare: float = 0.0) -> np.ndarray:
    """A crossguard: a bar across the blade's axis with optional turned ends."""
    cx, cy = center
    dx, dy = math.cos(angle), math.sin(angle)
    bar = cap((cx - dx * span, cy - dy * span), (cx + dx * span, cy + dy * span),
              thickness)
    if flare <= 0.0:
        return bar
    for sign in (-1.0, 1.0):
        tip = (cx + dx * span * sign, cy + dy * span * sign)
        ball = disc(tip, flare)
        bar = sdf_union(bar, ball)
    return bar


def wrapped_grip(start: tuple[float, float], end: tuple[float, float],
                 width: float, wraps: int = 5) -> list:
    """A leather grip with gold wire wraps and a pommel: three layers, not one."""
    grip = taper(start, end, width, width * 0.86)
    sx, sy = start
    ex, ey = end
    dx, dy = ex - sx, ey - sy
    px, py = -dy, dx
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    wires = []
    for index in range(wraps):
        k = (index + 0.5) / wraps
        cx, cy = sx + dx * k, sy + dy * k
        half = width * (1.05 + 0.06 * index)
        wires.append(cap((cx - px * half, cy - py * half),
                         (cx + px * half, cy + py * half), width * 0.16))
    pommel = disc(end, width * 1.35)
    return grip, wires, pommel


def spark_at(at: tuple[float, float], length: float, angle: float,
             width: float = 0.008) -> np.ndarray:
    cx, cy = at
    dx, dy = math.cos(angle), math.sin(angle)
    return cap((cx, cy), (cx + dx * length, cy + dy * length), width)


def halo(center: tuple[float, float], radius: float, half_width: float,
         start: float, end: float) -> np.ndarray:
    """A tapered motion crescent in degrees, for swings and force walls."""
    cx, cy = P(*center)
    return sdf_tapered_arc((cx, cy), U(radius), U(half_width), U(half_width * 0.12),
                           math.radians(start), math.radians(end))


def plate(family_key: str) -> list[Layer]:
    """The disc every icon stands on: lacquer, a family-coloured rim, an inner glow.

    One shared ground is what makes 37 icons read as one set instead of 37
    drawings. It is dark and cool so the warm key light on the subject has
    something to cut against, and it is inset far enough that the hotbar's own
    frame still shows around it.
    """
    disc_shape = disc((0.50, 0.52), 0.452)
    layers = [Layer(disc_shape, "lacquer", bevel=44, depth=0.8, outline=1.2)]
    rim = sdf_subtract(disc_shape, disc((0.50, 0.52), 0.428))
    layers.append(Layer(rim, family_key, bevel=16, alpha=1.0, depth=0.8))
    inner = sdf_subtract(disc((0.50, 0.52), 0.415), disc((0.50, 0.52), 0.395))
    layers.append(Layer(inner, "lacquer", bevel=10, alpha=0.75, depth=0.5))
    # A low glow behind the subject, in the family's colour.
    layers.append(Layer(disc((0.50, 0.46), 0.32), family_key, bevel=60, depth=0.30,
                        alpha=0.16, outline=0.0))
    return layers


# --- icons -----------------------------------------------------------------
#
# Every icon is the same three things in the same order: the lacquer plate, the
# subject in two or three bold masses, one saturated accent. Nothing is drawn
# thinner than about 3.5% of the canvas, because at 26 px a thinner line is gone
# and the icon has to survive that size on the hotbar.
#
# The light is fixed (warm key upper left, cool fill lower right) and every
# composition is written in the 0..1 design grid with a 0.04 margin.

ICONS: dict[str, callable] = {}


def icon(name: str):
    def register(func):
        ICONS[name] = func
        return func
    return register


FAMILY_AURA = {
    "steel": (0.42, 0.62, 0.92),
    "gold": (0.92, 0.68, 0.28),
    "ember": (0.98, 0.42, 0.12),
    "bone": (0.52, 0.86, 0.58),
    "teal": (0.26, 0.82, 0.74),
    "ash": (0.60, 0.58, 0.54),
    "blood": (0.82, 0.18, 0.14),
}


# --- shared pieces ---------------------------------------------------------

def blade_kit(tip, base, half, *, family: str = "steel", bevel: float = 26.0,
              fuller: bool = True, fuller_width: float = 0.030,
              span: float = 0.115, guard_thick: float = 0.026,
              flare: float = 0.034, grip_length: float = 0.17,
              grip_width: float = 0.044, wraps: int = 4, angle: float = None):
    """A hilted blade: leaf, fuller, crossguard, wrapped grip, pommel.

    `angle` is the blade's own direction in radians; everything else hangs off
    the tip/base pair, so a composition only has to place two points.
    """
    tx, ty = tip
    bx, by = base
    if angle is None:
        angle = math.atan2(ty - by, tx - bx)
    layers = []
    body = leaf(tip, base, half, taper=0.76, base_flat=0.5)
    layers.append(Layer(body, family, bevel=bevel))
    if fuller:
        inner = (bx + (tx - bx) * 0.22, by + (ty - by) * 0.22)
        outer = (bx + (tx - bx) * 0.82, by + (ty - by) * 0.82)
        layers.append(Layer(taper(outer, inner, fuller_width, fuller_width * 0.25),
                            "steel_dark", bevel=12, alpha=0.9))
    guard_angle = angle + math.pi * 0.5
    guard = quillons(base, guard_angle, span, guard_thick, flare=flare)
    layers.append(Layer(guard, "gold", bevel=18))
    end = (base[0] - math.cos(angle) * grip_length,
           base[1] - math.sin(angle) * grip_length)
    grip, wires, pommel = wrapped_grip(base, end, grip_width, wraps=wraps)
    layers.append(Layer(grip, "leather", bevel=18))
    wire_union = wires[0]
    for wire in wires[1:]:
        wire_union = sdf_union(wire_union, wire)
    layers.append(Layer(wire_union, "gold", bevel=12, alpha=0.95))
    layers.append(Layer(pommel, "gold", bevel=16))
    return layers, angle


def bow_kit(center, radius, *, tilt: float = 0.0, thickness: float = 0.036,
            string: bool = True) -> list:
    """A strung bow: two swept limbs, a leather grip, horn nocks, a taut string.

    Built from swept arcs rather than an ellipse-ring, because a scaled ellipse
    is not a Euclidean distance field: the subtraction that makes the ring also
    squeezes it, and the limb comes out as a hairline wire. Each limb is thick at
    the grip and drawn to a horn tip, which is what a bow looks like.
    """
    cx, cy = center
    mid_width = thickness * 2.1
    tip_width = thickness * 0.62
    upper = P(cx, cy)
    layers = []
    limb_up = sdf_tapered_arc((upper[0], upper[1]), U(radius), U(mid_width),
                              U(tip_width), math.radians(96.0),
                              math.radians(184.0))
    limb_down = sdf_tapered_arc((upper[0], upper[1]), U(radius), U(tip_width),
                                U(mid_width), math.radians(184.0),
                                math.radians(272.0))
    layers.append(Layer(sdf_union(limb_up, limb_down), "gold", bevel=18))
    # The grip sits on the belly of the bow, where the hand closes.
    layers.append(Layer(ellipse((cx - radius * 0.97, cy), 0.032, 0.085), "leather",
                        bevel=14))
    tips = []
    for sign in (-1.0, 1.0):
        angle = math.radians(96.0)
        ty = cy + sign * radius * math.sin(angle)
        tx = cx + radius * math.cos(angle)
        tips.append((tx, ty))
        layers.append(Layer(disc((tx, ty), tip_width * 1.4), "brass_dark", bevel=12))
    if string:
        layers.append(Layer(cap(tips[0], tips[1], 0.005), "bone", bevel=8, alpha=0.95))
    if tilt != 0.0:
        pass
    return layers


def arrow_kit(a, b, scale: float = 1.0, shaft: str = "ash",
              head: str = "steel") -> list:
    body, _, head_shape, angle = _arrow(a, b, scale)
    px, py = math.cos(angle + math.pi * 0.5), math.sin(angle + math.pi * 0.5)
    # Fletching: two short vanes close to the nock. Anything longer reads as a
    # head at 26 px and the arrow appears to fly the other way.
    fletch = sdf_union(
        sdf_polygon([P(a[0], a[1]),
                     P(a[0] + (b[0] - a[0]) * 0.13 + px * 0.030 * scale,
                       a[1] + (b[1] - a[1]) * 0.13 + py * 0.030 * scale),
                     P(a[0] + (b[0] - a[0]) * 0.05 + px * 0.010 * scale,
                       a[1] + (b[1] - a[1]) * 0.05 + py * 0.010 * scale)]),
        sdf_polygon([P(a[0], a[1]),
                     P(a[0] + (b[0] - a[0]) * 0.13 - px * 0.030 * scale,
                       a[1] + (b[1] - a[1]) * 0.13 - py * 0.030 * scale),
                     P(a[0] + (b[0] - a[0]) * 0.05 - px * 0.010 * scale,
                       a[1] + (b[1] - a[1]) * 0.05 - py * 0.010 * scale)]))
    return [Layer(body, shaft, bevel=16), Layer(head_shape, head, bevel=16),
            Layer(fletch, "ember_hot", bevel=10, alpha=0.85)]


def staff_kit(a, b, *, head: str = "bone", ferrule: bool = True) -> list:
    shaft = taper(a, b, 0.030, 0.020)
    layers = [Layer(shaft, "leather", bevel=18)]
    if ferrule:
        ring = box((a[0], a[1]), 0.048, 0.016)
        layers.append(Layer(ring, "gold", bevel=12))
    return layers


def _arrow(a, b, scale: float = 1.0):
    shaft = taper(a, b, 0.017 * scale, 0.013 * scale)
    bx, by = b
    angle = math.atan2(b[1] - a[1], b[0] - a[0])
    # A forged head is a narrow diamond, not a triangle: a wide triangle at this
    # scale reads as a second fletching and the arrow appears to fly backwards.
    head = sdf_polygon([P(bx, by),
                        P(bx - math.cos(angle) * 0.040 * scale -
                          math.sin(angle) * 0.040 * scale,
                          by - math.sin(angle) * 0.040 * scale +
                          math.cos(angle) * 0.040 * scale),
                        P(bx - math.cos(angle) * 0.125 * scale,
                          by - math.sin(angle) * 0.125 * scale),
                        P(bx - math.cos(angle) * 0.040 * scale +
                          math.sin(angle) * 0.040 * scale,
                          by - math.sin(angle) * 0.040 * scale -
                          math.cos(angle) * 0.040 * scale)])
    return sdf_union(shaft, head), shaft, head, angle


def shield_kit(family: str = "brass_dark", size: float = 0.33,
               boss: str = "gold") -> list:
    body = poly((0.50, 0.52 - size), (0.50 + size * 0.86, 0.52 - size * 0.48),
                (0.50 + size * 0.74, 0.52 + size * 0.22), (0.50, 0.52 + size),
                (0.50 - size * 0.74, 0.52 + size * 0.22),
                (0.50 - size * 0.86, 0.52 - size * 0.48))
    inner = poly((0.50, 0.52 - size * 0.84), (0.50 + size * 0.70, 0.52 - size * 0.38),
                 (0.50 + size * 0.58, 0.52 + size * 0.16), (0.50, 0.52 + size * 0.82),
                 (0.50 - size * 0.58, 0.52 + size * 0.16),
                 (0.50 - size * 0.70, 0.52 - size * 0.38))
    rim = sdf_subtract(body, inner)
    layers = [Layer(body, family, bevel=28), Layer(rim, "gold", bevel=18),
              Layer(disc((0.50, 0.50), size * 0.24), boss, bevel=18)]
    for sign in (-1.0, 1.0):
        strap = box((0.50 + sign * size * 0.52, 0.52), size * 0.06, size * 0.9,
                    rot=sign * 0.1)
        layers.append(Layer(strap, "leather", bevel=14, alpha=0.9))
    return layers


def chevron_field(x: float, y: float, size: float) -> np.ndarray:
    """A solid forward chevron: the body skills' shared mark, drawn thick."""
    return poly((x, y - size), (x + size * 0.60, y), (x, y + size),
                (x + size * 0.30, y + size), (x + size * 0.90, y),
                (x + size * 0.30, y - size))


# --- bow -------------------------------------------------------------------

@icon("barrage")
def barrage():
    layers = plate("gold")
    layers += bow_kit((0.34, 0.52), 0.245, tilt=0.0, thickness=0.034)
    for index, (y0, y1) in enumerate(((0.30, 0.26), (0.52, 0.52), (0.74, 0.78))):
        layers += arrow_kit((0.26, y0), (0.88, y1), 1.05 if index == 1 else 0.90)
    layers.append(Layer(halo((0.30, 0.52), 0.58, 0.02, -46, 46), "ember_hot",
                        bevel=10, alpha=0.55))
    return layers


@icon("triple_volley")
def triple_volley():
    layers = plate("gold")
    layers += bow_kit((0.32, 0.52), 0.235, thickness=0.032)
    for index, (dy, length, scale) in enumerate(((-0.26, 0.56, 0.8), (0.0, 0.68, 1.0),
                                                 (0.26, 0.56, 0.8))):
        layers += arrow_kit((0.24, 0.52), (0.24 + length, 0.52 + dy), scale)
    layers.append(Layer(halo((0.24, 0.52), 0.62, 0.024, -42, 42), "ember_hot",
                        bevel=10, alpha=0.6))
    return layers


@icon("piercing_shot")
def piercing_shot():
    layers = plate("steel")
    layers += arrow_kit((0.08, 0.54), (0.94, 0.46), 1.6)
    for x, r in ((0.34, 0.12), (0.56, 0.10), (0.76, 0.085)):
        layers.append(Layer(sdf_subtract(arc((x, 0.50), r, 0.030, 0, 360),
                                         arc((x, 0.50), r, 0.014, 0, 360)),
                            "teal", bevel=14, alpha=0.9))
    for index, y in enumerate((0.30, 0.72)):
        layers.append(Layer(cap((0.10, y), (0.32, y), 0.014), "teal_dark", bevel=10,
                            alpha=0.85))
    return layers


@icon("snap_shot")
def snap_shot():
    layers = plate("gold")
    layers += bow_kit((0.36, 0.52), 0.215, thickness=0.030)
    layers += arrow_kit((0.26, 0.58), (0.90, 0.44), 1.0)
    layers.append(Layer(disc((0.80, 0.46), 0.062), "lacquer", bevel=14))
    layers.append(Layer(disc((0.80, 0.46), 0.038), "rot", bevel=12))
    return layers


@icon("rain_of_ash")
def rain_of_ash():
    layers = plate("ash")
    for x in (0.24, 0.44, 0.64, 0.82):
        layers += arrow_kit((x + 0.02, 0.08), (x - 0.05, 0.68), 1.05,
                            shaft="ash", head="steel")
    for x, y, r, a in ((0.22, 0.80, 0.10, 0.5), (0.52, 0.86, 0.13, 0.45),
                       (0.80, 0.82, 0.09, 0.5)):
        layers.append(Layer(disc((x, y), r), "ash", bevel=40, alpha=a, outline=0.0,
                            bloom=False))
    layers.append(Layer(arc((0.5, 0.90), 0.42, 0.022, 16, 164), "ember", bevel=12,
                        alpha=0.6))
    for x, y in ((0.30, 0.42), (0.58, 0.30), (0.76, 0.48), (0.46, 0.60)):
        layers.append(Layer(disc((x, y), 0.020), "ash", bevel=10, alpha=0.85,
                            bloom=False))
    return layers


@icon("skewer")
def skewer():
    layers = plate("steel")
    sack = ellipse((0.42, 0.62), 0.19, 0.26, rot=-0.30)
    sack = sdf_union(sack, cap((0.42, 0.38), (0.42, 0.22), 0.026))
    layers.append(Layer(sack, "leather", bevel=26))
    layers.append(Layer(cap((0.24, 0.86), (0.60, 0.86), 0.018), "brass_dark",
                        bevel=12, alpha=0.7))
    layers += arrow_kit((0.06, 0.80), (0.96, 0.26), 1.7)
    layers.append(Layer(disc((0.52, 0.46), 0.075), "blood", bevel=16))
    layers.append(Layer(disc((0.52, 0.46), 0.030), "ember_hot", bevel=10))
    return layers


# --- sword and dagger ------------------------------------------------------

@icon("quick_cut")
def quick_cut():
    layers = plate("steel")
    layers.append(Layer(halo((0.42, 0.54), 0.46, 0.085, -148, -2), "teal",
                        bevel=20, alpha=0.85))
    layers.append(Layer(halo((0.42, 0.54), 0.50, 0.022, -144, -14), "ember_hot",
                        bevel=10, alpha=0.8))
    blade, _ = blade_kit((0.87, 0.14), (0.33, 0.65), 0.165)
    return layers + blade


@icon("double_slash")
def double_slash():
    layers = plate("teal")
    layers.append(Layer(halo((0.50, 0.50), 0.44, 0.070, -156, -12), "teal",
                        bevel=16, alpha=0.55))
    layers.append(Layer(halo((0.50, 0.50), 0.38, 0.060, 16, 168), "steel_dark",
                        bevel=16, alpha=0.55))
    upper, _ = blade_kit((0.80, 0.22), (0.46, 0.48), 0.100, span=0.075,
                         grip_length=0.11, grip_width=0.032, wraps=3)
    lower, _ = blade_kit((0.24, 0.30), (0.58, 0.56), 0.095, family="steel_dark",
                         span=0.075, grip_length=0.11, grip_width=0.032, wraps=3)
    layers += lower
    layers += upper
    return layers


@icon("quick_stab")
def quick_stab():
    layers = plate("steel")
    layers.append(Layer(cap((0.12, 0.50), (0.80, 0.50), 0.026), "teal", bevel=14,
                        alpha=0.65))
    blade, _ = blade_kit((0.93, 0.50), (0.40, 0.54), 0.105, span=0.095,
                         grip_length=0.15, grip_width=0.040)
    layers += blade
    layers.append(Layer(disc((0.95, 0.50), 0.036), "teal", bevel=12))
    return layers


@icon("lunge_thrust")
def lunge_thrust():
    layers = plate("steel")
    for y in (0.34, 0.50, 0.66):
        layers.append(Layer(cap((0.05, y), (0.30, y), 0.014), "teal", bevel=10,
                            alpha=0.8))
    blade, _ = blade_kit((0.90, 0.48), (0.34, 0.55), 0.115, span=0.10,
                         grip_length=0.14, grip_width=0.040)
    layers += blade
    layers.append(Layer(disc((0.93, 0.47), 0.060), "ember", bevel=14))
    layers.append(Layer(disc((0.93, 0.47), 0.028), "ember_hot", bevel=10))
    return layers


@icon("butchers_cut")
def butchers_cut():
    layers = plate("blood")
    layers.append(Layer(halo((0.46, 0.52), 0.44, 0.105, -156, 8), "blood",
                        bevel=18, alpha=0.85))
    layers.append(Layer(halo((0.46, 0.52), 0.48, 0.022, -150, -8), "ember",
                        bevel=10, alpha=0.75))
    blade, _ = blade_kit((0.88, 0.20), (0.36, 0.62), 0.145, bevel=28, span=0.10,
                         grip_length=0.13, grip_width=0.040)
    layers += blade
    for x, y, r in ((0.62, 0.72, 0.034), (0.74, 0.64, 0.026), (0.52, 0.78, 0.022)):
        layers.append(Layer(disc((x, y), r), "blood", bevel=12))
    return layers


@icon("gut_hook")
def gut_hook():
    layers = plate("blood")
    layers.append(Layer(halo((0.48, 0.58), 0.34, 0.075, 196, 524), "blood",
                        bevel=14, alpha=0.6))
    for y in (0.26, 0.38, 0.50):
        layers.append(Layer(arc((0.52, y + 0.18), 0.17, 0.020, 175, 365), "bone",
                            bevel=14, alpha=0.95))
    layers.append(Layer(cap((0.52, 0.20), (0.52, 0.74), 0.022), "bone", bevel=14))
    hook = arc((0.44, 0.64), 0.19, 0.034, 110, 410)
    layers.append(Layer(hook, "steel", bevel=18))
    layers.append(Layer(taper((0.30, 0.72), (0.30, 0.88), 0.032, 0.022), "leather",
                        bevel=16))
    layers.append(Layer(arc((0.44, 0.64), 0.19, 0.012, 110, 410), "ember_hot",
                        bevel=10, alpha=0.7))
    return layers


@icon("knife_work")
def knife_work():
    layers = plate("steel")
    for index, (y, tilt) in enumerate(((0.32, 0.10), (0.52, 0.0), (0.72, -0.10))):
        blade, _ = blade_kit((0.60, y - tilt), (0.26, y + 0.05 + tilt * 0.4), 0.070,
                             bevel=18, fuller=False, span=0.055,
                             guard_thick=0.014, flare=0.020, grip_length=0.10,
                             grip_width=0.030, wraps=2)
        layers += blade
        layers.append(Layer(disc((0.62, y - tilt * 1.6), 0.026), "teal", bevel=10,
                            alpha=0.9))
    return layers


@icon("three_strike")
def three_strike():
    layers = plate("gold")
    for r, start_angle, end_angle, material in ((0.46, -132, -14, "steel"),
                                                (0.38, -6, 110, "steel"),
                                                (0.29, 102, 224, "gold")):
        layers.append(Layer(halo((0.50, 0.52), r, 0.075, start_angle, end_angle),
                            material, bevel=18, alpha=0.95))
    blade, _ = blade_kit((0.80, 0.34), (0.46, 0.60), 0.085, span=0.075,
                         grip_length=0.11, grip_width=0.032, wraps=3)
    layers += blade
    layers.append(Layer(disc((0.50, 0.88), 0.048), "ember_hot", bevel=14))
    return layers


@icon("heavy_swing")
def heavy_swing():
    layers = plate("gold")
    layers.append(Layer(halo((0.48, 0.60), 0.50, 0.105, -152, -14), "gold",
                        bevel=18, alpha=0.6))
    blade, _ = blade_kit((0.80, 0.12), (0.34, 0.66), 0.185, bevel=30, span=0.14,
                         guard_thick=0.032, flare=0.042, grip_length=0.15,
                         grip_width=0.048)
    layers += blade
    for x, y, r in ((0.20, 0.84, 0.040), (0.34, 0.90, 0.030), (0.62, 0.84, 0.034)):
        layers.append(Layer(disc((x, y), r), "ash", bevel=12, alpha=0.6,
                            bloom=False))
    return layers


@icon("wide_sweep")
def wide_sweep():
    layers = plate("steel")
    for r, start, end, material, alpha in ((0.50, -170, 14, "steel_dark", 0.6),
                                           (0.41, -158, 4, "steel", 0.85),
                                           (0.32, -148, -6, "steel", 0.95)):
        layers.append(Layer(halo((0.46, 0.56), r, 0.055, start, end), material,
                            bevel=14, alpha=alpha))
    blade, _ = blade_kit((0.86, 0.26), (0.40, 0.62), 0.125, span=0.10,
                         grip_length=0.13, grip_width=0.040)
    layers += blade
    return layers


@icon("ground_breaker")
def ground_breaker():
    layers = plate("gold")
    haft = cap((0.50, 0.10), (0.50, 0.60), 0.034)
    head = box((0.50, 0.14), 0.22, 0.10)
    layers.append(Layer(haft, "leather", bevel=18))
    layers.append(Layer(head, "iron", bevel=26))
    layers.append(Layer(box((0.50, 0.14), 0.14, 0.042), "gold", bevel=12, alpha=0.8))
    layers.append(Layer(cap((0.10, 0.74), (0.90, 0.74), 0.020), "teal", bevel=12,
                        alpha=0.9))
    for x, dx, dy in ((0.50, -0.18, 0.13), (0.50, 0.16, 0.10), (0.34, -0.12, 0.10),
                      (0.66, 0.14, 0.15), (0.24, -0.09, 0.06), (0.76, 0.08, 0.06)):
        layers.append(Layer(cap((x, 0.75), (x + dx, 0.75 + dy), 0.010), "ash",
                            bevel=8, alpha=0.9, bloom=False))
    for x, y, r in ((0.28, 0.86, 0.032), (0.70, 0.88, 0.026), (0.50, 0.92, 0.020)):
        layers.append(Layer(disc((x, y), r), "stone", bevel=12))
    return layers


@icon("executioner")
def executioner():
    layers = plate("steel")
    layers.append(Layer(arc((0.50, 0.28), 0.16, 0.026, 0, 360), "blood", bevel=12,
                        alpha=0.6))
    blade, _ = blade_kit((0.50, 0.84), (0.50, 0.30), 0.135, bevel=30, span=0.15,
                         guard_thick=0.030, flare=0.040, grip_length=0.14,
                         grip_width=0.044)
    layers += blade
    skull = sdf_union(ellipse((0.50, 0.84), 0.10, 0.088), box((0.50, 0.92), 0.052,
                                                             0.034))
    layers.append(Layer(skull, "bone", bevel=18))
    for x in (0.462, 0.538):
        layers.append(Layer(disc((x, 0.82), 0.022), "iron", bevel=10))
    return layers


@icon("spin_slash")
def spin_slash():
    layers = plate("teal")
    layers.append(Layer(halo((0.50, 0.52), 0.40, 0.085, -166, 166), "steel",
                        bevel=18, alpha=0.75))
    layers.append(Layer(halo((0.50, 0.52), 0.45, 0.022, -158, 18), "teal",
                        bevel=10, alpha=0.7))
    blade, _ = blade_kit((0.86, 0.22), (0.46, 0.58), 0.125, span=0.10,
                         grip_length=0.13, grip_width=0.040)
    layers += blade
    for index in range(8):
        angle = math.radians(index * 45 + 10)
        layers.append(Layer(cap((0.50 + math.cos(angle) * 0.56,
                                 0.52 + math.sin(angle) * 0.56),
                                (0.50 + math.cos(angle) * 0.60,
                                 0.52 + math.sin(angle) * 0.60), 0.008), "teal",
                            bevel=8, alpha=0.7))
    return layers


@icon("backstab")
def backstab():
    layers = plate("steel")
    shoulders = ellipse((0.50, 0.78), 0.22, 0.19)
    hood = ellipse((0.50, 0.40), 0.125, 0.15)
    figure = sdf_union(shoulders, hood)
    layers.append(Layer(figure, "steel_dark", bevel=26))
    # Rim light along the silhouette: the figure has to separate from the plate
    # at 26 px, and a dark shape on a dark disc does not.
    outline_band = np.exp(-np.square(figure / U(0.012)))
    layers.append(Layer(outline_band, "steel", bevel=6, alpha=0.55))
    layers.append(Layer(cap((0.20, 0.68), (0.80, 0.68), 0.014), "leather",
                        bevel=10, alpha=0.9))
    layers.append(Layer(disc((0.50, 0.56), 0.115), "blood", bevel=22))
    layers.append(Layer(disc((0.50, 0.56), 0.052), "ember_hot", bevel=12))
    dagger, _ = blade_kit((0.92, 0.80), (0.62, 0.44), 0.070, bevel=18, span=0.05,
                          grip_length=0.09, grip_width=0.028, wraps=2)
    layers += dagger
    for index in range(8):
        angle = math.radians(index * 45 + 18)
        reach = 0.21 if index % 2 == 0 else 0.15
        layers.append(Layer(cap((0.50 + math.cos(angle) * 0.07,
                                 0.56 + math.sin(angle) * 0.07),
                                (0.50 + math.cos(angle) * reach,
                                 0.56 + math.sin(angle) * reach), 0.011),
                            "ember" if index % 2 == 0 else "gold", bevel=8))
    return layers


# --- staff -----------------------------------------------------------------

@icon("fireball")
def fireball():
    layers = plate("ember")
    layers += staff_kit((0.18, 0.86), (0.54, 0.46))
    layers.append(Layer(disc((0.63, 0.42), 0.245), "ember", bevel=32))
    layers.append(Layer(disc((0.63, 0.42), 0.165), "ember_hot", bevel=22))
    for a, b, r in (((0.62, 0.22), (0.54, 0.04), 0.070),
                    ((0.72, 0.28), (0.84, 0.06), 0.052),
                    ((0.52, 0.30), (0.40, 0.10), 0.046)):
        layers.append(Layer(taper(a, b, r, 0.006), "ember", bevel=16, alpha=0.9))
    layers.append(Layer(arc((0.63, 0.42), 0.30, 0.016, 20, 300), "cinder",
                        bevel=10, alpha=0.7))
    return layers


@icon("cinder_lance")
def cinder_lance():
    layers = plate("ember")
    layers += staff_kit((0.14, 0.86), (0.42, 0.58))
    layers.append(Layer(taper((0.42, 0.58), (0.96, 0.16), 0.075, 0.010), "ember",
                        bevel=20))
    layers.append(Layer(taper((0.46, 0.54), (0.94, 0.18), 0.030, 0.004), "ember_hot",
                        bevel=12))
    for index, t in enumerate((0.30, 0.48, 0.66, 0.84)):
        x = 0.42 + (0.96 - 0.42) * t
        y = 0.58 + (0.16 - 0.58) * t
        layers.append(Layer(disc((x + 0.03, y - 0.03), 0.022 - 0.002 * index),
                            "ember_hot", bevel=10, alpha=0.9))
    return layers


@icon("bone_spear")
def bone_spear():
    layers = plate("bone")
    layers += staff_kit((0.16, 0.88), (0.46, 0.58))
    layers.append(Layer(disc((0.46, 0.56), 0.070), "bone", bevel=16))
    layers.append(Layer(taper((0.46, 0.56), (0.92, 0.18), 0.070, 0.014), "bone",
                        bevel=20))
    for t_along in (0.20, 0.42, 0.64):
        x = 0.46 + (0.92 - 0.46) * t_along
        y = 0.56 + (0.18 - 0.56) * t_along
        barbs = sdf_union(cap((x, y), (x - 0.075, y - 0.12), 0.020),
                          cap((x, y), (x - 0.03, y + 0.12), 0.017))
        layers.append(Layer(barbs, "bone", bevel=14))
    layers.append(Layer(arc((0.60, 0.48), 0.26, 0.020, 150, 390), "teal", bevel=10,
                        alpha=0.7))
    return layers


@icon("grave_bloom")
def grave_bloom():
    layers = plate("bone")
    for index in range(6):
        angle = math.radians(-90 + index * 60)
        cx = 0.50 + math.cos(angle) * 0.22
        cy = 0.50 + math.sin(angle) * 0.22
        layers.append(Layer(ellipse((cx, cy), 0.135, 0.078, rot=angle), "bone",
                            bevel=20))
        layers.append(Layer(ellipse((cx, cy), 0.085, 0.030, rot=angle), "ash",
                            bevel=12, alpha=0.5, bloom=False))
    layers.append(Layer(disc((0.50, 0.50), 0.13), "iron", bevel=20))
    layers.append(Layer(disc((0.50, 0.50), 0.062), "teal", bevel=16))
    for index in range(5):
        angle = math.radians(-90 + index * 72 + 36)
        layers.append(Layer(cap((0.50 + math.cos(angle) * 0.34,
                                 0.50 + math.sin(angle) * 0.34),
                                (0.50 + math.cos(angle) * 0.44,
                                 0.50 + math.sin(angle) * 0.44), 0.010), "teal",
                            bevel=8, alpha=0.75))
    return layers


# --- wards -----------------------------------------------------------------

@icon("ember_ward")
def ember_ward():
    layers = plate("ember")
    layers.append(Layer(arc((0.50, 0.52), 0.40, 0.022, 0, 360), "gold", bevel=16))
    layers.append(Layer(arc((0.50, 0.52), 0.30, 0.038, 0, 360), "ember", bevel=18,
                        alpha=0.95))
    for index in range(9):
        angle = math.radians(index * 40)
        layers.append(Layer(cap((0.50 + math.cos(angle) * 0.29,
                                 0.52 + math.sin(angle) * 0.29),
                                (0.50 + math.cos(angle) * 0.43,
                                 0.52 + math.sin(angle) * 0.43), 0.024), "ember",
                            bevel=14, alpha=0.95))
    layers.append(Layer(disc((0.50, 0.52), 0.165), "ember_hot", bevel=22))
    layers.append(Layer(poly((0.50, 0.34), (0.62, 0.54), (0.50, 0.70),
                             (0.38, 0.54)), "cinder", bevel=16, alpha=0.8))
    return layers


@icon("energy_shield")
def energy_shield():
    layers = plate("gold")
    layers.append(Layer(disc((0.50, 0.52), 0.44), "gold", bevel=40, alpha=0.16,
                        outline=0.5))
    layers.append(Layer(arc((0.50, 0.52), 0.42, 0.026, 0, 360), "gold", bevel=18))
    shield = poly((0.50, 0.14), (0.80, 0.27), (0.75, 0.56), (0.50, 0.88),
                  (0.25, 0.56), (0.20, 0.27))
    layers.append(Layer(shield, "gold", bevel=30))
    inner = poly((0.50, 0.23), (0.71, 0.33), (0.67, 0.55), (0.50, 0.78),
                 (0.33, 0.55), (0.29, 0.33))
    layers.append(Layer(inner, "brass_dark", bevel=20))
    layers.append(Layer(disc((0.50, 0.50), 0.085), "gold", bevel=16))
    for index in range(12):
        angle = math.radians(index * 30)
        layers.append(Layer(cap((0.50 + math.cos(angle) * 0.47,
                                 0.52 + math.sin(angle) * 0.47),
                                (0.50 + math.cos(angle) * 0.53,
                                 0.52 + math.sin(angle) * 0.53), 0.008), "gold",
                            bevel=8, alpha=0.7))
    return layers


@icon("focus")
def focus():
    layers = plate("teal")
    for r, width, material, alpha in ((0.42, 0.020, "teal", 1.0),
                                      (0.31, 0.014, "teal_dark", 0.9),
                                      (0.21, 0.011, "teal", 0.8)):
        layers.append(Layer(arc((0.50, 0.52), r, width, 0, 360), material,
                            bevel=14, alpha=alpha))
    layers.append(Layer(disc((0.50, 0.52), 0.13), "teal", bevel=22))
    layers.append(Layer(disc((0.50, 0.52), 0.075), "lacquer", bevel=14))
    # The cord's sigil: a vertical eye, which is what "attention" looks like.
    layers.append(Layer(sdf_union(sdf_union(cap((0.50, 0.42), (0.50, 0.62), 0.020),
                                            cap((0.44, 0.52), (0.56, 0.52), 0.016)),
                                  disc((0.50, 0.52), 0.030)), "ember_hot",
                        bevel=12, alpha=0.95))
    for index in range(8):
        angle = math.radians(index * 45 + 22)
        layers.append(Layer(cap((0.50 + math.cos(angle) * 0.36,
                                 0.52 + math.sin(angle) * 0.36),
                                (0.50 + math.cos(angle) * 0.41,
                                 0.52 + math.sin(angle) * 0.41), 0.009), "teal",
                            bevel=8, alpha=0.8))
    return layers


@icon("stone_skin")
def stone_skin():
    layers = plate("ash")
    torso = poly((0.28, 0.16), (0.72, 0.16), (0.80, 0.44), (0.62, 0.86),
                 (0.38, 0.86), (0.20, 0.44))
    layers.append(Layer(torso, "stone", bevel=32))
    for y in (0.34, 0.52, 0.70):
        layers.append(Layer(cap((0.22, y), (0.78, y), 0.018), "iron", bevel=10,
                            alpha=0.75, bloom=False))
    layers.append(Layer(cap((0.50, 0.19), (0.50, 0.82), 0.014), "iron", bevel=10,
                        alpha=0.6, bloom=False))
    layers.append(Layer(poly((0.22, 0.44), (0.40, 0.28), (0.32, 0.54)), "gold",
                        bevel=14, alpha=0.6))
    for x, y, angle in ((0.36, 0.62, 0.9), (0.62, 0.46, -0.7)):
        layers.append(Layer(cap((x, y), (x + math.cos(angle) * 0.10,
                                         y + math.sin(angle) * 0.10), 0.008),
                            "ash", bevel=8, alpha=0.8, bloom=False))
    crack = sdf_union(cap((0.40, 0.28), (0.52, 0.44), 0.012),
                      cap((0.52, 0.44), (0.46, 0.62), 0.010))
    layers.append(Layer(crack, "ember", bevel=10, alpha=0.9))
    return layers


# --- shields ---------------------------------------------------------------

@icon("shield_shove")
def shield_shove():
    layers = plate("gold")
    for index, r in enumerate((0.50, 0.56, 0.62)):
        layers.append(Layer(arc((0.44, 0.52), r, 0.030, -58, 58), "steel",
                            bevel=12, alpha=0.70 - 0.15 * index))
    layers += shield_kit(size=0.30)
    layers.append(Layer(cap((0.84, 0.52), (0.95, 0.52), 0.034), "teal", bevel=14,
                        alpha=0.9))
    return layers


@icon("shield_bash")
def shield_bash():
    layers = plate("gold")
    layers += shield_kit(size=0.28)
    for index in range(10):
        angle = math.radians(index * 36 + 12)
        length = 0.30 if index % 2 == 0 else 0.22
        layers.append(Layer(cap((0.50 + math.cos(angle) * 0.22,
                                 0.52 + math.sin(angle) * 0.22),
                                (0.50 + math.cos(angle) * length,
                                 0.52 + math.sin(angle) * length), 0.018),
                            "ember" if index % 2 == 0 else "ember_hot", bevel=10,
                            alpha=0.95))
    return layers


@icon("shield_charge")
def shield_charge():
    layers = plate("gold")
    for index, x in enumerate((0.06, 0.15, 0.24)):
        layers.append(Layer(chevron_field(x, 0.52, 0.15), "teal", bevel=14,
                            alpha=0.55 + 0.2 * index))
    layers += shield_kit(size=0.31)
    return layers


@icon("shield_slam")
def shield_slam():
    layers = plate("gold")
    layers += shield_kit(size=0.26)
    layers.append(Layer(cap((0.10, 0.80), (0.90, 0.80), 0.020), "teal", bevel=12,
                        alpha=0.9))
    for r, alpha in ((0.44, 0.6), (0.54, 0.4), (0.64, 0.26)):
        layers.append(Layer(arc((0.50, 0.82), r, 0.020, 190, 350), "ember",
                            bevel=12, alpha=alpha))
    return layers


@icon("rebuke")
def rebuke():
    layers = plate("gold")
    layers += shield_kit(size=0.29)
    layers.append(Layer(arc((0.50, 0.52), 0.44, 0.032, 150, 250), "gold", bevel=16,
                        alpha=0.85))
    layers += arrow_kit((0.88, 0.18), (0.58, 0.34), 1.0)
    layers.append(Layer(disc((0.50, 0.44), 0.045), "ember", bevel=12))
    return layers


# --- body ------------------------------------------------------------------

@icon("charge")
def charge():
    layers = plate("teal")
    layers.append(Layer(chevron_field(0.28, 0.50, 0.40), "gold", bevel=24))
    layers.append(Layer(chevron_field(0.54, 0.50, 0.30), "brass_dark", bevel=20))
    for index, y in enumerate((0.22, 0.50, 0.78)):
        layers.append(Layer(cap((0.04, y), (0.26 - 0.04 * index, y), 0.024),
                            "teal", bevel=12, alpha=0.85))
    layers.append(Layer(disc((0.88, 0.50), 0.055), "ember", bevel=14))
    layers.append(Layer(disc((0.88, 0.50), 0.026), "ember_hot", bevel=10))
    return layers


@icon("dash")
def dash():
    layers = plate("teal")
    for index, (x, length) in enumerate(((0.06, 0.26), (0.24, 0.18), (0.40, 0.12))):
        layers.append(Layer(cap((x, 0.50), (x + length, 0.50), 0.020 - index * 0.003),
                            "teal", bevel=10, alpha=0.9 - 0.2 * index))
    layers.append(Layer(chevron_field(0.42, 0.50, 0.36), "gold", bevel=24))
    layers.append(Layer(chevron_field(0.70, 0.50, 0.22), "brass_dark", bevel=16))
    layers.append(Layer(disc((0.90, 0.50), 0.050), "teal", bevel=14))
    return layers


# --- consumables -----------------------------------------------------------

@icon("bandage")
def bandage():
    layers = plate("bone")
    roll = ellipse((0.46, 0.52), 0.30, 0.25, rot=-0.28)
    layers.append(Layer(roll, "bone", bevel=34))
    for index, r in enumerate((0.19, 0.13, 0.075)):
        layers.append(Layer(ellipse((0.46 - 0.012 * index, 0.52 - 0.012 * index),
                                    r, r * 0.84, rot=-0.28), "ash", bevel=12,
                            alpha=0.5, bloom=False))
    layers.append(Layer(ellipse((0.46, 0.52), 0.050, 0.042, rot=-0.28), "bone",
                        bevel=12))
    layers.append(Layer(cap((0.16, 0.32), (0.76, 0.70), 0.036), "gold", bevel=16))
    layers.append(Layer(cap((0.74, 0.72), (0.92, 0.82), 0.028), "gold", bevel=14,
                        alpha=0.95))
    for index in (0, 1):
        layers.append(Layer(cap((0.28 + 0.09 * index, 0.76),
                                (0.33 + 0.09 * index, 0.92), 0.012), "bone",
                            bevel=8, alpha=0.7, bloom=False))
    return layers


@icon("healing_potion")
def healing_potion():
    layers = plate("blood")
    neck = box((0.50, 0.28), 0.062, 0.085)
    body = disc((0.50, 0.60), 0.26)
    flask = sdf_union(sdf_union(body, neck), box((0.50, 0.19), 0.075, 0.035))
    layers.append(Layer(flask, "ash", bevel=28, alpha=0.95))
    layers.append(Layer(sdf_subtract(body, disc((0.50, 0.60), 0.225)), "steel",
                        bevel=16, alpha=0.6))
    layers.append(Layer(sdf_subtract(disc((0.50, 0.60), 0.225),
                                     cap((0.22, 0.60), (0.78, 0.60), 0.001)),
                        "blood", bevel=24, alpha=0.98))
    layers.append(Layer(ellipse((0.385, 0.49), 0.048, 0.10, rot=0.42), "bone",
                        bevel=14, alpha=0.7))
    layers.append(Layer(box((0.50, 0.19), 0.080, 0.040), "leather", bevel=14))
    for x, y, r in ((0.80, 0.32, 0.020), (0.86, 0.24, 0.014), (0.73, 0.22, 0.012)):
        layers.append(Layer(cap((x, y), (x + 0.02, y - 0.06), r), "ember_hot",
                            bevel=8, alpha=0.9))
    return layers


# --- the forge --------------------------------------------------------------

def build(name: str) -> list[Layer]:
    if name not in ICONS:
        raise KeyError(f"no icon composition named {name!r}")
    return ICONS[name]()


ICON_AURA = {
    "barrage": FAMILY_AURA["gold"], "triple_volley": FAMILY_AURA["gold"],
    "piercing_shot": FAMILY_AURA["steel"], "snap_shot": FAMILY_AURA["gold"],
    "rain_of_ash": FAMILY_AURA["ash"], "skewer": FAMILY_AURA["steel"],
    "quick_cut": FAMILY_AURA["steel"], "double_slash": FAMILY_AURA["steel"],
    "quick_stab": FAMILY_AURA["steel"], "lunge_thrust": FAMILY_AURA["steel"],
    "butchers_cut": FAMILY_AURA["blood"], "gut_hook": FAMILY_AURA["blood"],
    "knife_work": FAMILY_AURA["steel"], "three_strike": FAMILY_AURA["gold"],
    "heavy_swing": FAMILY_AURA["gold"], "wide_sweep": FAMILY_AURA["steel"],
    "ground_breaker": FAMILY_AURA["gold"], "executioner": FAMILY_AURA["steel"],
    "spin_slash": FAMILY_AURA["teal"], "backstab": FAMILY_AURA["blood"],
    "fireball": FAMILY_AURA["ember"], "cinder_lance": FAMILY_AURA["ember"],
    "bone_spear": FAMILY_AURA["bone"], "grave_bloom": FAMILY_AURA["bone"],
    "ember_ward": FAMILY_AURA["ember"], "energy_shield": FAMILY_AURA["gold"],
    "focus": FAMILY_AURA["teal"], "stone_skin": FAMILY_AURA["ash"],
    "shield_shove": FAMILY_AURA["gold"], "shield_bash": FAMILY_AURA["gold"],
    "shield_charge": FAMILY_AURA["gold"], "shield_slam": FAMILY_AURA["gold"],
    "rebuke": FAMILY_AURA["gold"], "charge": FAMILY_AURA["teal"],
    "dash": FAMILY_AURA["teal"], "bandage": FAMILY_AURA["bone"],
    "healing_potion": FAMILY_AURA["blood"],
}


def render_icon(name: str) -> Image.Image:
    return render(build(name), seed=zlib.crc32(name.encode("utf-8")) % 9999,
                  aura=ICON_AURA.get(name))


def ship(name: str, master: bool = False) -> Path:
    image = render_icon(name)
    shipped = downsample(image, SHIPPED)
    path = OUT / f"{name}.png"
    shipped.save(path, optimize=True)
    if master:
        MASTER.mkdir(parents=True, exist_ok=True)
        downsample(image, MASTER_SIZE).save(MASTER / f"{name}.png", optimize=True)
    return path


def contact_sheet(names: list[str], path: Path, columns: int = 8,
                  cell: int = 160) -> None:
    rows = (len(names) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell, rows * cell), (20, 24, 26, 255))
    for index, name in enumerate(names):
        with Image.open(OUT / f"{name}.png") as icon_image:
            tile = icon_image.convert("RGBA").resize((cell, cell), Image.LANCZOS)
        sheet.alpha_composite(tile, ((index % columns) * cell,
                                     (index // columns) * cell))
    sheet.save(path)


def legibility_strip(names: list[str], path: Path,
                     sizes: tuple[int, ...] = (26, 52)) -> None:
    width = sum(size + 12 for size in sizes) + 12
    sheet = Image.new("RGBA", (width, len(names) * (max(sizes) + 12)),
                      (20, 24, 26, 255))
    for row, name in enumerate(names):
        with Image.open(OUT / f"{name}.png") as icon_image:
            x = 6
            for size in sizes:
                tile = icon_image.convert("RGBA").resize((size, size),
                                                         Image.LANCZOS)
                sheet.alpha_composite(tile, (x, row * (max(sizes) + 12) + 6))
                x += size + 12
    sheet.save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", default="", help="comma-separated icon ids")
    parser.add_argument("--sheet", action="store_true", help="write a contact sheet")
    parser.add_argument("--preview", type=int, default=0,
                        help="write a legibility strip at the given columns")
    parser.add_argument("--master", action="store_true",
                        help="also write 512 px masters to .runtime/icon-masters")
    args = parser.parse_args()

    names = ([n.strip() for n in args.only.split(",") if n.strip()] or
             sorted(ICONS))
    OUT.mkdir(parents=True, exist_ok=True)
    for name in names:
        path = ship(name, master=args.master)
        print(f"wrote {path}")
    if args.sheet:
        contact_sheet(sorted(ICONS), ROOT.parent / "icon_sheet.png")
    if args.preview > 0:
        legibility_strip(names, ROOT.parent / "icon_preview.png")


if __name__ == "__main__":
    main()
