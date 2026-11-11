"""Author the roguelite's reward chests: three ornate, textured props.

The run's furniture used to be `Geo.box` with flat `StandardMaterial3D` colours,
which is a placeholder that a lit scene cannot hide. These are the real props: an
island chest, a mini cache and a boss's hoard - planked body, a staved lid, a
riveted iron strap over the dome, corner brackets, ring handles and a gilded
hasp with a gem - built here as geometry and baked in Cycles into a PBR set per
material, so the wood has grain, the iron has hammer marks and the gilt has cast
pitting. Pigment and relief only; no lighting is painted into a map.

Four materials, one atlas each, shared by all three variants:

    Chest_Wood   2048  base colour / tangent normal / ORM (metal 0)
    Chest_Iron   1024  glTF metal 0.92
    Chest_Gold   1024  glTF metal 1.00
    Chest_Gem     512  the one emissive material; tinted per tier at runtime

The bake is high-to-low: every group is built twice, the dense copy displaced by
an analytic field (grain, hammer marks, cast pitting) and the low copy carrying
the finished bevels. The low mesh is unwrapped into its variant's atlas cell, so
one material serves all three chests and a chest is one mesh with four surfaces.

Normals are OpenGL tangent space (+Y green up), which is what glTF and Godot
read. The exporter writes +Y up; Blender -Y (the front) becomes Godot -Z, so the
chest faces the same way its label does.

    python tools/build_reward_chests.py

runs Blender on this file in background mode. Intermediates and the
`preview_chests.png` beauty renders land in `.runtime/chest-build/`.
"""

from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pbr_bake as pbr  # noqa: E402
import prepare_cave_kit as cave  # noqa: E402
import prop_primitives as prop  # noqa: E402
from prop_primitives import add_cube, add_cylinder, add_shell, add_sphere, add_torus  # noqa: E402

SEED = 2412
TEX = {"wood": 2048, "iron": 1024, "gold": 1024, "gem": 512}
METALLIC = {"wood": 0.0, "iron": 0.62, "gold": 0.72, "gem": 0.0}
EMISSIVE = {"gem"}
# A 2x2 cell grid per atlas: three variants, one cell each, one left empty.
CELLS = {"island": (0.5, 0.0, 1.0, 0.5), "cache": (0.0, 0.0, 0.5, 0.5),
    "hoard": (0.0, 0.5, 0.5, 1.0)}
SPACING = 4.0

# One row per prop. `width` across, `depth` front to back, `body` the planked
# box, `dome` the lid's rise as a fraction of the half-depth, `staves` how many
# planks the lid is laid from. Metres, standing on the origin.
VARIANTS = [
    {"id": "island", "node": "Chest_Island", "width": 1.24, "depth": 0.80,
        "body": 0.56, "dome": 0.62, "staves": 9, "straps": 2, "brackets": True,
        "handles": True, "gilt_ribs": False, "spires": False, "crest": False},
    {"id": "cache", "node": "Chest_Cache", "width": 0.80, "depth": 0.52,
        "body": 0.30, "dome": 0.55, "staves": 5, "straps": 2, "brackets": False,
        "handles": False, "gilt_ribs": False, "spires": False, "crest": False},
    {"id": "hoard", "node": "Chest_Hoard", "width": 1.56, "depth": 1.00,
        "body": 0.68, "dome": 0.70, "staves": 12, "straps": 3, "brackets": True,
        "handles": True, "gilt_ribs": True, "spires": True, "crest": True},
]


def log(*parts) -> None:
    print("chests:", *parts, flush=True)


def _args() -> tuple[Path, Path]:
    """`-- <out_dir> [<work_dir>]`: these chests are authored from nothing, so
    there is no source pack to stage first."""
    argv = sys.argv
    if "--" not in argv or len(argv) - argv.index("--") < 2:
        raise SystemExit("usage: blender -b --python tools/prepare_reward_chests.py"
            " -- <out_dir> [<work_dir>]")
    rest = argv[argv.index("--") + 1:]
    root = Path(__file__).resolve().parent.parent
    work = Path(rest[1]) if len(rest) > 1 else root / ".runtime" / "chest-build"
    return Path(rest[0]).resolve(), work.resolve()


# --- the chest's frame ------------------------------------------------------


class Chest:
    """One prop's dimensions in metres, standing on its own origin. The lid is
    an elliptical vault, not a half-cylinder: a chest is wider than it is tall
    and a semicircular lid makes it read as a barrel."""

    def __init__(self, spec: dict):
        self.spec = spec
        self.width = spec["width"]
        self.depth = spec["depth"]
        self.radius = spec["depth"] * 0.5
        self.dome = self.radius * spec["dome"]
        self.plinth = 0.10
        self.body_h = spec["body"]
        self.lid_z = self.plinth + self.body_h
        self.top = self.lid_z + self.dome

    def arc(self, t: float, radial: float = 0.0) -> Vector:
        """A point on the lid's vault: t runs from the front edge (0) over the
        apex to the back edge (pi). `radial` lifts the point clear of the
        surface; the chest's front is -Y."""
        horizontal = self.radius + radial
        rise = self.dome + radial
        return Vector((0.0, -horizontal * math.cos(t), self.lid_z + rise * math.sin(t)))


def add_stave(bm, chest: Chest, x0: float, x1: float, t0: float, t1: float,
        thickness: float, cols: int = 4):
    """One plank of the vaulted lid, running the width of the chest. The outer
    skin sits on the lid's surface and the inner one a plank's thickness under
    it, so a seam between two staves is a real groove with two edges."""
    rows = 4
    u = np.linspace(x0, x1, rows)
    ts = np.linspace(t0, t1, cols + 1)
    outer = np.empty((rows, cols + 1, 3))
    inner = np.empty((rows, cols + 1, 3))
    for i, x in enumerate(u):
        for j, t in enumerate(ts):
            p = chest.arc(t)
            outer[i, j] = (x, p.y, p.z)
            q = chest.arc(t, -thickness)
            inner[i, j] = (x, q.y, q.z)
    vo = add_shell(bm, outer)
    vi = add_shell(bm, inner[::-1])
    for i in (0, rows - 1):
        for j in range(cols):
            bm.faces.new((vo[i][j], vo[i][j + 1], vi[rows - 1 - i][j + 1], vi[rows - 1 - i][j]))
    for j in (0, cols):
        for i in range(rows - 1):
            bm.faces.new((vo[i][j], vi[rows - 1 - i][j], vi[rows - 2 - i][j], vo[i + 1][j]))
    return vo


def add_strap(bm, chest: Chest, x: float, width: float, thickness: float,
        bottom: float, samples: int = 24):
    """An iron strap at `x`: down the front, over the vault, down the back. A
    rectangular section swept along the path, its inner skin on the wood."""
    half_w = width * 0.5
    path = []
    for z in np.linspace(bottom, chest.lid_z, 4)[:-1]:
        path.append(Vector((0.0, -chest.radius - 0.001, z)))
    for t in np.linspace(0.0, math.pi, samples):
        p = chest.arc(t, 0.001)
        path.append(Vector((0.0, p.y, p.z)))
    for z in np.linspace(chest.lid_z, bottom, 4)[1:]:
        path.append(Vector((0.0, chest.radius + 0.001, z)))
    grid = np.empty((len(path), 2, 3))
    for i, p in enumerate(path):
        grid[i, 0] = (x - half_w, p.y, p.z)
        grid[i, 1] = (x + half_w, p.y, p.z)
    inner = add_shell(bm, grid)
    outward = []
    for i, p in enumerate(path):
        if p.z > chest.lid_z - 1e-6 and abs(p.y) < chest.radius:
            span = chest.arc(math.atan2(p.z - chest.lid_z, -p.y), thickness)
            outward.append(Vector((0.0, span.y, span.z)))
        else:
            outward.append(Vector((0.0, p.y + (-thickness if p.y < 0 else thickness), p.z)))
    over = [[bm.verts.new((x - half_w if j == 0 else x + half_w,
        outward[i].y, outward[i].z)) for j in range(2)] for i in range(len(path))]
    for i in range(len(path) - 1):
        bm.faces.new((over[i][0], over[i + 1][0], over[i + 1][1], over[i][1]))
        bm.faces.new((inner[i][0], over[i][0], over[i + 1][0], inner[i + 1][0]))
        bm.faces.new((inner[i][1], inner[i + 1][1], over[i + 1][1], over[i][1]))
    for i in (0, len(path) - 1):
        bm.faces.new((inner[i][0], inner[i][1], over[i][1], over[i][0]))
    return path


# --- the four materials -----------------------------------------------------


def build_wood(chest: Chest, bm, high: bool):
    w, d, lid_z, plinth = chest.width, chest.depth, chest.lid_z, chest.plinth
    # Carcass: the solid box the planks are laid over, so a seam is never a hole.
    add_cube(bm, (0, 0, plinth + chest.body_h * 0.5),
        (w - 0.06, d - 0.06, chest.body_h), 0.01, 2)
    # Plinth and its four splayed feet.
    add_cube(bm, (0, 0, plinth * 0.5), (w + 0.10, d + 0.10, plinth), 0.014, 3)
    for sx in (-1, 1):
        for sy in (-1, 1):
            add_cube(bm, (sx * (w * 0.5 - 0.05), sy * (d * 0.5 - 0.05), 0.035),
                (0.20, 0.20, 0.07), 0.012, 2)
    # Cladding: vertical planks on the front and back, then the two ends.
    planks = 5
    gap = 0.012
    pw = (w - 0.10 - gap * (planks - 1)) / planks
    for sy in (-1, 1):
        for i in range(planks):
            x = -w * 0.5 + 0.05 + pw * 0.5 + i * (pw + gap)
            add_cube(bm, (x, sy * (d * 0.5 - 0.02), plinth + chest.body_h * 0.5),
                (pw, 0.045, chest.body_h - 0.02), 0.008, 2)
    side_planks = 3
    sw = (d - 0.12 - gap * (side_planks - 1)) / side_planks
    for sx in (-1, 1):
        for i in range(side_planks):
            y = -d * 0.5 + 0.06 + sw * 0.5 + i * (sw + gap)
            add_cube(bm, (sx * (w * 0.5 - 0.02), y, plinth + chest.body_h * 0.5),
                (0.045, sw, chest.body_h - 0.02), 0.008, 2)
    # Top plate: what closes the body under the lid.
    add_cube(bm, (0, 0, lid_z - 0.02), (w - 0.04, d - 0.04, 0.05), 0.008, 2)
    # The vaulted lid: staves side by side with a seam between each.
    staves = chest.spec["staves"]
    seam = 0.014
    span = (w - 0.10 - seam * (staves - 1)) / staves
    for i in range(staves):
        x0 = -w * 0.5 + 0.05 + i * (span + seam)
        add_stave(bm, chest, x0, x0 + span, 0.0, math.pi,
            0.055 if high else 0.05, 8 if high else 5)
    # The lid's end cheeks, so the vault reads as closed from the side.
    for sx in (-1, 1):
        x = sx * (w * 0.5 - 0.03)
        rows, cols = 3, 20
        outer = np.empty((rows, cols, 3))
        for j, t in enumerate(np.linspace(0.0, math.pi, cols)):
            p = chest.arc(t)
            for i, dz in enumerate(np.linspace(0.0, 0.05, rows)):
                outer[i, j] = (x + sx * dz * 0.4, p.y, p.z)
        add_shell(bm, outer)
    return bm


def build_iron(chest: Chest, bm, high: bool):
    w, d, lid_z, plinth = chest.width, chest.depth, chest.lid_z, chest.plinth
    straps = chest.spec["straps"]
    thickness = 0.026
    width = 0.085 if chest.spec["id"] != "cache" else 0.07
    xs = [-w * 0.26, w * 0.26] if straps == 2 else [-w * 0.30, 0.0, w * 0.30]
    for x in xs:
        add_strap(bm, chest, x, width, thickness, plinth * 0.6, 24 if high else 16)
        for i in range(5):
            t = math.pi * (i + 0.5) / 5.0
            p = chest.arc(t, thickness * 0.85)
            add_sphere(bm, (x, p.y, p.z), 0.024, 12, 7, (1.0, 1.0, 0.7))
        for z in (plinth + 0.10, lid_z - 0.09):
            add_sphere(bm, (x, -d * 0.5 - thickness, z), 0.024, 12, 7, (1.0, 1.0, 0.7))
            add_sphere(bm, (x, d * 0.5 + thickness, z), 0.024, 12, 7, (1.0, 1.0, 0.7))
    # Corner brackets: two plates an edge, wrapping each vertical corner.
    if chest.spec["brackets"]:
        for sx in (-1, 1):
            for sy in (-1, 1):
                add_cube(bm, (sx * (w * 0.5 + 0.012), sy * (d * 0.5 - 0.09),
                    plinth + chest.body_h * 0.5), (0.028, 0.11, chest.body_h * 0.92), 0.006, 2)
                add_cube(bm, (sx * (w * 0.5 - 0.09), sy * (d * 0.5 + 0.012),
                    plinth + chest.body_h * 0.5), (0.11, 0.028, chest.body_h * 0.92), 0.006, 2)
                for dz in (-0.32, 0.0, 0.32):
                    z = plinth + chest.body_h * 0.5 + dz * chest.body_h
                    add_sphere(bm, (sx * (w * 0.5 + 0.03), sy * (d * 0.5 - 0.09), z),
                        0.016, 8, 6, (1.0, 1.0, 0.75))
    # Hinges: two barrels at the back with their plates on the lid and body.
    for sx in (-1, 1):
        x = sx * w * 0.22
        add_cylinder(bm, (x, d * 0.5 + 0.02, lid_z), 0.032, 0.20, 16, "X", 0.004)
        add_cube(bm, (x, d * 0.5 - 0.05, lid_z - 0.055), (0.16, 0.10, 0.03), 0.006, 2)
        add_cube(bm, (x, d * 0.5 + 0.01, lid_z + 0.07), (0.16, 0.05, 0.10), 0.006, 2)
    # Ring handles on the two ends, each hanging off its own escutcheon.
    if chest.spec["handles"]:
        for sx in (-1, 1):
            centre = (sx * (w * 0.5 + 0.05), 0.0, plinth + chest.body_h * 0.62)
            add_torus(bm, centre, 0.10, 0.022, "X", 30 if high else 22, 8 if high else 6)
            add_cube(bm, (sx * (w * 0.5 + 0.012), 0.0, centre[2] + 0.115),
                (0.02, 0.22, 0.055), 0.008, 2)
    return bm


def build_gold(chest: Chest, bm, high: bool):
    w, d, lid_z, plinth = chest.width, chest.depth, chest.lid_z, chest.plinth
    # The plinth's gilt band and the lid's rim moulding.
    add_cube(bm, (0, 0, plinth - 0.012), (w + 0.14, d + 0.14, 0.032), 0.01, 2)
    for sx in (-1, 1):
        add_cube(bm, (sx * (w * 0.5 - 0.022), 0, lid_z + 0.012), (0.05, d + 0.02, 0.045),
            0.008, 2)
    for sy in (-1, 1):
        add_cube(bm, (0, sy * (d * 0.5 - 0.022), lid_z + 0.012), (w + 0.02, 0.05, 0.045),
            0.008, 2)
    # The hasp: a shield over the seam, its escutcheon, and the lock's eye.
    add_cube(bm, (0, -d * 0.5 - 0.04, lid_z + 0.01), (0.26, 0.05, 0.24), 0.020, 4)
    point = bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=0.012,
        radius2=0.135, depth=0.09)
    bmesh.ops.scale(bm, vec=Vector((1.0, 0.30, 1.0)), verts=point["verts"])
    bmesh.ops.translate(bm, vec=Vector((0, -d * 0.5 - 0.04, lid_z - 0.145)),
        verts=point["verts"])
    prop.bevel_verts(bm, point["verts"], 0.010, 3)
    add_cube(bm, (0, -d * 0.5 - 0.066, lid_z - 0.10), (0.16, 0.03, 0.13), 0.008, 2)
    add_torus(bm, (0, -d * 0.5 - 0.075, lid_z + 0.10), 0.05, 0.013, "Y", 24 if high else 18, 7)
    # A rosette on each lid cheek.
    for sx in (-1, 1):
        add_cylinder(bm, (sx * (w * 0.5 + 0.012), 0.0, lid_z + chest.dome * 0.55),
            0.085, 0.028, 20, "X", 0.006)
    # The hoard's gilt ribs across the vault.
    if chest.spec["gilt_ribs"]:
        for dt in (0.28, 0.5, 0.72):
            p = chest.arc(math.pi * dt, 0.02)
            add_cube(bm, (0, p.y, p.z), (w - 0.02, 0.05, 0.05), 0.01, 2)
    # Spires on the four plinth corners: a tapered post with a finial.
    if chest.spec["spires"]:
        for sx in (-1, 1):
            for sy in (-1, 1):
                bx, by = sx * (w * 0.5 - 0.02), sy * (d * 0.5 - 0.02)
                add_cylinder(bm, (bx, by, plinth + 0.18), 0.045, 0.30, 12, "Z", 0.006, 0.55)
                add_sphere(bm, (bx, by, plinth + 0.35), 0.045, 12, 8)
    # The crest over the vault's apex: three prongs and a cross-bar.
    if chest.spec["crest"]:
        apex = chest.top
        add_cube(bm, (0, 0, apex + 0.02), (0.44, 0.10, 0.055), 0.012, 2)
        for dx in (-0.15, 0.0, 0.15):
            add_cylinder(bm, (dx, 0, apex + 0.10), 0.028, 0.14, 10, "Z", 0.005, 0.4)
        add_cube(bm, (0, 0, apex + 0.18), (0.30, 0.055, 0.05), 0.01, 2)
    return bm


def add_gem(bm, center, radius: float, scale=(1.0, 1.0, 1.0)):
    """A cut stone: a twenty-face icosahedron, flattened across its depth so it
    sits in a bezel. Facets catch one light at a time, which is the whole read."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    verts = res["verts"]
    bmesh.ops.scale(bm, vec=Vector(scale), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    return verts


def build_gem(chest: Chest, bm, high: bool):
    w, d, lid_z = chest.width, chest.depth, chest.lid_z
    # A cut stone, not a bead: a faceted icosahedron in a flat bezel.
    add_cylinder(bm, (0, -d * 0.5 - 0.072, lid_z - 0.02), 0.075, 0.03, 20, "Y", 0.006)
    add_gem(bm, (0, -d * 0.5 - 0.088, lid_z - 0.02), 0.062, (1.0, 0.72, 1.0))
    if chest.spec["id"] != "cache":
        for sx in (-1, 1):
            add_gem(bm, (sx * 0.20, -d * 0.5 - 0.062, lid_z + 0.15), 0.034, (1.0, 0.8, 1.0))
    if chest.spec["spires"]:
        for sx in (-1, 1):
            for sy in (-1, 1):
                add_gem(bm, (sx * (w * 0.5 - 0.02), sy * (d * 0.5 - 0.02),
                    chest.plinth + 0.42), 0.038, (1.0, 0.8, 1.0))
    if chest.spec["crest"]:
        add_gem(bm, (0, 0, chest.top + 0.13), 0.052, (1.0, 0.62, 1.0))
    return bm


BUILD = {"wood": build_wood, "iron": build_iron, "gold": build_gold, "gem": build_gem}


# --- analytic relief for the high-detail copy -------------------------------


def relief(group: str, co: np.ndarray) -> np.ndarray:
    """Height field, in metres. Grain and hammering are displacement that the
    normal bake turns into a tangent map; the low mesh keeps only its bevels."""
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    if group == "wood":
        grain = np.sin(x * 92.0 + 5.0 * cave.fbm(x * 2.0, y * 2.0, z * 2.0, 3))
        knot = cave.fbm(x * 17.0, y * 30.0, z * 30.0, 3) - 0.5
        return 0.0013 * grain + 0.0007 * knot
    if group == "iron":
        hammer = cave.fbm(x * 26.0, y * 26.0, z * 26.0, 3) - 0.5
        pits = cave.fbm(x * 90.0, y * 90.0, z * 90.0, 2) - 0.5
        return 0.0026 * hammer + 0.0011 * pits
    if group == "gold":
        return 0.0009 * (cave.fbm(x * 55.0, y * 55.0, z * 55.0, 2) - 0.5)
    return np.zeros(len(co))


def displace(obj, group: str) -> None:
    """Subdivide the low mesh and push it along its normals by `relief`: the
    dense surface the tangent normal is baked down from."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=2, use_grid_fill=True)
    bm.normal_update()
    co = np.array([(v.co.x, v.co.y, v.co.z) for v in bm.verts])
    heights = relief(group, co)
    for vert, height in zip(bm.verts, heights):
        vert.co += vert.normal * float(height)
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.shade_smooth()


# --- procedural source materials --------------------------------------------
#
# The pigment network is pure data - base colour and roughness from noise, rings
# and tarnish - and `pbr_bake` reads it twice: once through an Emission shader
# for the COLOR pass, once through a Principled body for the roughness pass.
# Scene light never enters it, so nothing is baked as glare.


def pigment_graph(nodes, links, group: str):
    """The material's own signals: (base colour, roughness) sockets."""
    coord = nodes.new("ShaderNodeTexCoord")
    gain = nodes.new("ShaderNodeTexNoise")
    gain.inputs["Scale"].default_value = 4.0
    gain.inputs["Detail"].default_value = 6.0
    gain.inputs["Roughness"].default_value = 0.55
    links.new(coord.outputs["Object"], gain.inputs["Vector"])
    if group == "wood":
        # Growth rings: bands across the planks' width, warped by the noise so
        # they are not a corduroy pattern. Along X, which is the front planks'
        # short axis and the vault staves' long one - correct for both.
        rings = nodes.new("ShaderNodeTexWave")
        rings.bands_direction = "X"
        rings.wave_profile = "SIN"
        rings.inputs["Scale"].default_value = 52.0
        rings.inputs["Distortion"].default_value = 5.0
        rings.inputs["Detail"].default_value = 3.0
        rings.inputs["Detail Scale"].default_value = 2.0
        links.new(coord.outputs["Object"], rings.inputs["Vector"])
        grain = cave._range(nodes, links, rings.outputs["Fac"], 0.26, 0.78)
        pigment = cave._mix(nodes, links, "MIX", grain,
            (0.0240, 0.0122, 0.0068), (0.0780, 0.0410, 0.0205))
        # A little board-to-board tone, at low contrast: sapwood, not paint.
        board = nodes.new("ShaderNodeTexNoise")
        board.inputs["Scale"].default_value = 16.0
        board.inputs["Detail"].default_value = 4.0
        links.new(coord.outputs["Object"], board.inputs["Vector"])
        tone = pbr.remap(nodes, links, board.outputs["Fac"], 0.93, 1.07)
        base = cave._mix(nodes, links, "MULTIPLY", 1.0, pigment, tone)
        return base, pbr.remap(nodes, links, grain, 0.44, 0.70)
    if group == "iron":
        patina = cave._range(nodes, links, gain.outputs["Fac"], 0.46, 0.88)
        pigment = cave._mix(nodes, links, "MIX", patina,
            (0.072, 0.078, 0.086), (0.120, 0.080, 0.060))
        return pigment, pbr.remap(nodes, links, patina, 0.30, 0.58)
    if group == "gold":
        tarnish = cave._range(nodes, links, gain.outputs["Fac"], 0.40, 0.78)
        pigment = cave._mix(nodes, links, "MIX", tarnish,
            (0.640, 0.436, 0.126), (0.395, 0.268, 0.092))
        return pigment, pbr.remap(nodes, links, tarnish, 0.16, 0.38)
    facet = cave._range(nodes, links, gain.outputs["Fac"], 0.45, 0.95)
    pigment = cave._mix(nodes, links, "MIX", facet,
        (0.215, 0.185, 0.150), (0.560, 0.500, 0.410))
    return pigment, None


# --- unwrap, bake, compose --------------------------------------------------


def unwrap(obj, cell) -> None:
    cave.smart_uv(obj, cell)


# --- build, bake, preview, export -------------------------------------------


def build_all() -> list:
    made = []
    for spec in VARIANTS:
        chest = Chest(spec)
        groups = {}
        for group in ("wood", "iron", "gold", "gem"):
            low = prop.finish(f"{spec['node']}_{group}_low",
                BUILD[group](chest, bmesh.new(), False))
            high = prop.finish(f"{spec['node']}_{group}_high",
                BUILD[group](chest, bmesh.new(), True), smooth=True)
            displace(high, group)
            cave.smart_uv(low, CELLS[spec["id"]])
            groups[group] = (low, high)
            log(spec["id"], group, "low", cave.triangles(low), "high", cave.triangles(high))
        made.append({"spec": spec, "chest": chest, "groups": groups})
    return made


def bake_all(made: list, out_dir: Path, work: Path, report: dict) -> None:
    for group in ("wood", "iron", "gold", "gem"):
        pieces = []
        for index, entry in enumerate(made):
            low, high = entry["groups"][group]
            offset = index * SPACING
            low.location.x = offset
            high.location.x = offset
            pieces.append({"low": low, "high": high, "offset": offset,
                "cage": 0.06 + 0.02 * float(entry["spec"]["id"] == "hoard")})
        graph = (lambda nodes, links, _group=group: pigment_graph(nodes, links, _group))
        baked = pbr.bake_group(pieces, work, f"chest_{group}", TEX[group],
            METALLIC[group], graph, emit=group in EMISSIVE)
        material = cave.final_material(f"Chest_{group.capitalize()}", baked["files"])
        pbr.ship(out_dir, f"chest_{group}", baked, report, METALLIC[group], key=group)
        for entry in made:
            low, high = entry["groups"][group]
            low.data.materials.clear()
            low.data.materials.append(material)
            low.location.x = 0.0
            bpy.data.objects.remove(high, do_unlink=True)


def stage_preview(objects: list) -> None:
    """A lit stage for the beauty renders: three area lights a metal can
    actually reflect, and a floor. This is presentation only - the maps above
    carry no light."""
    scene = bpy.context.scene
    span = 0.0
    for obj in objects:
        obj.location.x = span + obj.dimensions.x * 0.5
        span += obj.dimensions.x + 1.1
    centre = (span - 1.1) * 0.5
    bpy.ops.mesh.primitive_plane_add(size=60.0, location=(centre, 0.0, -0.002))
    ground = bpy.context.active_object
    ground_mat = bpy.data.materials.new("PreviewGround")
    ground_mat.use_nodes = True
    ground_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"] \
        .default_value = (0.045, 0.038, 0.032, 1.0)
    ground.data.materials.append(ground_mat)
    for name, at, energy, colour, size in (
            ("Key", (centre - 2.8, -3.6, 3.1), 460.0, (1.0, 0.82, 0.62), 2.2),
            ("Fill", (centre + 3.6, -2.4, 2.1), 190.0, (0.66, 0.76, 1.0), 2.6),
            ("Rim", (centre + 0.5, 2.8, 2.4), 300.0, (1.0, 0.46, 0.30), 2.0)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.color = colour
        light.size = size
        obj = bpy.data.objects.new(name, light)
        obj.location = at
        direction = Vector((centre, 0.0, 0.45)) - Vector(at)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)
    scene.world.color = (0.075, 0.070, 0.066)
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"
    scene.render.image_settings.color_mode = "RGB"
    return centre, span


def render_preview(objects: list, work: Path) -> None:
    scene = bpy.context.scene
    centre, span = stage_preview(objects)
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 55.0
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    # Frame the whole row: the sensor is 36 mm wide, so the half-angle is
    # atan(18 / lens) and the distance follows from the width that must fit.
    half_angle = math.atan(18.0 / camera_data.lens)
    distance = (span * 0.55) / math.tan(half_angle) * 1.15
    target = Vector((centre, 0.0, 0.42))
    camera.location = (centre, -distance, 0.42 + distance * 0.16)
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 720
    scene.cycles.samples = 128
    scene.render.filepath = str(work / "preview_chests.png")
    bpy.ops.render.render(write_still=True)
    log("preview", scene.render.filepath)
    # A close pass on the island chest, where the grain and rivets are read.
    island = objects[0]
    camera_data.lens = 68.0
    camera.location = (island.location.x - 0.62, -1.85, 0.78)
    target = Vector((island.location.x, 0.0, 0.44))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.cycles.samples = 160
    scene.render.filepath = str(work / "preview_chest_close.png")
    bpy.ops.render.render(write_still=True)
    log("preview", scene.render.filepath)


def main() -> None:
    started = time.time()
    out_dir, work = _args()
    work.mkdir(parents=True, exist_ok=True)
    (out_dir / "textures").mkdir(parents=True, exist_ok=True)
    report = {
        "generator": "tools/prepare_reward_chests.py",
        "builder": "python tools/build_reward_chests.py",
        "blender": bpy.app.version_string,
        "seed": SEED,
        "license": "CC BY-NC-SA 4.0 (LICENSE.md section 3); original geometry and bakes",
        "conventions": {
            "axes": "Godot +Y up; the chest front faces -Z; stands on its origin",
            "albedo": "sRGB, pigment only (no baked lighting)",
            "normal": "OpenGL tangent (+Y green up)",
            "orm": "R occlusion, G roughness, B metallic (glTF metallicRoughness)",
            "gem": "the only emissive material; tinted per tier at runtime",
        },
        "variants": {},
        "textures": {},
    }
    cave.reset_scene()
    made = build_all()
    bake_all(made, out_dir, work, report)
    objects = []
    for entry in made:
        joined = pbr.join_group(
            [entry["groups"][group][0] for group in ("wood", "iron", "gold", "gem")],
            entry["spec"]["node"])
        prop.triangulate(joined)
        objects.append(joined)
    for obj, entry in zip(objects, made):
        co = np.empty(len(obj.data.vertices) * 3, np.float32)
        obj.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        # Godot frame: x, z, -y.
        godot = np.stack([co[:, 0], co[:, 2], -co[:, 1]], axis=-1)
        report["variants"][entry["spec"]["id"]] = {
            "node": obj.name,
            "triangles": cave.triangles(obj),
            "materials": sorted(slot.name for slot in obj.data.materials),
            "min": [round(float(v), 4) for v in godot.min(axis=0)],
            "max": [round(float(v), 4) for v in godot.max(axis=0)],
        }
    render_preview(objects, work)
    path = out_dir / "reward_chests.glb"
    cave.export_glb(path, objects, vertex_colours=False)
    report["file"] = {"name": path.name, "sha256": cave.sha256(path),
        "bytes": path.stat().st_size}
    report["build_seconds"] = round(time.time() - started, 1)
    (out_dir / "reward_chests.json").write_text(json.dumps(report, indent=1) + "\n",
        encoding="utf-8")
    log("done", report["build_seconds"], "s")


if __name__ == "__main__":
    main()
