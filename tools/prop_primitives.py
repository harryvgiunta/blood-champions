"""bmesh primitives shared by the authored props.

Every prop in `tools/` that is built from boxes, cylinders, spheres and swept
skins grows them the same way: one bmesh per material, closed primitives with
bevelled edges, and consistent outward normals before the object leaves this
module. The helpers are deliberately small - a prop is a stack of these, not a
new modelling language - and they operate in metres on Blender's Z-up frame.

Shading: `finish()` flat-shades by default, because a bevelled box reads through
its edge highlights rather than through interpolated normals. The dense copy
that a normal bake needs passes `smooth=True` and is displaced afterwards.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_cave_kit as cave  # noqa: E402


def log(*parts) -> None:
    print("props:", *parts, flush=True)


def finish(name: str, bm, smooth: bool = False):
    """Consistent outward normals, then a scene object. Nothing leaves a build
    function without this: a wrongly wound face bakes a black patch."""
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return cave.bm_object(name, bm, smooth=smooth)


def triangulate(obj) -> None:
    """An n-gon cannot carry tangents, and the glTF exporter drops the tangent
    map for a mesh it cannot triangulate - which silently kills the normal map."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def add_cube(bm, center, size, bevel: float = 0.006, segments: int = 2):
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    bevel_verts(bm, verts, bevel, segments)
    return verts


def bevel_verts(bm, verts, offset: float, segments: int) -> list:
    if offset <= 0.0:
        return []
    edges = set()
    for vert in verts:
        for edge in vert.link_edges:
            edges.add(edge)
    result = bmesh.ops.bevel(bm, geom=list(edges), offset=offset, segments=segments,
        affect="EDGES", profile=0.5, clamp_overlap=True)
    return result["verts"]


def add_cylinder(bm, center, radius: float, depth: float, segments: int = 24,
        axis: str = "Z", bevel: float = 0.004, taper: float = 1.0):
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
        radius1=radius, radius2=radius * taper, depth=depth)
    verts = res["verts"]
    if axis == "X":
        bmesh.ops.rotate(bm, cent=(0, 0, 0),
            matrix=Matrix.Rotation(math.radians(90.0), 4, "Y"), verts=verts)
    elif axis == "Y":
        bmesh.ops.rotate(bm, cent=(0, 0, 0),
            matrix=Matrix.Rotation(math.radians(90.0), 4, "X"), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    bevel_verts(bm, verts, bevel, 2)
    return verts


def add_sphere(bm, center, radius: float, u: int = 16, v: int = 10, scale=(1, 1, 1)):
    res = bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=radius)
    verts = res["verts"]
    bmesh.ops.scale(bm, vec=Vector(scale), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    return verts


def add_torus(bm, center, major: float, minor: float, axis: str = "Z",
        major_seg: int = 32, minor_seg: int = 8):
    """A swept tube round a circle: a ring handle, a lock's eye, a bezel."""
    ring = []
    for i in range(major_seg):
        a = math.tau * i / major_seg
        c = Vector((math.cos(a) * major, math.sin(a) * major, 0.0))
        section = []
        for j in range(minor_seg):
            b = math.tau * j / minor_seg
            n = Vector((math.cos(a) * math.cos(b), math.sin(a) * math.cos(b), math.sin(b)))
            section.append(bm.verts.new(c + n * minor))
        ring.append(section)
    for i in range(major_seg):
        nxt = ring[(i + 1) % major_seg]
        for j in range(minor_seg):
            k = (j + 1) % minor_seg
            bm.faces.new((ring[i][j], ring[i][k], nxt[k], nxt[j]))
    verts = [v for section in ring for v in section]
    if axis == "X":
        bmesh.ops.rotate(bm, cent=(0, 0, 0),
            matrix=Matrix.Rotation(math.radians(90.0), 4, "Y"), verts=verts)
    elif axis == "Y":
        bmesh.ops.rotate(bm, cent=(0, 0, 0),
            matrix=Matrix.Rotation(math.radians(90.0), 4, "X"), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    return verts


def add_shell(bm, grid):
    """A one-sided quad surface from a (rows, cols, 3) array of points. The
    caller closes it: a shell on its own is a sheet, not a solid."""
    rows, cols = grid.shape[0], grid.shape[1]
    verts = [[bm.verts.new(tuple(grid[i, j])) for j in range(cols)] for i in range(rows)]
    for i in range(rows - 1):
        for j in range(cols - 1):
            bm.faces.new((verts[i][j], verts[i][j + 1], verts[i + 1][j + 1], verts[i + 1][j]))
    return verts
