class_name RogueliteProps
extends RefCounted
## The interactive furniture of an island: reward chests, mod pedestals, Greed
## Totems, the shop and the biome portals.
##
## Every prop is procedural (`Geo` primitives), carries its own `Label3D` so a
## player never has to read the HUD to know what they are walking up to, and
## stores its payload in metadata so the director can answer an interaction
## without a second table. Nothing here decides a reward: the node is the door,
## the director is the roll.

const Geo = preload("res://scripts/geo.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")

const META := "roguelite_prop"

const INK := Color(0.96, 0.90, 0.74)
const MUTED := Color(0.74, 0.68, 0.56)


static func tag_prop(node: Node3D, kind: String, payload: Dictionary) -> Node3D:
	node.set_meta(META, kind)
	node.set_meta("payload", payload)
	return node


static func prop_kind(node) -> String:
	if node == null or not is_instance_valid(node) or not (node is Node):
		return ""
	return str(node.get_meta(META, ""))


static func payload_of(node) -> Dictionary:
	if node == null or not is_instance_valid(node) or not (node is Node):
		return {}
	var raw: Variant = node.get_meta("payload", {})
	return raw if raw is Dictionary else {}


# --- chest -----------------------------------------------------------------

## A reward chest. `tier` is `"chest"` for the island's own, `"mini"` for the
## extra one a Buried Cache pays for, and `"elite"` for the one a boss leaves.
static func chest(parent: Node3D, at: Vector3, tier: String = "chest",
		payload: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "RewardChest"
	parent.add_child(root)
	# Props are handed a world point and stand on it: the island they hang from
	# has its own transform, so a local assignment would double it.
	root.global_position = at
	var wood := Geo.material(Color(0.30, 0.20, 0.13), 0.0, 0.86)
	var iron := Geo.material(Color(0.20, 0.20, 0.21), 0.6, 0.42)
	var glow := Color(0.95, 0.74, 0.34) if tier == "chest" else Color(0.84, 0.40, 0.28)
	if tier == "elite":
		glow = Color(0.95, 0.35, 0.28)
	var trim := Geo.material(glow, 0.35, 0.35)
	trim.emission_enabled = true
	trim.emission = glow
	trim.emission_energy_multiplier = 0.6
	var size := 1.0 if tier != "mini" else 0.66
	Geo.box(root, Vector3(1.2, 0.62, 0.78) * size, Vector3(0.0, 0.31 * size, 0.0), wood)
	Geo.box(root, Vector3(1.28, 0.20, 0.84) * size, Vector3(0.0, 0.66 * size, 0.0), wood)
	for x in [-0.45, 0.45]:
		Geo.box(root, Vector3(0.09, 0.66, 0.82) * size,
			Vector3(float(x) * size, 0.34 * size, 0.0), iron)
	Geo.box(root, Vector3(1.34, 0.08, 0.88) * size, Vector3(0.0, 0.55 * size, 0.0), trim)
	Geo.box(root, Vector3(0.18, 0.22, 0.08) * size, Vector3(0.0, 0.46 * size, 0.42 * size), trim)
	var light := OmniLight3D.new()
	light.light_color = glow
	light.light_energy = 1.1 if tier != "mini" else 0.6
	light.omni_range = 5.0
	light.position = Vector3(0.0, 0.9 * size, 0.0)
	root.add_child(light)
	var text := "REWARD CHEST"
	if tier == "mini":
		text = "CACHE"
	elif tier == "elite":
		text = "WARDEN'S HOARD"
	_label(root, text, Vector3(0.0, 1.35 * size, 0.0), glow, 40)
	tag_prop(root, "chest", payload.merged({"tier": tier}, true))
	return root


# --- pedestal --------------------------------------------------------------

## An item pedestal and the three choices standing over it. `offers` is the local
## body's own row; the payload may carry the whole party's table, which is what
## every machine reads its row from.
static func pedestal(parent: Node3D, at: Vector3, offers: Array,
		payload: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "ModPedestal"
	parent.add_child(root)
	# Props are handed a world point and stand on it: the island they hang from
	# has its own transform, so a local assignment would double it.
	root.global_position = at
	var stone := Geo.material(Color(0.28, 0.26, 0.23), 0.0, 0.9)
	var gold := Geo.material(Color(0.86, 0.70, 0.35), 0.55, 0.35)
	Geo.cylinder(root, 0.62, 0.48, 0.9, Vector3(0.0, 0.45, 0.0), stone, 8)
	Geo.cylinder(root, 0.70, 0.70, 0.10, Vector3(0.0, 0.94, 0.0), gold, 8)
	# A slow ring of light: the pedestal is the one thing on the island that wants
	# a player to walk to it.
	var halo := OmniLight3D.new()
	halo.light_color = Color(0.78, 0.86, 1.0)
	halo.light_energy = 1.0
	halo.omni_range = 6.0
	halo.position = Vector3(0.0, 1.5, 0.0)
	root.add_child(halo)
	for index in offers.size():
		var mod_id := str(offers[index])
		var colour := Color(0.86, 0.90, 0.82)
		var display := mod_id
		var row := Mods.get_mod(mod_id)
		if not row.is_empty():
			colour = _rarity_colour(str(row.get("rarity", "common")))
			display = str(row.get("name", mod_id))
		var angle := -0.7 + 1.4 * (float(index) / float(maxi(1, offers.size() - 1)))
		var card := Node3D.new()
		card.name = "Offer%d" % index
		card.position = Vector3(sin(angle) * 1.45, 1.45 + float(index % 2) * 0.18,
			cos(angle) * 1.45)
		root.add_child(card)
		var plate := Geo.box(card, Vector3(0.62, 0.9, 0.05), Vector3.ZERO,
			Geo.material(Color(0.07, 0.07, 0.08), 0.0, 0.6))
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var edge := Geo.box(card, Vector3(0.68, 0.96, 0.03), Vector3(0.0, 0.0, -0.02),
			Geo.material(colour, 0.4, 0.3))
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_label(card, display, Vector3(0.0, 0.16, 0.06), colour, 28, 0.004)
		_label(card, str(row.get("rarity", "")).to_upper(), Vector3(0.0, -0.2, 0.06),
			Color(0.85, 0.82, 0.74), 22, 0.004)
	# The payload is the wire's: a director hands the whole party's draft table
	# here and the cards above are only the local body's row. A caller with no
	# table to give still gets the three it drew stamped on the prop.
	var wire := payload
	if not wire.has("offers"):
		wire = wire.merged({"offers": offers.duplicate()}, true)
	tag_prop(root, "pedestal", wire)
	return root


# --- greed totem -----------------------------------------------------------

## A greed totem: a tall bone pole with a burning bowl. Its press is the bargain
## the run's own risk economy is built on.
static func greed_totem(parent: Node3D, at: Vector3, payload: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "GreedTotem"
	parent.add_child(root)
	# Props are handed a world point and stand on it: the island they hang from
	# has its own transform, so a local assignment would double it.
	root.global_position = at
	var bone := Geo.material(Color(0.76, 0.70, 0.56), 0.0, 0.7)
	var iron := Geo.material(Color(0.22, 0.18, 0.16), 0.5, 0.45)
	var blood := Geo.material(Color(0.62, 0.09, 0.08), 0.0, 0.5)
	blood.emission_enabled = true
	blood.emission = Color(0.8, 0.12, 0.08)
	blood.emission_energy_multiplier = 1.6
	Geo.cylinder(root, 0.16, 0.22, 2.6, Vector3(0.0, 1.3, 0.0), bone, 7)
	Geo.cylinder(root, 0.42, 0.34, 0.34, Vector3(0.0, 2.62, 0.0), iron, 8)
	Geo.sphere(root, 0.34, Vector3(0.0, 2.84, 0.0), blood, Vector3(1.0, 0.7, 1.0))
	for index in 4:
		var angle := TAU * float(index) / 4.0
		var horn := Geo.cylinder(root, 0.06, 0.015, 0.62,
			Vector3(cos(angle) * 0.3, 2.2, sin(angle) * 0.3), bone, 5)
		horn.rotation.z = cos(angle) * 0.5
		horn.rotation.x = sin(angle) * 0.5
	var light := OmniLight3D.new()
	light.light_color = Color(0.95, 0.22, 0.16)
	light.light_energy = 1.8
	light.omni_range = 7.5
	light.position = Vector3(0.0, 2.9, 0.0)
	root.add_child(light)
	_label(root, "GREED TOTEM", Vector3(0.0, 3.5, 0.0), Color(0.94, 0.36, 0.28), 38)
	tag_prop(root, "greed", payload)
	return root


# --- shop ------------------------------------------------------------------

## The shop island's stall: a keeper's counter with three wares and their prices.
static func shop(parent: Node3D, at: Vector3, wares: Array, payload: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "ShopIsland"
	parent.add_child(root)
	# Props are handed a world point and stand on it: the island they hang from
	# has its own transform, so a local assignment would double it.
	root.global_position = at
	var wood := Geo.material(Color(0.28, 0.20, 0.13), 0.0, 0.88)
	var cloth := Geo.material(Color(0.24, 0.30, 0.28), 0.0, 0.94)
	var gold := Geo.material(Color(0.86, 0.70, 0.35), 0.55, 0.35)
	Geo.box(root, Vector3(2.4, 0.14, 1.0), Vector3(0.0, 1.05, 0.0), wood)
	for side in [-1.0, 1.0]:
		Geo.cylinder(root, 0.10, 0.10, 1.05,
			Vector3(float(side) * 1.05, 0.52, 0.0), wood, 7)
	Geo.box(root, Vector3(2.6, 0.06, 1.2), Vector3(0.0, 2.1, 0.0), cloth)
	for side in [-1.0, 1.0]:
		Geo.cylinder(root, 0.08, 0.08, 2.1,
			Vector3(float(side) * 1.2, 1.05, -0.5), wood, 6)
	for index in wares.size():
		var ware: Dictionary = wares[index]
		var x := (float(index) - float(maxi(1, wares.size()) - 1) * 0.5) * 0.72
		var colour := _rarity_colour(str(ware.get("rarity", "common")))
		Geo.sphere(root, 0.16, Vector3(x, 1.26, 0.0), Geo.material(colour, 0.3, 0.3))
		_label(root, "%s  ·  %d" % [str(ware.get("name", "?")),
			int(ware.get("price", 0))], Vector3(x, 1.62, 0.0), colour, 26, 0.004)
	_label(root, "THE SHOP ISLAND", Vector3(0.0, 2.55, 0.0), Color(0.86, 0.70, 0.35), 38)
	tag_prop(root, "shop", payload.merged({"wares": wares.duplicate(true)}, true))
	return root


# --- rack ------------------------------------------------------------------

## The shop level's Weapon Rack: the same board the town keeps, so a party can
## spend the boss key it just earned and take the new piece straight into the
## next fight.
static func rack(parent: Node3D, at: Vector3, payload: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "WeaponRack"
	parent.add_child(root)
	root.global_position = at
	var wood := Geo.material(Color(0.28, 0.20, 0.13), 0.0, 0.88)
	var steel := Geo.material(Color(0.70, 0.74, 0.75), 0.7, 0.3)
	var iron := Geo.material(Color(0.20, 0.20, 0.21), 0.6, 0.42)
	for side in [-1.0, 1.0]:
		Geo.box(root, Vector3(0.18, 2.0, 0.18), Vector3(float(side) * 1.25, 1.0, 0.0), wood)
	Geo.box(root, Vector3(2.9, 0.18, 0.24), Vector3(0.0, 1.85, 0.0), wood)
	Geo.box(root, Vector3(2.9, 0.14, 0.24), Vector3(0.0, 0.9, 0.0), wood)
	for index in 3:
		var x := (float(index) - 1.0) * 0.78
		Geo.cylinder(root, 0.035, 0.035, 1.45, Vector3(x, 1.4, 0.12), wood, 6)
		var blade := Geo.box(root, Vector3(0.11, 0.5, 0.03),
			Vector3(x, 2.18, 0.12), steel if index != 1 else iron)
		blade.rotation.z = 0.12 if index == 0 else (-0.1 if index == 2 else 0.0)
	_label(root, "WEAPON RACK", Vector3(0.0, 2.95, 0.0), Color(0.92, 0.86, 0.68), 38)
	tag_prop(root, "rack", payload)
	return root


# --- portal ----------------------------------------------------------------

## A gate out of a cleared level: the frame every faction builds its door on, and
## then the faction's own body on the stone. The wood keeps its grey ring and the
## green sheet it always had; the demons hang their gate in black rock, bone and
## skulls; the blood clones stand a body turned inside out - red flesh, ribs, and
## a heart in the lintel. All three lead one level on; the director reads which
## was taken from the payload's `biome`.
static func portal(parent: Node3D, at: Vector3, biome_id: String,
		biome_name: String, payload: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Gate_%s" % biome_id
	parent.add_child(root)
	# Props are handed a world point and stand on it: the island they hang from
	# has its own transform, so a local assignment would double it.
	root.global_position = at
	match biome_id:
		"caves":
			_gate_demons(root)
		"arena":
			_gate_clones(root)
		_:
			_gate_watchers(root)
	_label(root, biome_name, Vector3(0.0, 4.05, 0.0), gate_glow(biome_id), 40)
	tag_prop(root, "portal", payload.merged({"biome": biome_id}, true))
	return root


## The colour a gate's sheet, light and lintel burn with.
static func gate_glow(biome_id: String) -> Color:
	match biome_id:
		"caves":
			return Color(0.98, 0.32, 0.10)
		"arena":
			return Color(0.94, 0.12, 0.14)
	return Color(0.48, 0.78, 0.52)


## The posts, the lintel and the sheet every gate is built on. A faction dresses
## around it; none of them rewrites it, so the three stay one family of door.
static func _gate_frame(root: Node3D, stone: Material, sheet: Material,
		glow: Color, energy: float = 1.2) -> void:
	for side in [-1.0, 1.0]:
		Geo.box(root, Vector3(0.44, 3.3, 0.5), Vector3(float(side) * 1.3, 1.65, 0.0), stone)
	Geo.box(root, Vector3(3.1, 0.5, 0.56), Vector3(0.0, 3.42, 0.0), stone)
	Geo.box(root, Vector3(2.2, 2.9, 0.06), Vector3(0.0, 1.6, 0.02), sheet)
	var light := OmniLight3D.new()
	light.light_color = glow
	light.light_energy = 2.0
	light.omni_range = 10.0
	light.position = Vector3(0.0, 1.7, 0.6)
	root.add_child(light)
	if energy > 0.0:
		(sheet as StandardMaterial3D).emission_energy_multiplier = energy


static func _glow_material(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := Geo.material(colour, 0.4, 0.3)
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	return mat


## Watchers: the wood's own door - grey stone, a green sheet, two thin posts of
## light. It is the gate the run has always opened on.
static func _gate_watchers(root: Node3D) -> void:
	var glow := gate_glow("wilderness")
	var stone := Geo.material(Color(0.26, 0.25, 0.23), 0.0, 0.9)
	var trim := _glow_material(glow, 1.2)
	_gate_frame(root, stone, trim, glow)
	for side in [-1.0, 1.0]:
		Geo.box(root, Vector3(0.10, 3.0, 0.10), Vector3(float(side) * 1.12, 1.6, 0.06), trim)


## Demons: black rock hung with bone. Skulls watch from both posts, ribs of bone
## climb the lintel, and the sheet burns the colour of a forge mouth.
static func _gate_demons(root: Node3D) -> void:
	var glow := gate_glow("caves")
	var rock := Geo.material(Color(0.05, 0.045, 0.05), 0.05, 0.95)
	var core := _glow_material(Color(0.42, 0.06, 0.04), 0.5)
	var bone := Geo.material(Color(0.84, 0.81, 0.70), 0.0, 0.55)
	var dark := Geo.material(Color(0.03, 0.02, 0.02), 0.0, 0.9)
	_gate_frame(root, rock, core, glow, 0.55)
	# The sheet is a mouth in the dark rock, not a sheet of light: one ember line
	# down its middle reads as the far side of the fire.
	Geo.box(root, Vector3(0.14, 2.7, 0.09), Vector3(0.0, 1.6, 0.05), _glow_material(glow, 1.9))
	for side in [-1.0, 1.0]:
		var x := float(side) * 1.3
		for step in 3:
			var y := 1.05 + 0.95 * float(step)
			# A skull: a cranium, a jaw under it, and the two holes it looks out of.
			Geo.sphere(root, 0.17, Vector3(x, y, 0.34), bone)
			Geo.box(root, Vector3(0.17, 0.07, 0.14), Vector3(x, y - 0.16, 0.34), bone)
			for eye in [-1.0, 1.0]:
				Geo.box(root, Vector3(0.05, 0.06, 0.05),
					Vector3(x + float(eye) * 0.06, y + 0.02, 0.47), dark)
		# Bone spurs jutting out of the post's back.
		for step in 2:
			var spur := Geo.cylinder(root, 0.035, 0.0, 0.5,
				Vector3(x + float(side) * 0.3, 2.2 + 0.5 * float(step), -0.12), bone, 6)
			spur.rotation.z = float(side) * 0.9
	# Ribs of bone along the lintel, caught between the posts.
	for step in 5:
		var rib := Geo.cylinder(root, 0.04, 0.05, 0.62,
			Vector3(-0.9 + 0.45 * float(step), 3.72, 0.0), bone, 6)
		rib.rotation.x = 0.35
	Geo.sphere(root, 0.2, Vector3(0.0, 3.36, 0.34), bone)


## Blood clones: a body turned inside out. Dark maroon flesh for stone, a bright
## blood sheet, ribs standing proud of both posts and a heart hanging off the
## lintel with its veins drawn over the flesh.
static func _gate_clones(root: Node3D) -> void:
	var glow := gate_glow("arena")
	var flesh := Geo.material(Color(0.26, 0.03, 0.04), 0.0, 0.55)
	var sinew := Geo.material(Color(0.70, 0.26, 0.28), 0.0, 0.35)
	var core := _glow_material(Color(0.62, 0.04, 0.05), 1.1)
	var blood := _glow_material(glow, 1.8)
	_gate_frame(root, flesh, core, glow, 1.1)
	# Ribs: pale sinew over the dark flesh, six a side, each a step further out.
	for side in [-1.0, 1.0]:
		var x := float(side) * 1.3
		for step in 6:
			var y := 0.62 + 0.52 * float(step)
			var rib := Geo.sphere(root, 0.115, Vector3(x, y, 0.30), sinew,
				Vector3(1.7, 0.55, 1.2))
			rib.rotation.z = 0.12 * float(side) * float(step) - 0.1 * float(side)
		# The muscle the ribs are set in, a shade lighter than the frame.
		Geo.box(root, Vector3(0.12, 2.9, 0.16), Vector3(x + float(side) * 0.16, 1.6, 0.22), sinew)
	# The heart: out in front of the lintel where it can be read from the ground.
	var heart := Geo.sphere(root, 0.24, Vector3(0.0, 3.30, 0.44), blood,
		Vector3(1.0, 1.15, 0.85))
	heart.rotation.z = 0.3
	Geo.sphere(root, 0.11, Vector3(0.17, 3.48, 0.42), blood)
	Geo.beam(root, Vector3(-0.05, 3.18, 0.40), Vector3(-1.22, 2.30, 0.34), 0.05, sinew)
	Geo.beam(root, Vector3(0.05, 3.18, 0.40), Vector3(1.22, 2.30, 0.34), 0.05, sinew)
	Geo.beam(root, Vector3(0.0, 3.52, 0.40), Vector3(0.0, 3.68, 0.20), 0.045, sinew)
	# A seam of blood down the sheet: the body is open, and something is behind it.
	Geo.box(root, Vector3(0.10, 2.6, 0.09), Vector3(0.0, 1.65, 0.06), blood)
	for step in 4:
		Geo.box(root, Vector3(0.34, 0.06, 0.07),
			Vector3(-0.5 + 0.34 * float(step), 2.35 - 0.3 * float(step), 0.06), blood)


# --- helpers ---------------------------------------------------------------

static func _label(parent: Node3D, text: String, at: Vector3, colour: Color,
		size: int = 36, pixel: float = 0.006) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = colour
	label.outline_modulate = Color(0.03, 0.03, 0.04, 0.9)
	label.outline_size = 12
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	return label


static func _rarity_colour(rarity: String) -> Color:
	return Mods.RARITY_COLOUR.get(rarity, Color(0.86, 0.90, 0.82))
