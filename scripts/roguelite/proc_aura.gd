extends Node3D
## A standing field on the floor: the ground a proc owns for a few seconds - a
## ward, a pool, a patch of something eating through the boards. It is drawn by
## `proc_fx.zone_field` and it is presentation only: no collision, no shape, no
## gameplay state and nothing to damage, so host and guest can both own one and
## still agree on what the fight did.
##
## The pulse is `_process`, not a tween chain, on purpose: a field lasts however
## long its proc says, and a chain would have to be rebuilt for every duration
## while an oscillator breathes at the same rate for all of them. The same
## `_process` owns the fade and the free, so a field cannot outlive its timer.

const AbilityFx = preload("res://scripts/ability_fx.gd")

## Seconds of tail in which the field fades out before it frees itself.
const FADE := 0.45
## How fast the inner rune ring turns against the outer ring, radians/second.
const RUNE_SPIN := -0.32

var _colour := Color(0.62, 0.89, 0.72)
var _radius := 3.0
var _seconds := 3.0
var _elapsed := 0.0
var _built := false
var _disc: MeshInstance3D
var _ring: MeshInstance3D
var _runes: MeshInstance3D
var _light: OmniLight3D
var _disc_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _rune_material: StandardMaterial3D


## Sizes and tints the field and builds its three meshes. Safe to call before
## the node is in the tree - every child is a plain mesh, and nothing here reads
## the world - which is what lets the static helper spawn it in one line.
func configure(colour: Color, radius: float, seconds: float) -> void:
	_colour = colour
	_radius = maxf(radius, 0.4)
	_seconds = maxf(seconds, 0.2)
	_build()


func _ready() -> void:
	if not _built:
		_build()


func _process(delta: float) -> void:
	if not _built:
		return
	_elapsed += delta
	var remaining := clampf((_seconds - _elapsed) / FADE, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_elapsed * 4.2)
	_disc_material.albedo_color = Color(_colour.r, _colour.g, _colour.b,
		(0.09 + 0.06 * pulse) * remaining)
	_ring_material.albedo_color = Color(_colour.r, _colour.g, _colour.b,
		(0.34 + 0.28 * pulse) * remaining)
	_rune_material.albedo_color = Color(_colour.r, _colour.g, _colour.b,
		(0.55 + 0.4 * pulse) * remaining)
	_ring.scale = Vector3(1.0 + 0.02 * pulse, 1.0, 1.0 + 0.02 * pulse)
	_runes.rotate_y(RUNE_SPIN * delta)
	_light.light_energy = (0.7 + 1.1 * pulse) * remaining
	if _elapsed >= _seconds:
		queue_free()


func _build() -> void:
	if _built:
		return
	_disc_material = AbilityFx.glow_material(_colour, 1.1, 0.12)
	var disc_mesh := CylinderMesh.new()
	disc_mesh.bottom_radius = _radius
	disc_mesh.top_radius = _radius
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 28
	_disc = MeshInstance3D.new()
	_disc.mesh = disc_mesh
	_disc.material_override = _disc_material
	_disc.position = Vector3.UP * 0.03
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	_ring_material = AbilityFx.glow_material(_colour, 2.4, 0.5)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = _radius * 0.94
	ring_mesh.outer_radius = _radius
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.material_override = _ring_material
	_ring.position = Vector3.UP * 0.06
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	# The notches are one baked mesh rather than twelve nodes: a ring of runes
	# is a texture, not a rig, and twelve meshes would spend the whole node
	# budget of a standing effect on decoration.
	_rune_material = AbilityFx.ribbon_material(_colour)
	_runes = MeshInstance3D.new()
	_runes.mesh = _notch_mesh(_radius * 0.78, 12)
	_runes.material_override = _rune_material
	_runes.position = Vector3.UP * 0.05
	_runes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_runes)
	_light = AbilityFx.flash_light(_colour, 1.0, _radius * 1.6)
	_light.position = Vector3.UP * 0.6
	add_child(_light)
	# Only now is the field complete: `_process` reads every one of the members
	# above, so it may not start before the last of them exists.
	_built = true


## Twelve flat trapezoid notches on one surface, in the XZ plane, so the whole
## rune ring is a single draw call that can be spun.
static func _notch_mesh(radius: float, count: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for index in count:
		var angle := TAU * float(index) / float(count)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var inner := direction * (radius * 0.86)
		var outer := direction * (radius * 1.0)
		var half := side * (radius * 0.055)
		var base := vertices.size()
		vertices.append(inner - half)
		vertices.append(inner + half)
		vertices.append(outer + half)
		vertices.append(outer - half)
		for _corner in 4:
			normals.append(Vector3.UP)
			colors.append(Color(1.0, 1.0, 1.0, 1.0))
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
