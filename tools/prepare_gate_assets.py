"""Author the run's three gates: real doorways, not boxes with flat colours.

A gate used to be a stack of `Geo.box` primitives under a `StandardMaterial3D`
colour - a grey post, a black post, a red post. These are the doors themselves:
coursed granite for the wood's own gate, black basalt hung with bone for the
devils', and a body turned inside out for the clones'. Each is built here as
geometry and baked in Cycles into per-material PBR, through the same bake the
chests use (`tools/pbr_bake.py`).

Five materials, one atlas each, shared by the three variants:

    Gate_Granite  2048  ashlar courses, chisel marks, moss in the crevices
    Gate_Basalt   1024  the devils' rock: near-black, broken, porous
    Gate_Bone     1024  crania, ribs, talons - pitted, not polished
    Gate_Flesh    1024  the clones' columns, sinew and heart
    Gate_Iron     1024  straps, sockets, spikes and hooks

The glowing sheet is NOT here: its colour is the biome's promise, so the runtime
lays it in the opening and owns the lamp (`scripts/roguelite/gate_visual.gd`).

Footprint matches the primitive gate it replaces, so interaction framing, gate
spacing and the plaques above it do not move: posts on x = +-1.30, lintel at
3.4 m, an opening 2.2 m wide and 2.9 m tall.

    python tools/build_gate_assets.py
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
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pbr_bake as pbr  # noqa: E402
import prepare_cave_kit as cave  # noqa: E402
import prop_primitives as prop  # noqa: E402
from prop_primitives import add_cube, add_cylinder, add_shell, add_sphere, add_torus  # noqa: E402

SEED = 9021
TEX = {"granite": 2048, "basalt": 1024, "bone": 1024, "flesh": 1024, "iron": 1024}
METALLIC = {"granite": 0.0, "basalt": 0.0, "bone": 0.0, "flesh": 0.0, "iron": 0.55}
# 2x2 cells per atlas: a material is used by at most three variants.
CELLS = {
    "granite": {"watchers": (0.0, 0.0, 1.0, 1.0)},
    "basalt": {"demons": (0.0, 0.0, 1.0, 1.0)},
    "bone": {"demons": (0.0, 0.0, 0.5, 1.0), "clones": (0.5, 0.0, 1.0, 1.0)},
    "flesh": {"clones": (0.0, 0.0, 1.0, 1.0)},
    "iron": {"watchers": (0.0, 0.0, 0.5, 0.5), "demons": (0.5, 0.0, 1.0, 0.5),
        "clones": (0.0, 0.5, 0.5, 1.0)},
}
SPACING = 5.0

VARIANTS = [
    {"id": "watchers", "node": "Gate_Watchers", "groups": ("granite", "iron")},
    {"id": "demons", "node": "Gate_Demons", "groups": ("basalt", "bone", "iron")},
    {"id": "clones", "node": "Gate_Clones", "groups": ("flesh", "bone", "iron")},
]

POST_X = 1.30
POST_W = 0.60
POST_D = 0.62
LINTEL_Z = 3.40


def log(*parts) -> None:
    print("gates:", *parts, flush=True)


def _args() -> tuple[Path, Path]:
    argv = sys.argv
    if "--" not in argv or len(argv) - argv.index("--") < 2:
        raise SystemExit("usage: blender -b --python tools/prepare_gate_assets.py"
            " -- <out_dir> [<work_dir>]")
    rest = argv[argv.index("--") + 1:]
    root = Path(__file__).resolve().parent.parent
    work = Path(rest[1]) if len(rest) > 1 else root / ".runtime" / "gate-build"
    return Path(rest[0]).resolve(), work.resolve()


# --- shapes the doors need --------------------------------------------------


def rough_prism(bm, centre, radius: float, height: float, sides: int, salt: float,
        taper: float = 1.0):
    """A broken column segment: a low-sided cylinder whose every ring is pushed
    in and out by a seeded field, so the silhouette is rock and not a tube."""
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides,
        radius1=radius, radius2=radius * taper, depth=height)
    verts = res["verts"]
    for vert in verts:
        jitter = cave.fbm(vert.co.x * 3.1 + salt, vert.co.y * 3.1, vert.co.z * 3.1, 3)
        vert.co.x += (jitter - 0.5) * radius * 0.85
        vert.co.y += (jitter - 0.5) * radius * 0.85
    bmesh.ops.translate(bm, vec=Vector(centre), verts=verts)
    return verts


def swept_column(bm, z0: float, z1: float, centre_x: float, centre_y: float,
        radius: float, rings: int = 12, sides: int = 14, twist: float = 0.0,
        salt: float = 0.0, flare: float = 0.0):
    """A column swept from rings whose radius swells with a noise field: the
    clones' posts are muscle, so the surface has to be irregular everywhere."""
    rows = []
    for row in range(rings + 1):
        t = row / rings
        z = z0 + (z1 - z0) * t
        ring = []
        for side in range(sides):
            angle = math.tau * side / sides + twist * t
            swell = 1.0 + flare * t
            wobble = 0.82 + 0.36 * cave.fbm(
                math.cos(angle) * 2.0 + salt, math.sin(angle) * 2.0, z * 1.7, 3)
            r = radius * swell * wobble
            ring.append(bm.verts.new((centre_x + math.cos(angle) * r,
                centre_y + math.sin(angle) * r, z)))
        rows.append(ring)
    for row in range(rings):
        for side in range(sides):
            nxt = (side + 1) % sides
            bm.faces.new((rows[row][side], rows[row][nxt], rows[row + 1][nxt],
                rows[row + 1][side]))
    bm.faces.new(rows[0][::-1])
    bm.faces.new(rows[-1])
    return rows


def arc_tube(bm, centre, radius: float, thickness: float, t0: float, t1: float,
        plane: str = "YZ", samples: int = 10, sides: int = 6):
    """A curved bone: a tube swept along an arc, for ribs and talons."""
    path = []
    for step in range(samples + 1):
        t = t0 + (t1 - t0) * step / samples
        if plane == "YZ":
            path.append(Vector((centre[0], centre[1] + math.cos(t) * radius,
                centre[2] + math.sin(t) * radius)))
        else:
            path.append(Vector((centre[0] + math.cos(t) * radius, centre[1],
                centre[2] + math.sin(t) * radius)))
    rings = []
    for index, point in enumerate(path):
        forward = (path[min(index + 1, len(path) - 1)] - path[max(index - 1, 0)])
        forward = forward.normalized() if forward.length > 1e-6 else Vector((0, 1, 0))
        side = forward.cross(Vector((1, 0, 0)))
        if side.length < 1e-6:
            side = Vector((0, 0, 1))
        side.normalize()
        up = forward.cross(side).normalized()
        ring = []
        for k in range(sides):
            angle = math.tau * k / sides
            offset = side * (math.cos(angle) * thickness) + up * (math.sin(angle) * thickness)
            ring.append(bm.verts.new(point + offset))
        rings.append(ring)
    for index in range(len(rings) - 1):
        for k in range(sides):
            nxt = (k + 1) % sides
            bm.faces.new((rings[index][k], rings[index][nxt], rings[index + 1][nxt],
                rings[index + 1][k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    return rings


## Where the devils' skulls hang: three a post, at these heights.
SKULL_ROWS = (1.15, 2.05, 2.92)


def skull_at(side: int, row: int):
    """One skull's centre and size. Bones and iron bake into different atlases,
    so the sockets are derived from this rather than carried across builds."""
    return (side * POST_X, -0.34, SKULL_ROWS[row]), 0.17 + 0.01 * row


def skull_sockets() -> list:
    """Two iron stones a skull, set proud of the bone so they catch no light."""
    out = []
    for side in (-1, 1):
        for row in range(len(SKULL_ROWS)):
            centre, size = skull_at(side, row)
            for eye in (-1, 1):
                out.append(((centre[0] + eye * size * 0.40,
                    centre[1] - size * 0.86, centre[2] + size * 0.10), size * 0.31))
    return out


def rib_ring(bm, centre, major: float, minor: float, high: bool):
    """A bone band round a column: far more legible than an arc hanging in the
    air, and it reads as a ribcage binding a body at any distance."""
    add_torus(bm, centre, major, minor, "Z", 26 if high else 18, 8 if high else 6)


def skull(bm, centre, size: float):
    """A cranium with its jaw and a heavy brow. The lightless eyes are iron and
    go in that mesh."""
    add_sphere(bm, centre, size, 14, 10, (1.0, 0.95, 0.88))
    add_cube(bm, (centre[0], centre[1] + size * 0.10, centre[2] - size * 0.92),
        (size * 1.05, size * 0.72, size * 0.42), size * 0.10, 2)
    add_cube(bm, (centre[0], centre[1] - size * 0.66, centre[2] + size * 0.42),
        (size * 1.16, size * 0.34, size * 0.30), size * 0.08, 2)


# --- the three doors --------------------------------------------------------


def build_granite(variant: str, bm, high: bool):
    """Coursed ashlar: three blocks a post, a heavy lintel on corbels, a proud
    keystone. Each course is turned a degree or two off the last, so the wall
    reads as laid stone rather than an extruded rectangle."""
    block = 0.46 if not high else 0.48
    for side in (-1, 1):
        x = side * POST_X
        add_cube(bm, (x, 0.0, 0.08), (POST_W + 0.12, POST_D + 0.12, 0.16), 0.018, 3)
        z = 0.16
        for index, height in enumerate((1.02, 1.06, 0.98)):
            tilt = math.radians(0.9 * (1 if index % 2 else -1))
            centre = (x + 0.005 * (index - 1), 0.0, z + height * 0.5)
            # Turn the course before it is bevelled: a bevel replaces the corner
            # vertices, so a handle taken before it is stale afterwards.
            verts = add_cube(bm, centre, (block, POST_D + 0.02, height), 0.0, 2)
            bmesh.ops.rotate(bm, cent=centre, matrix=Matrix.Rotation(tilt, 4, "Y"),
                verts=verts)
            prop.bevel_verts(bm, verts, 0.020, 3)
            z += height
        # A raised pilaster down the outward face: the carved band.
        add_cube(bm, (x + side * (POST_W * 0.5 + 0.004), 0.0, 1.6),
            (0.05, 0.20, 2.6), 0.010, 2)
    # Corbels, then the lintel and its keystone.
    for side in (-1, 1):
        add_cube(bm, (side * POST_X, 0.0, 3.24), (0.34, POST_D + 0.04, 0.14), 0.012, 2)
    add_cube(bm, (0.0, 0.0, LINTEL_Z), (3.20, POST_D + 0.06, 0.52), 0.022, 3)
    # The keystone drops below the beam, where an arch's key would be.
    add_cube(bm, (0.0, -0.02, LINTEL_Z - 0.36), (0.40, POST_D + 0.02, 0.28), 0.016, 3)
    add_cylinder(bm, (0.0, -0.34, LINTEL_Z - 0.02), 0.10, 0.04, 16, "Y", 0.006)
    return bm


def build_basalt(variant: str, bm, high: bool):
    """The devils' rock: their gate is a break in the stone, so the posts are
    stacks of broken prisms of different widths and the lintel is a slab with
    teeth hanging off its underside."""
    sides = 7 if high else 5
    for side in (-1, 1):
        x = side * POST_X
        add_cube(bm, (x, 0.0, 0.10), (POST_W + 0.20, POST_D + 0.20, 0.20), 0.026, 3)
        z = 0.20
        for index, (height, radius) in enumerate(((0.86, 0.30), (0.94, 0.27),
                (0.86, 0.25), (0.50, 0.22))):
            rough_prism(bm, (x + 0.02 * (index - 1), 0.0, z + height * 0.5),
                radius, height, sides, salt=index * 3.7 + side, taper=0.92)
            z += height
    add_cube(bm, (0.0, 0.0, LINTEL_Z), (3.28, POST_D + 0.10, 0.54), 0.026, 3)
    # Teeth: a row of downward cones under the lintel.
    for step in range(7):
        x = -1.20 + 0.40 * step
        add_cylinder(bm, (x, -0.10, LINTEL_Z - 0.34), 0.075, 0.20, 6, "Z", 0.004, 0.05)
    return bm


def build_flesh(variant: str, bm, high: bool):
    """A body turned inside out: two columns of muscle, a mass across the top,
    and a heart hanging off it with its veins running back into the lintel."""
    for side in (-1, 1):
        swept_column(bm, 0.0, 3.30, side * POST_X, 0.0, 0.26, 16 if high else 10,
            16 if high else 11, twist=side * 0.6, salt=side * 2.0, flare=0.18)
        add_sphere(bm, (side * POST_X, 0.0, 0.06), 0.30, 12, 8, (1.0, 1.0, 0.55))
    # The lintel: a slab of the same flesh, lumped so it reads as tissue laid
    # across the two columns rather than as a beam.
    add_cube(bm, (0.0, 0.0, LINTEL_Z), (3.10, POST_D * 0.86, 0.36), 0.03, 3)
    for step in range(6):
        add_sphere(bm, (-1.35 + 0.54 * step, 0.0, LINTEL_Z + 0.02), 0.30, 14, 10,
            (1.0, 0.94, 0.88))
    # The heart, and two veins up into the mass.
    add_sphere(bm, (0.0, -0.30, LINTEL_Z - 0.44), 0.26, 14, 10, (1.0, 1.12, 0.92))
    add_sphere(bm, (0.17, -0.30, LINTEL_Z - 0.26), 0.16, 12, 8)
    add_sphere(bm, (-0.16, -0.30, LINTEL_Z - 0.28), 0.14, 12, 8)
    for side in (-1, 1):
        arc_tube(bm, (side * 0.14, -0.28, LINTEL_Z - 0.66), 0.26, 0.035,
            -math.pi * 0.15, math.pi * 0.55, "YZ", 6 if high else 4, 6)
    return bm


def build_bone(variant: str, bm, high: bool):
    if variant == "demons":
        for side in (-1, 1):
            for row in range(len(SKULL_ROWS)):
                centre, size = skull_at(side, row)
                skull(bm, centre, size)
            # Talons: three bone spikes off the top of each post.
            for step in range(3):
                arc_tube(bm, (side * POST_X, 0.06, 3.05), 0.34, 0.045,
                    math.pi * (0.05 + 0.22 * step), math.pi * (0.45 + 0.16 * step),
                    "XZ", 5 if high else 3, 6)
        # Ribs caught between the posts.
        for step in range(7):
            x = -1.05 + 0.35 * step
            arc_tube(bm, (x, 0.10, LINTEL_Z - 0.12), 0.30, 0.038,
                math.pi * 0.15, math.pi * 0.92, "YZ", 7 if high else 5, 6)
    else:
        # The clones' ribcage: a bone band round each column, and a sternum down
        # the front of it.
        for side in (-1, 1):
            x = side * POST_X
            for step in range(6):
                z = 0.52 + 0.50 * step
                rib_ring(bm, (x, 0.0, z), 0.305 + 0.006 * (step % 2), 0.034, high)
            add_cylinder(bm, (x, -0.30, 1.72), 0.042, 2.5, 8, "Z", 0.006, 0.9)
    return bm


def build_iron(variant: str, bm, high: bool):
    """Straps, sockets, spikes and hooks: the fittings every one of the three
    doors has some of."""
    if variant == "watchers":
        for side in (-1, 1):
            x = side * POST_X
            add_cube(bm, (x, 0.0, 3.14), (POST_W + 0.08, POST_D + 0.08, 0.07), 0.012, 2)
            add_cube(bm, (x, 0.0, 0.17), (POST_W + 0.09, POST_D + 0.09, 0.06), 0.010, 2)
            for step in range(4):
                add_sphere(bm, (x, -POST_D * 0.5 - 0.01, 0.40 + 0.62 * step),
                    0.022, 8, 6, (1.0, 1.0, 0.7))
        for side in (-1, 1):
            add_cube(bm, (side * 0.80, 0.0, LINTEL_Z), (0.10, POST_D + 0.10, 0.52),
                0.010, 2)
    elif variant == "demons":
        for side in (-1, 1):
            x = side * POST_X
            for step in range(2):
                add_cube(bm, (x, 0.0, 0.95 + 1.28 * step),
                    (POST_W + 0.12, POST_D + 0.12, 0.09), 0.014, 2)
            for step in range(3):
                add_cylinder(bm, (x - 0.10 + 0.10 * step, 0.16, 3.02 + 0.10 * step),
                    0.035, 0.42, 6, "Z", 0.004, 0.0)
        for step in range(4):
            add_sphere(bm, (-1.05 + 0.70 * step, -0.02, LINTEL_Z + 0.30), 0.06, 8, 6)
        for centre, radius in skull_sockets():
            add_sphere(bm, centre, radius, 8, 6, (1.0, 1.0, 0.6))
    else:
        for side in (-1, 1):
            x = side * POST_X
            for step in range(2):
                add_torus(bm, (x + 0.28 * -side, -0.22, 1.20 + 1.10 * step), 0.10, 0.022,
                    "X", 20 if high else 14, 6)
            add_cube(bm, (x, 0.0, 0.16), (0.42, POST_D + 0.06, 0.07), 0.010, 2)
        # The heart is held in a ring of iron.
        add_torus(bm, (0.0, -0.30, LINTEL_Z - 0.44), 0.34, 0.026, "Y", 26 if high else 18, 6)
    return bm


BUILDERS = {"granite": build_granite, "basalt": build_basalt, "flesh": build_flesh,
    "bone": build_bone, "iron": build_iron}


# --- relief and pigment -----------------------------------------------------


def relief(group: str, co: np.ndarray) -> np.ndarray:
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    if group in ("granite", "basalt"):
        chisel = cave.fbm(x * 60.0, y * 60.0, z * 60.0, 3) - 0.5
        pits = cave.fbm(x * 160.0, y * 160.0, z * 160.0, 2) - 0.5
        scale = 1.0 if group == "granite" else 1.8
        return scale * (0.0022 * chisel + 0.0009 * pits)
    if group == "bone":
        pores = cave.fbm(x * 130.0, y * 130.0, z * 130.0, 3) - 0.5
        return 0.0014 * pores
    if group == "flesh":
        wrinkle = cave.fbm(x * 34.0, y * 34.0, z * 34.0, 4) - 0.5
        fine = cave.fbm(x * 110.0, y * 110.0, z * 110.0, 2) - 0.5
        return 0.0032 * wrinkle + 0.0008 * fine
    hammer = cave.fbm(x * 40.0, y * 40.0, z * 40.0, 3) - 0.5
    return 0.0020 * hammer


def displace(obj, group: str) -> None:
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


def pigment_graph(nodes, links, group: str):
    coord = nodes.new("ShaderNodeTexCoord")
    gain = nodes.new("ShaderNodeTexNoise")
    gain.inputs["Scale"].default_value = 5.0
    gain.inputs["Detail"].default_value = 7.0
    gain.inputs["Roughness"].default_value = 0.6
    links.new(coord.outputs["Object"], gain.inputs["Vector"])
    if group == "granite":
        # Coursed stone: grey with a warm cast, dark mineral speckle, and moss
        # settling where the noise pools - pigment, never a green light.
        speckle = cave._range(nodes, links, gain.outputs["Fac"], 0.30, 0.86)
        stone = cave._mix(nodes, links, "MIX", speckle,
            (0.066, 0.064, 0.057), (0.178, 0.170, 0.152))
        # Moss pools where the noise does and only there: at full weight the
        # whole post turns copper-green, so the tint stays a stain.
        moss = cave._range(nodes, links, gain.outputs["Fac"], 0.74, 0.99)
        base = cave._mix(nodes, links, "MULTIPLY", moss, stone, (0.70, 0.78, 0.58))
        return base, pbr.remap(nodes, links, speckle, 0.74, 0.95)
    if group == "basalt":
        speckle = cave._range(nodes, links, gain.outputs["Fac"], 0.28, 0.90)
        base = cave._mix(nodes, links, "MIX", speckle,
            (0.020, 0.019, 0.022), (0.070, 0.062, 0.066))
        return base, pbr.remap(nodes, links, speckle, 0.74, 0.95)
    if group == "bone":
        stain = cave._range(nodes, links, gain.outputs["Fac"], 0.30, 0.82)
        base = cave._mix(nodes, links, "MIX", stain,
            (0.098, 0.090, 0.066), (0.290, 0.264, 0.196))
        return base, pbr.remap(nodes, links, stain, 0.46, 0.74)
    if group == "flesh":
        sinew = cave._range(nodes, links, gain.outputs["Fac"], 0.36, 0.90)
        base = cave._mix(nodes, links, "MIX", sinew,
            (0.072, 0.011, 0.014), (0.235, 0.055, 0.052))
        return base, pbr.remap(nodes, links, sinew, 0.30, 0.58)
    rust = cave._range(nodes, links, gain.outputs["Fac"], 0.40, 0.88)
    base = cave._mix(nodes, links, "MIX", rust,
        (0.045, 0.047, 0.052), (0.115, 0.070, 0.048))
    return base, pbr.remap(nodes, links, rust, 0.34, 0.62)


# --- build, bake, preview, export -------------------------------------------


def build_all() -> list:
    made = []
    for spec in VARIANTS:
        groups = {}
        for group in spec["groups"]:
            builder = BUILDERS[group]
            low = prop.finish(f"{spec['node']}_{group}_low",
                builder(spec["id"], bmesh.new(), False))
            high = prop.finish(f"{spec['node']}_{group}_high",
                builder(spec["id"], bmesh.new(), True), smooth=True)
            displace(high, group)
            cave.smart_uv(low, CELLS[group][spec["id"]])
            groups[group] = (low, high)
            log(spec["id"], group, "low", cave.triangles(low), "high", cave.triangles(high))
        made.append({"spec": spec, "groups": groups})
    return made


def bake_all(made: list, out_dir: Path, work: Path, report: dict) -> None:
    for group in ("granite", "basalt", "bone", "flesh", "iron"):
        pieces = []
        for index, entry in enumerate(made):
            if group not in entry["groups"]:
                continue
            low, high = entry["groups"][group]
            offset = index * SPACING
            low.location.x = offset
            high.location.x = offset
            pieces.append({"low": low, "high": high, "offset": offset,
                "cage": 0.10 + 0.04 * float(entry["spec"]["id"] == "demons")})
        if not pieces:
            continue
        graph = (lambda nodes, links, _group=group: pigment_graph(nodes, links, _group))
        baked = pbr.bake_group(pieces, work, f"gate_{group}", TEX[group],
            METALLIC[group], graph)
        material = cave.final_material(f"Gate_{group.capitalize()}", baked["files"])
        pbr.ship(out_dir, f"gate_{group}", baked, report, METALLIC[group], key=group)
        for entry in made:
            if group not in entry["groups"]:
                continue
            low, high = entry["groups"][group]
            low.data.materials.clear()
            low.data.materials.append(material)
            low.location.x = 0.0
            bpy.data.objects.remove(high, do_unlink=True)


def stage_preview(objects: list):
    scene = bpy.context.scene
    span = 0.0
    for obj in objects:
        obj.location.x = span + obj.dimensions.x * 0.5
        span += obj.dimensions.x + 1.4
    centre = (span - 1.4) * 0.5
    bpy.ops.mesh.primitive_plane_add(size=80.0, location=(centre, 0.0, -0.002))
    ground = bpy.context.active_object
    ground_mat = bpy.data.materials.new("PreviewGround")
    ground_mat.use_nodes = True
    ground_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"] \
        .default_value = (0.040, 0.036, 0.030, 1.0)
    ground.data.materials.append(ground_mat)
    for name, at, energy, colour, size in (
            ("Key", (centre - 3.4, -4.6, 4.2), 900.0, (1.0, 0.82, 0.60), 2.6),
            ("Fill", (centre + 4.2, -3.2, 2.8), 320.0, (0.66, 0.76, 1.0), 3.0),
            ("Rim", (centre + 0.6, 3.6, 3.4), 520.0, (1.0, 0.44, 0.28), 2.4)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.color = colour
        light.size = size
        obj = bpy.data.objects.new(name, light)
        obj.location = at
        direction = Vector((centre, 0.0, 1.3)) - Vector(at)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)
    scene.world.color = (0.070, 0.066, 0.062)
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"
    scene.render.image_settings.color_mode = "RGB"
    return centre, span


def render_preview(objects: list, work: Path) -> None:
    scene = bpy.context.scene
    centre, span = stage_preview(objects)
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 42.0
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    half_angle = math.atan(18.0 / camera_data.lens)
    distance = (span * 0.58) / math.tan(half_angle) * 1.06
    target = Vector((centre, 0.0, 1.80))
    camera.location = (centre, -distance, 1.95)
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 900
    scene.cycles.samples = 128
    scene.render.filepath = str(work / "preview_gates.png")
    bpy.ops.render.render(write_still=True)
    log("preview", scene.render.filepath)
    # A close pass on the wood's own gate, where the coursing is read.
    first = objects[0]
    camera_data.lens = 50.0
    camera.location = (first.location.x - 2.1, -4.1, 1.85)
    target = Vector((first.location.x - 0.55, 0.0, 1.75))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.cycles.samples = 160
    scene.render.filepath = str(work / "preview_gate_close.png")
    bpy.ops.render.render(write_still=True)
    log("preview", scene.render.filepath)


def main() -> None:
    started = time.time()
    out_dir, work = _args()
    work.mkdir(parents=True, exist_ok=True)
    (out_dir / "textures").mkdir(parents=True, exist_ok=True)
    report = {
        "generator": "tools/prepare_gate_assets.py",
        "builder": "python tools/build_gate_assets.py",
        "blender": bpy.app.version_string,
        "seed": SEED,
        "license": "CC BY-NC-SA 4.0 (LICENSE.md section 3); original geometry and bakes",
        "conventions": {
            "axes": "Godot +Y up; the gate faces -Z; stands on its origin",
            "opening": "2.0 m wide, 2.9 m tall: the runtime lays the biome's sheet in it",
            "albedo": "sRGB, pigment only (no baked lighting)",
            "normal": "OpenGL tangent (+Y green up)",
            "orm": "R occlusion, G roughness, B metallic (glTF metallicRoughness)",
        },
        "variants": {},
        "textures": {},
    }
    cave.reset_scene()
    made = build_all()
    bake_all(made, out_dir, work, report)
    objects = []
    for entry in made:
        joined = pbr.join_group([entry["groups"][group][0] for group in entry["spec"]["groups"]],
            entry["spec"]["node"])
        prop.triangulate(joined)
        objects.append(joined)
    for obj, entry in zip(objects, made):
        co = np.empty(len(obj.data.vertices) * 3, np.float32)
        obj.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        godot = np.stack([co[:, 0], co[:, 2], -co[:, 1]], axis=-1)
        report["variants"][entry["spec"]["id"]] = {
            "node": obj.name,
            "triangles": cave.triangles(obj),
            "materials": sorted(slot.name for slot in obj.data.materials),
            "min": [round(float(v), 4) for v in godot.min(axis=0)],
            "max": [round(float(v), 4) for v in godot.max(axis=0)],
        }
    render_preview(objects, work)
    path = out_dir / "ironwood_gates.glb"
    cave.export_glb(path, objects, vertex_colours=False)
    report["file"] = {"name": path.name, "sha256": cave.sha256(path),
        "bytes": path.stat().st_size}
    report["build_seconds"] = round(time.time() - started, 1)
    (out_dir / "ironwood_gates.json").write_text(json.dumps(report, indent=1) + "\n",
        encoding="utf-8")
    log("done", report["build_seconds"], "s")


if __name__ == "__main__":
    main()
