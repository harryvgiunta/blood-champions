"""Render the reward card's art: rarity frames, family sigils and prop plaques.

The draft and the shop used to be rows of `Button.text`, which is a dictionary
with a border. These are the surfaces that replace it, each rendered in Cycles
from real geometry, so a frame is a beveled metal ring with a cut stone in each
corner and a sigil is a solid emblem that catches the key light - not a flat
glyph on a coloured rectangle.

Three families of output, all deterministic (fixed seed, fixed camera):

    frame_<rarity>.png        512        the card's 9-slice plate
    frame_<rarity>_lit.png    512        the same plate under the hover light
    sigil_<family>.png        256        a family emblem on transparency
    plaque_<rarity>.png      1024x256    the plate a world prop hangs its name on

A frame is 9-sliced, so its border must survive being stretched along an edge:
the strips are averaged down their length while the four corner squares and the
centre keep their detail. That is the same treatment
`tools/render_ui_theme.py` gives the ledger's plates.

    python tools/build_reward_cards.py

runs Blender on this file in background mode.
"""

from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_cave_kit as cave  # noqa: E402
import prop_primitives as prop  # noqa: E402
from prop_primitives import add_cube, add_cylinder, add_sphere, add_torus  # noqa: E402

SEED = 7301
FRAME_SIZE = 512
# The 9-slice border in texture pixels, which is also the border drawn on
# screen: NinePatchRect does not scale its margins. Everything that is ornament
# must therefore live inside this many pixels of the plate's edge - the ring, its
# moulding and the corner bosses - and the stretchable middle must hold nothing
# but the field. A margin smaller than the art's ring stretches a slice of that
# ring into the card's centre, which reads as a frame drawn twice.
FRAME_MARGIN = 34
SIGIL_SIZE = 256
PLAQUE = (1024, 256)

# One row per rarity. `metal` is the frame's pigment, `gem` the corner stone's
# own colour, `energy` how hard the stone burns when the card is under the
# pointer. The card's field is dark in every rarity: the metal carries the tier.
RARITIES = {
    "common": {"metal": (0.048, 0.052, 0.058), "rough": 0.54,
        "gem": (0.72, 0.86, 0.92), "energy": 0.55},
    "epic": {"metal": (0.018, 0.046, 0.130), "rough": 0.46,
        "gem": (0.45, 0.72, 1.00), "energy": 0.85},
    "legendary": {"metal": (0.235, 0.140, 0.030), "rough": 0.36,
        "gem": (1.00, 0.78, 0.32), "energy": 1.15},
    "greed": {"metal": (0.170, 0.026, 0.019), "rough": 0.42,
        "gem": (1.00, 0.34, 0.22), "energy": 1.05},
    "neutral": {"metal": (0.040, 0.039, 0.037), "rough": 0.58,
        "gem": (0.86, 0.80, 0.66), "energy": 0.35},
}

# The five upgrade families, in the plate's order.
FAMILIES = ["shot", "hand", "ability", "perk", "relic"]


def log(*parts) -> None:
    print("cards:", *parts, flush=True)


def _args() -> tuple[Path, Path]:
    argv = sys.argv
    if "--" not in argv or len(argv) - argv.index("--") < 2:
        raise SystemExit("usage: blender -b --python tools/prepare_reward_cards.py"
            " -- <out_dir> [<work_dir>]")
    rest = argv[argv.index("--") + 1:]
    root = Path(__file__).resolve().parent.parent
    work = Path(rest[1]) if len(rest) > 1 else root / ".runtime" / "card-build"
    return Path(rest[0]).resolve(), work.resolve()


# --- materials --------------------------------------------------------------


def _material(name: str):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    return material, material.node_tree.nodes, material.node_tree.links


def _pitting(nodes, links, bsdf, scale: float, strength: float, distance: float) -> None:
    coord = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 3.0
    links.new(coord.outputs["Object"], noise.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    bump.inputs["Distance"].default_value = distance
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def metal_material(name: str, pigment, roughness: float, energy: float = 0.0,
        glow=(1.0, 1.0, 1.0)):
    """The frame's metal, the stone's own emission, the leather the plate is
    faced with. Rendered directly: a card's texture *is* the render, so these
    graphs are the finished look and there is no bake step."""
    material, nodes, links = _material(name)
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*pigment, 1.0)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = roughness
    if energy > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*glow, 1.0)
        bsdf.inputs["Emission Strength"].default_value = energy
    _pitting(nodes, links, bsdf, 260.0, 0.10, 0.0008)
    return material


def stone_material(name: str, colour, energy: float):
    """A cut stone: its own colour, faceted by the geometry, lit from inside."""
    material, nodes, links = _material(name)
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (
        colour[0] * 0.22, colour[1] * 0.22, colour[2] * 0.22, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.08
    bsdf.inputs["Emission Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Emission Strength"].default_value = energy * 0.22
    return material


def leather_material():
    material, nodes, links = _material("Card_Field")
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.013, 0.010, 0.008, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.86
    # No specular: the plate's field is where the card's copy is read, and a
    # glossy one lifts to mid grey under the ring's own bounce.
    for key in ("Specular IOR Level", "Specular"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = 0.0
    _pitting(nodes, links, bsdf, 150.0, 0.32, 0.0018)
    return material


def add_spike(bm, center, radius: float, depth: float, up: bool, segments: int = 4,
        bevel: float = 0.004):
    """A four-sided pyramid whose tip looks along +Y (`up`) or -Y, built face by
    face in the camera's own plane. `create_cone` with a zero radius leaves a
    degenerate apex ring that the mesh cleanup throws away, so the point is
    written here instead."""
    cx, cy, cz = center
    half = radius
    tip_y = cy + depth * 0.5 if up else cy - depth * 0.5
    base_y = cy - depth * 0.5 if up else cy + depth * 0.5
    ring = []
    for index in range(segments):
        angle = math.tau * (index + 0.5) / segments
        ring.append(bm.verts.new(
            (cx + math.cos(angle) * half, base_y, cz + math.sin(angle) * half)))
    tip = bm.verts.new((cx, tip_y, cz))
    bm.faces.new(ring)
    for index in range(segments):
        bm.faces.new((ring[index], ring[(index + 1) % segments], tip))
    prop.bevel_verts(bm, ring + [tip], bevel, 2)
    return ring + [tip]


def stones(bm, at: list, radius: float, depth_scale: float = 0.75):
    """Cut stones in their bezels: an icosahedron catches one light at a time,
    which is what reads as a jewel at 40 px."""
    for center in at:
        res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
        bmesh.ops.scale(bm, vec=Vector((1.0, 1.0, depth_scale)), verts=res["verts"])
        bmesh.ops.translate(bm, vec=Vector(center), verts=res["verts"])


# --- the frame plate --------------------------------------------------------


def frame_objects(rarity: str) -> list:
    """A plate faced in leather and bound in a beveled metal ring, with a cut
    stone at each corner. The ring is the 9-slice border and the stones live
    inside the corner squares, so the strips can stretch between them."""
    spec = RARITIES[rarity]
    metal = metal_material(f"Card_Metal_{rarity}", spec["metal"], spec["rough"])
    field = leather_material()
    gem = stone_material(f"Card_Gem_{rarity}", spec["gem"], spec["energy"])
    # Every dimension below is a pixel of the 512 plate divided by 512, so the
    # geometry and `FRAME_MARGIN` are the same numbers: ring 0..30, moulding
    # 27..33, field from 36.
    tile = 512.0
    bar = 30.0 / tile
    bm = bmesh.new()
    add_cube(bm, (0.0, 0.0, 0.010), (1.0 - 2 * 36.0 / tile,) * 2 + (0.020,), 0.006, 2)
    face = prop.finish(f"Card_Field_{rarity}", bm)
    face.data.materials.append(field)
    bm = bmesh.new()
    half = 0.5 - bar * 0.5
    for axis, sign in (("x", -1), ("x", 1), ("y", -1), ("y", 1)):
        size = (bar, 1.0, 0.040) if axis == "x" else (1.0, bar, 0.040)
        at = (sign * half, 0.0, 0.020) if axis == "x" else (0.0, sign * half, 0.020)
        add_cube(bm, at, size, 0.008, 2)
    # The lip of the case: a thin moulding just inside the ring, still inside
    # the corner square so the strips can carry it.
    inner = 0.5 - 30.0 / tile
    lip = 6.0 / tile
    for axis, sign in (("x", -1), ("x", 1), ("y", -1), ("y", 1)):
        size = (lip, inner * 2.0, 0.026) if axis == "x" else (inner * 2.0, lip, 0.026)
        at = (sign * inner, 0.0, 0.014) if axis == "x" else (0.0, sign * inner, 0.014)
        add_cube(bm, at, size, 0.003, 2)
    # The corner bosses: a 34 px square each, so the whole ornament sits inside
    # the 9-slice corner.
    boss = 0.5 - 17.0 / tile
    boss_size = 34.0 / tile
    for sx in (-1, 1):
        for sy in (-1, 1):
            add_cube(bm, (sx * boss, sy * boss, 0.022), (boss_size, boss_size, 0.044), 0.010, 3)
            add_torus(bm, (sx * boss, sy * boss, 0.046), 0.030, 0.008, "Z", 24, 8)
    ring = prop.finish(f"Card_Frame_{rarity}", bm)
    ring.data.materials.append(metal)
    bm = bmesh.new()
    stones(bm, [(sx * boss, sy * boss, 0.054) for sx in (-1, 1) for sy in (-1, 1)], 0.021)
    jewel = prop.finish(f"Card_Stones_{rarity}", bm, smooth=True)
    jewel.data.materials.append(gem)
    return [face, ring, jewel]


# --- the family sigils ------------------------------------------------------


def sigil_objects(family: str) -> list:
    """One emblem per family. Each is a solid with a bevel so the light reads
    its form, built in the camera's own plane; the silhouette is the whole read
    at 64 px, so every shape is one bold idea."""
    body = metal_material(f"Sigil_{family}", (0.430, 0.408, 0.340), 0.26)
    gold = metal_material(f"Sigil_{family}_gilt", (0.620, 0.440, 0.140), 0.20)
    gem = stone_material(f"Sigil_{family}_gem", (0.95, 0.70, 0.34), 0.85)
    bm = bmesh.new()
    if family == "shot":
        # An arrow climbing: shaft, a four-sided head, two swept fletches.
        add_cylinder(bm, (0.0, -0.06, 0.020), 0.030, 0.54, 12, "Y", 0.003)
        add_spike(bm, (0.0, 0.36, 0.020), 0.105, 0.30, True)
        for sign in (-1, 1):
            fletch = add_cube(bm, (sign * 0.085, -0.26, 0.020), (0.15, 0.18, 0.020),
                0.0, 2)
            for vert in fletch:
                vert.co.x += sign * 0.05 * (vert.co.y + 0.35)
            prop.bevel_verts(bm, fletch, 0.006, 2)
    elif family == "hand":
        # A sword held point down: blade, cross-guard, grip, pommel.
        add_cube(bm, (0.0, 0.00, 0.020), (0.112, 0.42, 0.030), 0.012, 3)
        add_spike(bm, (0.0, -0.30, 0.020), 0.079, 0.18, False)
        add_cube(bm, (0.0, 0.235, 0.022), (0.280, 0.050, 0.034), 0.012, 3)
        add_cylinder(bm, (0.0, 0.315, 0.020), 0.038, 0.14, 12, "Y", 0.005)
        add_sphere(bm, (0.0, 0.420, 0.020), 0.058, 12, 8)
    elif family == "ability":
        # A flame: three tongues climbing out of a bowl, each a round finger so
        # the silhouette is a flame and not a lump.
        add_spike(bm, (0.0, 0.02, 0.020), 0.150, 0.62, True, 9, 0.006)
        add_spike(bm, (-0.115, -0.06, 0.020), 0.115, 0.44, True, 9, 0.005)
        add_spike(bm, (0.115, -0.06, 0.020), 0.108, 0.40, True, 9, 0.005)
        add_cylinder(bm, (0.0, -0.30, 0.020), 0.175, 0.070, 22, "Z", 0.008, 0.82)
    elif family == "perk":
        # A ward: the heraldic shield, a disc with its point down, bound in a
        # ring and carrying its stone.
        add_cylinder(bm, (0.0, 0.10, 0.024), 0.205, 0.046, 28, "Y", 0.010, 0.96)
        add_spike(bm, (0.0, -0.09, 0.024), 0.196, 0.30, False, 14, 0.008)
        add_torus(bm, (0.0, 0.10, 0.030), 0.222, 0.026, "Y", 34, 9)
        add_sphere(bm, (0.0, 0.10, 0.048), 0.086, 16, 10, (1.0, 1.0, 0.68))
    else:
        # A relic: a pendant on its chain.
        add_torus(bm, (0.0, 0.10, 0.020), 0.230, 0.021, "Y", 34, 8)
        for step in range(6):
            t = math.pi * (0.22 + 0.11 * step)
            add_sphere(bm, (math.cos(t) * 0.230, 0.10 + math.sin(t) * 0.230, 0.020),
                0.028, 10, 6)
        add_sphere(bm, (0.0, -0.20, 0.020), 0.118, 16, 12, (1.0, 1.0, 0.72))
        add_cylinder(bm, (0.0, -0.30, 0.020), 0.072, 0.05, 16, "Y", 0.006, 0.7)
    made = prop.finish(f"Sigil_{family}_body", bm, smooth=family in ("ability", "perk", "relic"))
    made.data.materials.append(gold if family in ("perk", "relic") else body)
    if family == "relic":
        detail = bmesh.new()
        stones(detail, [(0.0, -0.24, 0.10)], 0.055, 0.8)
        jewel = prop.finish("Sigil_relic_stone", detail, smooth=True)
        jewel.data.materials.append(gem)
        return [made, jewel]
    if family == "perk":
        detail = bmesh.new()
        stones(detail, [(0.0, 0.0, 0.068)], 0.072, 0.7)
        jewel = prop.finish("Sigil_perk_stone", detail, smooth=True)
        jewel.data.materials.append(gem)
        return [made, jewel]
    return [made]


# --- the prop plaque --------------------------------------------------------


def plaque_objects(rarity: str) -> list:
    """The plate a world prop hangs its promise on: a wide bar of the tier's
    metal with a moulded rim and a stone at each end. Drawn as a billboard, so
    it is one shallow slab with its ornament, not a solid bar."""
    spec = RARITIES[rarity]
    metal = metal_material(f"Plaque_Metal_{rarity}", spec["metal"], spec["rough"])
    field = leather_material()
    gem = stone_material(f"Plaque_Gem_{rarity}", spec["gem"], spec["energy"])
    bm = bmesh.new()
    add_cube(bm, (0.0, 0.0, 0.010), (4.00, 0.94, 0.020), 0.014, 2)
    face = prop.finish(f"Plaque_Field_{rarity}", bm)
    face.data.materials.append(field)
    bm = bmesh.new()
    for sy in (-1, 1):
        add_cube(bm, (0.0, sy * 0.452, 0.026), (4.0, 0.10, 0.048), 0.012, 3)
    for sx in (-1, 1):
        add_cube(bm, (sx * 1.940, 0.0, 0.026), (0.12, 1.0, 0.048), 0.012, 3)
        # A tapered end fin: the bar reads as a smith's plate, not a box.
        add_cylinder(bm, (sx * 2.02, 0.0, 0.024), 0.30, 0.11, 4, "X", 0.010, 0.34)
    ring = prop.finish(f"Plaque_Frame_{rarity}", bm)
    ring.data.materials.append(metal)
    bm = bmesh.new()
    stones(bm, [(sx * 1.70, 0.0, 0.040) for sx in (-1, 1)], 0.105)
    jewel = prop.finish(f"Plaque_Gems_{rarity}", bm, smooth=True)
    jewel.data.materials.append(gem)
    return [face, ring, jewel]


# --- render -----------------------------------------------------------------


def stage(width: float, transparent: bool, strength: float) -> None:
    cave.reset_scene()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.seed = SEED
    scene.cycles.use_animated_seed = False
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    scene.render.resolution_percentage = 100
    # A rendered plate is a pigment reference for the whole UI: Standard keeps
    # the tier metals the colour the rest of the interface names them.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("CardWorld")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (0.016, 0.015, 0.014, 1.0)
    background.inputs["Strength"].default_value = strength
    camera_data = bpy.data.cameras.new("CardCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = width
    camera = bpy.data.objects.new("CardCamera", camera_data)
    camera.location = (0.0, 0.0, 4.0)
    scene.collection.objects.link(camera)
    scene.camera = camera


def lights(span: float, strength: float, rim=(1.0, 1.0, 1.0), rim_energy: float = 0.0) -> None:
    """A card is lit like a jewel case: a warm key from the upper left, a cool
    fill from the right, and - when the card is under the pointer - a rim of the
    rarity's own colour standing behind the ring."""
    scene = bpy.context.scene
    for name, at, energy, colour, size in (
            ("Key", (-span * 0.50, span * 0.55, span * 0.95),
                22.0 * strength * span * span, (1.0, 0.88, 0.70), span * 0.20),
            ("Fill", (span * 0.70, -span * 0.30, span * 0.75),
                8.0 * strength * span * span, (0.62, 0.74, 1.0), span * 0.28),
            ("Rim", (0.0, 0.0, -span * 0.30), 14.0 * rim_energy * span * span,
                rim, span * 0.55)):
        if energy <= 0.0:
            continue
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.color = colour
        light.size = size
        obj = bpy.data.objects.new(name, light)
        obj.location = at
        direction = Vector((0.0, 0.0, 0.02)) - Vector(at)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)


def shoot(path: Path, size, samples: int = 96) -> None:
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.cycles.samples = samples
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    log("render", path.name)


def average_strips(path: Path, margin: int) -> None:
    """A stretched 9-slice must not smear: the edge strips lose their variation
    along the axis they are stretched on, while the corner squares and the
    centre keep theirs."""
    pixels = cave.read_image(path, 4)
    height, width = pixels.shape[:2]
    rows = slice(margin, height - margin)
    pixels[rows, :margin] = pixels[rows, :margin].mean(axis=0, keepdims=True)
    pixels[rows, width - margin:] = pixels[rows, width - margin:].mean(axis=0, keepdims=True)
    cols = slice(margin, width - margin)
    pixels[:margin, cols] = pixels[:margin, cols].mean(axis=1, keepdims=True)
    pixels[height - margin:, cols] = pixels[height - margin:, cols].mean(axis=1, keepdims=True)
    cave.write_png(path, cave.quantize(pixels))


# --- main -------------------------------------------------------------------


def build_frames(out_dir: Path, report: dict) -> None:
    for rarity, spec in RARITIES.items():
        for lit in (False, True):
            name = f"frame_{rarity}" + ("_lit" if lit else "")
            stage(1.0, False, 0.55 if lit else 0.20)
            for obj in frame_objects(rarity):
                if obj.name not in bpy.context.scene.collection.objects:
                    bpy.context.scene.collection.objects.link(obj)
            lights(1.0, 1.0 if not lit else 2.2, tuple(spec["gem"]),
                0.5 if lit else 0.0)
            path = out_dir / f"{name}.png"
            shoot(path, (FRAME_SIZE, FRAME_SIZE), 160 if lit else 128)
            average_strips(path, FRAME_MARGIN)
            report["frames"].setdefault(rarity, {})["lit" if lit else "idle"] = {
                "file": path.name, "sha256": cave.sha256(path),
            }
        log("frame", rarity)


def build_sigils(out_dir: Path, report: dict) -> None:
    for family in FAMILIES:
        stage(1.0, True, 0.65)
        for obj in sigil_objects(family):
            if obj.name not in bpy.context.scene.collection.objects:
                bpy.context.scene.collection.objects.link(obj)
        lights(1.0, 1.35, (0.92, 0.86, 0.72), 0.55)
        path = out_dir / f"sigil_{family}.png"
        shoot(path, (SIGIL_SIZE, SIGIL_SIZE), 144)
        report["sigils"][family] = {"file": path.name, "sha256": cave.sha256(path)}
        log("sigil", family)


def build_plaques(out_dir: Path, report: dict) -> None:
    for rarity, spec in RARITIES.items():
        stage(4.36, True, 0.30)
        for obj in plaque_objects(rarity):
            if obj.name not in bpy.context.scene.collection.objects:
                bpy.context.scene.collection.objects.link(obj)
        lights(4.36, 1.1, tuple(spec["gem"]), 0.7)
        path = out_dir / f"plaque_{rarity}.png"
        shoot(path, PLAQUE, 144)
        report["plaques"][rarity] = {"file": path.name, "sha256": cave.sha256(path)}
        log("plaque", rarity)


def main() -> None:
    started = time.time()
    out_dir, work = _args()
    out_dir.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    report = {
        "generator": "tools/prepare_reward_cards.py",
        "builder": "python tools/build_reward_cards.py",
        "blender": bpy.app.version_string,
        "seed": SEED,
        "license": "CC BY-NC-SA 4.0 (LICENSE.md section 3); original renders",
        "conventions": {
            "frames": "9-slice; patch margin %d px, edge strips averaged for stretching"
                % FRAME_MARGIN,
            "sigils": "RGBA on transparency, drawn on the card's field",
            "plaques": "RGBA on transparency, drawn as a world billboard",
        },
        "frame_margin": FRAME_MARGIN,
        "rarities": sorted(RARITIES),
        "families": FAMILIES,
        "frames": {},
        "sigils": {},
        "plaques": {},
    }
    build_frames(out_dir, report)
    build_sigils(out_dir, report)
    build_plaques(out_dir, report)
    report["build_seconds"] = round(time.time() - started, 1)
    (out_dir / "cards.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    log("done", report["build_seconds"], "s")


if __name__ == "__main__":
    main()
