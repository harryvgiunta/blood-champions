class_name RogueliteChestVisual
extends Node3D
## The reward chest as it is actually seen: one authored, textured prop instead
## of a stack of flat-shaded boxes.
##
## `assets/props/chests/reward_chests.glb` carries all three variants - the
## island's own chest, a mini cache and the boss's hoard - each a single mesh
## with four Cycles-baked surfaces (wood, iron, gilt, gem). This node keeps one
## of them, tints the gem and its lamp to the promise's tier colour, and breathes
## the light so a chest reads as live furniture from across the island.
##
## Presentation only: no collision, no interaction, no reward. The director owns
## all of that; this file owns what the player looks at.

const SCENE := preload("res://assets/props/chests/reward_chests.glb")
const VARIANTS := {
	"chest": "Chest_Island", "mini": "Chest_Cache", "elite": "Chest_Hoard",
}
## Where each variant's lid ends, in metres: the plaque above a chest hangs here.
const TOPS := {"chest": 0.91, "mini": 0.55, "elite": 1.14}
## The one surface that is not a baked pigment: the stones are tinted per tier.
## Matched by the material's own name first; the slot is the fallback, in the
## order `tools/prepare_reward_chests.py` joins the four groups.
const GEM := "Chest_Gem"
const GEM_SLOT := 3
const PULSE_HZ := 0.55
const MODELS := 4

var style := "chest"
var glow := Color(0.95, 0.74, 0.34)
var _gem: StandardMaterial3D
var _lamp: OmniLight3D
var _clock := 0.0


func setup(chest_style: String, colour: Color) -> void:
	style = chest_style if VARIANTS.has(chest_style) else "chest"
	glow = colour
	var instance: Node = SCENE.instantiate()
	var wanted := str(VARIANTS[style])
	var chosen: Node3D = null
	for child in instance.get_children():
		if str(child.name) == wanted:
			chosen = child
	for child in instance.get_children():
		if child != chosen:
			instance.remove_child(child)
			child.free()
	if chosen == null:
		# A renamed export must not delete the reward: keep the first variant.
		if instance.get_child_count() == 0:
			instance.free()
			return
		chosen = instance.get_child(0) as Node3D
	instance.remove_child(chosen)
	instance.free()
	# The GLB lays its three variants out along +x so the bake sheet can render
	# them side by side. The one kept stands on the prop's own origin, under its
	# plaque and lamp, rather than wherever the sheet put it.
	chosen.position = Vector3.ZERO
	add_child(chosen)
	_tint_gem(chosen)
	_lamp = OmniLight3D.new()
	_lamp.name = "ChestGlow"
	_lamp.light_color = glow
	_lamp.light_energy = 1.9 if style != "mini" else 1.2
	_lamp.omni_range = 5.5 if style != "hoard" else 7.0
	_lamp.position = Vector3(0.0, float(TOPS[style]) + 0.10, 0.0)
	add_child(_lamp)


## The stones and their bezel are a single baked surface, so the tier's colour is
## an override rather than a shader: the pigment under it is near-white on
## purpose, for exactly this.
func _tint_gem(root: Node3D) -> void:
	var mesh_node := _first_mesh(root)
	if mesh_node == null:
		return
	var mesh: Mesh = mesh_node.mesh
	_gem = StandardMaterial3D.new()
	_gem.resource_name = "ChestGemGlow"
	# A stone, not a lamp: the pigment stays dark so the facets read, and the
	# light comes from inside it at a level a dark wood does not clip.
	# The stone carries its tier in pigment first and light second: a bright
	# emissive face plus the sky's specular washes every hue to cream, so the
	# albedo keeps the saturation and the glow only lifts it.
	_gem.albedo_color = Color(glow.r * 0.72, glow.g * 0.52, glow.b * 0.22)
	_gem.metallic = 0.0
	_gem.roughness = 0.72
	_gem.emission_enabled = true
	_gem.emission = glow
	_gem.emission_energy_multiplier = 0.22
	var found := -1
	for surface in mesh.get_surface_count():
		var baked := mesh.surface_get_material(surface)
		if baked != null and str(baked.resource_name).findn(GEM) >= 0:
			found = surface
			break
	if found < 0 and mesh.get_surface_count() > GEM_SLOT:
		found = GEM_SLOT
	if found >= 0:
		mesh_node.set_surface_override_material(found, _gem)


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _process(delta: float) -> void:
	if _gem == null:
		return
	_clock = fmod(_clock + delta * TAU * PULSE_HZ, TAU)
	var breathe := 0.5 + 0.5 * sin(_clock)
	if _lamp != null:
		_lamp.light_energy = (1.6 + 0.7 * breathe) * (0.6 if style == "mini" else 1.0)
	_gem.emission_energy_multiplier = 0.20 + 0.10 * breathe
