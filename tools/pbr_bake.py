"""The shared PBR bake for authored props.

Every prop pipeline in `tools/` builds the same way: geometry with real bevels
from `prop_primitives`, a dense displaced copy of it, and a Cycles bake of four
passes down onto the low mesh's UV atlas. This module owns the bake, the two
shader wrappers and the map writing, so the chests and the gates cannot drift
apart in how they produce a texture.

The pigment network stays in each asset's own script - a chest's grain and a
gate's chiselling are not the same graph - but it is handed in as a builder:

    def graph(nodes, links):
        ...
        return colour_socket, roughness_socket      # roughness may be None

    pigment = pigment_material("GateStonePigment", graph)   # EMIT, for COLOR
    surface = surface_material("GateStone", graph, metallic)  # Principled

Colour is baked through Emission on purpose: a `DIFFUSE`/`COLOR` pass has no
diffuse lobe to read on a metal and comes back black.
"""

from __future__ import annotations

import time
from pathlib import Path

import bpy
import numpy as np

import prepare_cave_kit as cave


def log(*parts) -> None:
    print("pbr:", *parts, flush=True)


def _new_material(name: str):
    made = bpy.data.materials.new(name)
    made.use_nodes = True
    nodes, links = made.node_tree.nodes, made.node_tree.links
    nodes.clear()
    return made, nodes, links


def remap(nodes, links, value, low: float, high: float):
    """A 0..1 field mapped into a real range: `cave._range` normalises to 0..1
    and is for factors, while a roughness or a tint needs the target numbers."""
    node = nodes.new("ShaderNodeMapRange")
    links.new(value, node.inputs["Value"])
    node.inputs["From Min"].default_value = 0.0
    node.inputs["From Max"].default_value = 1.0
    node.inputs["To Min"].default_value = low
    node.inputs["To Max"].default_value = high
    node.clamp = True
    return node.outputs["Result"]


def pigment_material(name: str, graph):
    """Base colour alone, out of an Emission shader: what the COLOR pass reads."""
    material, nodes, links = _new_material(name)
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    links.new(emit.outputs["Emission"], out.inputs["Surface"])
    colour, _rough = graph(nodes, links)
    links.new(colour, emit.inputs["Color"])
    return material


def surface_material(name: str, graph, metallic: float, emit_colour=None):
    """The Principled body the roughness pass reads, and what the artist sees."""
    material, nodes, links = _new_material(name)
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    colour, rough = graph(nodes, links)
    links.new(colour, bsdf.inputs["Base Color"])
    if rough is not None:
        links.new(rough, bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Roughness"].default_value = 0.30
    bsdf.inputs["Metallic"].default_value = metallic
    if emit_colour is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit_colour, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.4
    return material


def bake_group(pieces: list, work: Path, name: str, size: int, metallic: float,
        graph, emit: bool = False, margin: int = 4) -> dict:
    """High-to-low bake for one material: base colour, tangent normal, roughness
    and occlusion, packed into the glTF ORM the runtime material reads."""
    scene = bpy.context.scene
    kinds = [("color", (0.0, 0.0, 0.0, 1.0), "Linear Rec.709"),
        ("normal", (0.5, 0.5, 1.0, 1.0), "Non-Color"),
        ("rough", (0.6, 0.6, 0.6, 1.0), "Non-Color"),
        ("ao", (1.0, 1.0, 1.0, 1.0), "Non-Color")]
    if emit:
        kinds.append(("emit", (0.0, 0.0, 0.0, 1.0), "Linear Rec.709"))
    targets = {}
    for kind, colour, colorspace in kinds:
        image = bpy.data.images.new(f"{name}_{kind}", size, size, alpha=False,
            float_buffer=True)
        image.colorspace_settings.name = colorspace
        image.generated_color = colour
        targets[kind] = image
    bake_mat = bpy.data.materials.new(f"{name}_Target")
    bake_mat.use_nodes = True
    target_node = bake_mat.node_tree.nodes.new("ShaderNodeTexImage")
    bake_mat.node_tree.nodes.active = target_node
    for piece in pieces:
        mesh = piece["low"].data
        mesh.materials.clear()
        mesh.materials.append(bake_mat)
        mesh.polygons.foreach_set("material_index", np.zeros(len(mesh.polygons), np.int32))
    surface = surface_material(f"{name}_Surface", graph, metallic)
    pigment = pigment_material(f"{name}_Pigment", graph)
    passes = [("color", "EMIT", pigment, set(), 8),
        ("normal", "NORMAL", surface, set(), 16),
        ("rough", "ROUGHNESS", surface, set(), 10),
        ("ao", "AO", surface, set(), 64)]
    if emit:
        passes.append(("emit", "EMIT", surface, set(), 8))
    timing = {}
    for kind, bake_type, high_material, pass_filter, samples in passes:
        started = time.time()
        target_node.image = targets[kind]
        scene.cycles.samples = samples
        for piece in pieces:
            piece["high"].data.materials.clear()
            piece["high"].data.materials.append(high_material)
            cave.select_only([piece["high"], piece["low"]], piece["low"])
            kwargs = dict(type=bake_type, use_selected_to_active=True,
                cage_extrusion=piece["cage"], max_ray_distance=piece["cage"] * 2.4,
                margin=margin, margin_type="EXTEND", use_clear=False,
                target="IMAGE_TEXTURES")
            if pass_filter:
                kwargs["pass_filter"] = pass_filter
            if bake_type == "NORMAL":
                kwargs["normal_space"] = "TANGENT"
            bpy.ops.object.bake(**kwargs)
        timing[kind] = round(time.time() - started, 1)
        log("baked", name, kind, timing[kind], "s")
    colour = cave.image_pixels(targets["color"])[..., :3]
    normal = cave.image_pixels(targets["normal"])[..., :3]
    rough = cave.image_pixels(targets["rough"])[..., 0]
    occlusion = cave.image_pixels(targets["ao"])[..., 0]
    occlusion = np.clip(0.65 * occlusion + 0.35 * cave.blur(occlusion, 1.4), 0.0, 1.0)
    occlusion = 1.0 - (1.0 - occlusion) * 0.88
    orm = np.stack([occlusion, rough, np.full_like(rough, metallic)], axis=-1)
    files = {
        "albedo": work / f"{name}_albedo.png",
        "normal": work / f"{name}_normal.png",
        "orm": work / f"{name}_orm.png",
    }
    cave.write_png(files["albedo"], cave.quantize(cave.to_srgb(np.clip(colour, 0.0, 1.0))))
    cave.write_png(files["normal"], cave.quantize(normal))
    cave.write_png(files["orm"], cave.quantize(orm))
    if emit:
        files["emit"] = work / f"{name}_emit.png"
        glow = cave.image_pixels(targets["emit"])[..., :3]
        cave.write_png(files["emit"], cave.quantize(cave.to_srgb(np.clip(glow, 0.0, 1.0))))
    for image in targets.values():
        bpy.data.images.remove(image)
    return {"files": files, "timing": timing, "size": size}


def join_group(objects: list, name: str):
    cave.select_only(objects, objects[0])
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    return joined


def ship(out_dir: Path, name: str, baked: dict, report: dict, metallic: float,
        key: str | None = None) -> None:
    """Copy a bake's maps into the asset's `textures/` and record their digests.
    `name` is the map prefix; `key` is the manifest row, when they differ."""
    (out_dir / "textures").mkdir(parents=True, exist_ok=True)
    entry = {"size": baked["size"], "metallic": metallic,
        "bake_seconds": baked["timing"], "files": {}}
    for kind, path in baked["files"].items():
        target = out_dir / "textures" / path.name
        target.write_bytes(path.read_bytes())
        entry["files"][kind] = {"file": f"textures/{path.name}",
            "sha256": cave.sha256(target)}
    report["textures"][key or name] = entry
