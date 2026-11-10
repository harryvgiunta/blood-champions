class_name RogueliteGateVisual
extends Node3D
## A gate out of a cleared level: an authored doorway with the biome's sheet
## standing in its opening.
##
## `assets/props/gates/ironwood_gates.glb` carries all three doors - the wood's
## coursed granite, the devils' basalt hung with bone, the clones' turned-out
## body - each a single mesh with its own Cycles-baked surfaces. This node keeps
## the one the biome asked for, lays the promise's sheet in the opening and sets
## the lamp that spills out of it.
##
## The sheet is presentation, not geometry: its colour is the biome's promise, so
## it is a quad the director's payload colours rather than something baked into
## an atlas. Nothing here decides where a gate leads.

const SCENE := preload("res://assets/props/gates/ironwood_gates.glb")
const VARIANTS := {
	"wilderness": "Gate_Watchers", "caves": "Gate_Demons", "arena": "Gate_Clones",
}
## The opening the sheet fills, in metres, and where the lamp sits in front of it.
const OPENING := Vector2(2.0, 2.9)
const CENTRE := Vector3(0.0, 1.60, 0.02)
const LAMP := Vector3(0.0, 1.70, 0.62)
const PULSE_HZ := 0.35

var biome := "wilderness"
var glow := Color(0.48, 0.78, 0.52)
var _sheet: StandardMaterial3D
var _ember: StandardMaterial3D
var _light: OmniLight3D
var _clock := 0.0


func setup(biome_id: String, colour: Color) -> void:
	biome = biome_id
	glow = colour
	var instance: Node = SCENE.instantiate()
	var wanted := str(VARIANTS.get(biome, VARIANTS["wilderness"]))
	var chosen: Node3D = null
	for child in instance.get_children():
		if str(child.name) == wanted:
			chosen = child
	for child in instance.get_children():
		if child != chosen:
			instance.remove_child(child)
			child.free()
	if chosen == null:
		if instance.get_child_count() == 0:
			instance.free()
			return
		chosen = instance.get_child(0) as Node3D
	instance.remove_child(chosen)
	instance.free()
	# The GLB lays its three variants out along +x so the bake sheet can render
	# them side by side. The one kept stands on the prop's own origin, so the
	# sheet and the lamp below sit in its opening.
	chosen.position = Vector3.ZERO
	add_child(chosen)
	# A portal is a lit surface, not a light source: pigment well under the glow,
	# so the sheet reads as the promise's colour instead of clipping to white.
	_sheet = _glow_material(0.42)
	_sheet.albedo_color = glow.darkened(0.62)
	var quad := QuadMesh.new()
	quad.size = OPENING
	var mouth := MeshInstance3D.new()
	mouth.name = "Sheet"
	mouth.mesh = quad
	mouth.material_override = _sheet
	mouth.position = CENTRE
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mouth)
	if biome == "caves":
		# The devils' door is a mouth in the rock, not a sheet of light: one
		# ember line down its middle is the far side of the fire.
		_ember = _glow_material(0.85)
		var ember := QuadMesh.new()
		ember.size = Vector2(0.16, 2.7)
		var vein := MeshInstance3D.new()
		vein.name = "Ember"
		vein.mesh = ember
		vein.material_override = _ember
		vein.position = CENTRE + Vector3(0.0, 0.0, 0.03)
		vein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(vein)
	_light = OmniLight3D.new()
	_light.name = "GateGlow"
	_light.light_color = glow
	_light.light_energy = 5.0
	_light.omni_range = 12.0
	_light.position = LAMP
	add_child(_light)


## The promise's light. A flat fill of the tier's colour reads as a painted
## billboard; a hot centre falling away to the jambs reads as a doorway, so the
## sheet carries a vignette and its pigment stays dark under the glow.
func _glow_material(energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var veil := _vignette()
	material.albedo_color = glow
	material.albedo_texture = veil
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.emission_enabled = true
	material.emission = glow
	material.emission_texture = veil
	material.emission_energy_multiplier = energy
	return material


## A soft core: bright at the middle of the opening, dimming into the jambs and
## the lintel. Generated once, and cached for every gate after the first.
static var _veil_cache: ImageTexture


func _vignette() -> ImageTexture:
	if _veil_cache != null:
		return _veil_cache
	var edge := 72
	var image := Image.create(edge, edge, false, Image.FORMAT_RGBA8)
	for y in edge:
		for x in edge:
			var u := (float(x) + 0.5) / float(edge) - 0.5
			var v := (float(y) + 0.5) / float(edge) - 0.5
			# Gentle on purpose: the sheet has to fill the opening, so the jambs
			# stay at two thirds and only the very edge falls away. A stronger
			# falloff leaves a glowing blob floating in the doorway.
			var radius := sqrt(u * u * 0.85 + v * v * 0.45) * 1.5
			var core := clampf(1.0 - radius * radius * 0.42, 0.0, 1.0)
			var column := lerpf(0.72, 1.0, clampf(1.0 - absf(u) * 1.7, 0.0, 1.0))
			var value := clampf(core * column, 0.0, 1.0)
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	_veil_cache = ImageTexture.create_from_image(image)
	return _veil_cache


func _process(delta: float) -> void:
	if _light == null:
		return
	_clock = fmod(_clock + delta * TAU * PULSE_HZ, TAU)
	var breathe := 0.5 + 0.5 * sin(_clock)
	_light.light_energy = 4.6 + 1.1 * breathe
	_sheet.emission_energy_multiplier = 0.40 + 0.12 * breathe
	if _ember != null:
		_ember.emission_energy_multiplier = 0.85 + 0.20 * breathe
