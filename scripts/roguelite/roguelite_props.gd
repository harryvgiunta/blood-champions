class_name RogueliteProps
extends RefCounted
## The interactive furniture of an island: reward chests, the shop and the biome
## portals.
##
## Every prop is procedural (`Geo` primitives), carries its own `Label3D` so a
## player never has to read the HUD to know what they are walking up to, and
## stores its payload in metadata so the director can answer an interaction
## without a second table. Nothing here decides a reward: the node is the door,
## the director is the roll.

const Geo = preload("res://scripts/geo.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const CardArt = preload("res://scripts/roguelite/card_art.gd")
const ChestVisual = preload("res://scripts/roguelite/chest_visual.gd")
const GateVisual = preload("res://scripts/roguelite/gate_visual.gd")
## The plaque's name is set in the ledger's display face, like every other
## heading in the game.
const DISPLAY_FONT: FontFile = preload("res://assets/ui/fonts/PirataOne-Regular.ttf")

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

## A reward chest. `style` is the prop's own build: `"chest"` for the island's
## own, `"mini"` for a cache a Buried Cache or a kill pays for, and `"elite"` for
## the box a boss leaves.
##
## What the chest *promises* rides the payload (`surface`, `tier`), and the lid
## glows the tier's own colour, so a legendary promise is readable from the entry
## line. A chest stood with an `offers` table opens a draft of three for the body
## it was stood for, exactly as it opens its lid.
##
## A co-op level stands one chest a player, so the payload also names its owner
## (`owner_name`, `owner_colour`) and the box wears that name over the promise: a
## party has to be able to tell whose box it is walking up to from the entry
## line, without reading the HUD.
static func chest(parent: Node3D, at: Vector3, style: String = "chest",
		payload: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "RewardChest"
	parent.add_child(root)
	# Props are handed a world point and stand on it: the island they hang from
	# has its own transform, so a local assignment would double it.
	root.global_position = at
	var tier := str(payload.get("tier", ""))
	var glow := Color(0.95, 0.74, 0.34)
	if style == "mini":
		glow = Color(0.84, 0.40, 0.28)
	elif style == "elite":
		glow = Color(0.95, 0.35, 0.28)
	elif Mods.RARITY_COLOUR.has(tier):
		glow = Mods.RARITY_COLOUR[tier]
	# The prop itself: an authored, Cycles-textured chest, one of three.
	var model: Node3D = ChestVisual.new()
	model.name = "Model"
	root.add_child(model)
	model.setup(style, glow)
	var text := str(payload.get("label", ""))
	if text.is_empty():
		text = "REWARD CHEST"
		if style == "mini":
			text = "CACHE"
		elif style == "elite":
			text = "WARDEN'S HOARD"
	var top := float(ChestVisual.TOPS.get(style, 0.91))
	# The plate is a little wider than the box it names, not wider than the
	# player: a sign that eats the screen is not a sign.
	var plate: float = {"mini": 1.15, "elite": 2.00}.get(style, 1.70)
	_plaque(root, text, Vector3(0.0, top + 0.42, 0.0), glow, tier, plate)
	# Whose box it is, on its own plate above the promise. Only a chest stood for
	# a name wears one: the mini caches a kill drops belong to whoever reaches
	# them.
	var owner := str(payload.get("owner_name", ""))
	if not owner.is_empty():
		var ink: Variant = payload.get("owner_colour", INK)
		_plaque(root, owner.to_upper(), Vector3(0.0, top + 1.02, 0.0),
			ink if ink is Color else INK, "", 1.10)
	tag_prop(root, "chest", payload.merged({"style": style}, true))
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
	_plaque(root, "GREED TOTEM", Vector3(0.0, 3.50, 0.0), Color(0.94, 0.36, 0.28),
		Mods.RARITY_GREED, 1.70)
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
		# The name only: the price is on the card the stall opens, and a plate
		# narrow enough to stand clear of its neighbour cannot hold both.
		_plaque(root, str(ware.get("name", "?")), Vector3(x, 1.66, 0.0), colour,
			str(ware.get("rarity", "common")), 1.10)
	_plaque(root, str(payload.get("label", "THE SHOP ISLAND")).to_upper(),
		Vector3(0.0, 2.58, 0.0), Color(0.86, 0.70, 0.35),
		Mods.RARITY_LEGENDARY, 2.00)
	tag_prop(root, "shop", payload.merged({"wares": wares.duplicate(true)}, true))
	return root


# --- recruiter -------------------------------------------------------------

## The recruiter's desk: the town's counter, standing on a shop level, with one
## board per body for sale - the name over it and the archetype and price cut
## under it. The prop kind is `recruiter`; its payload carries the board the panel
## reads, so a guest renders the same three bodies the host is selling.
static func recruiter(parent: Node3D, at: Vector3, hires: Array,
		payload: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "RecruiterDesk"
	parent.add_child(root)
	root.global_position = at
	var wood := Geo.material(Color(0.26, 0.18, 0.12), 0.0, 0.9)
	var iron := Geo.material(Color(0.34, 0.33, 0.31), 0.5, 0.45)
	var ink := Color(0.52, 0.10, 0.10)
	var brass := Color(0.86, 0.70, 0.35)
	# The counter a body walks up to: the same trestle the square's desk is, so a
	# player who has hired in town reads this one at a glance.
	Geo.box(root, Vector3(2.2, 0.16, 0.8), Vector3(0.0, 1.02, 0.0), wood)
	for side in [-1.0, 1.0]:
		Geo.cylinder(root, 0.09, 0.09, 1.02, Vector3(float(side) * 0.92, 0.51, 0.0),
			wood, 6)
	for index in hires.size():
		var offer: Dictionary = hires[index]
		var x := (float(index) - float(maxi(1, hires.size()) - 1) * 0.5) * 0.68
		# A board leaning on the counter, the man's name above it and the price
		# under it: what is for sale, at what, in one read.
		Geo.box(root, Vector3(0.44, 0.46, 0.04), Vector3(x, 1.40, 0.12), iron)
		_plaque(root, str(offer.get("name", "?")).to_upper(), Vector3(x, 1.80, 0.12),
			brass, Mods.RARITY_LEGENDARY, 1.0)
		_plaque(root, "%s  ·  %d GOLD" % [str(offer.get("archetype_label", "")),
			int(offer.get("price", 0))], Vector3(x, 1.26, 0.12), ink,
			Mods.RARITY_GREED, 0.72)
	_plaque(root, str(payload.get("label", "THE RECRUITER")).to_upper(),
		Vector3(0.0, 2.40, 0.0), brass, Mods.RARITY_LEGENDARY, 1.8)
	tag_prop(root, "recruiter", payload.merged({"hires": hires.duplicate(true)}, true))
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
	_plaque(root, "WEAPON RACK", Vector3(0.0, 2.98, 0.0), Color(0.92, 0.86, 0.68),
		Mods.RARITY_LEGENDARY, 1.70)
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
	# A chamber's gate turns to face the party's line; an island's payload says 0.
	root.rotation.y = float(payload.get("yaw", 0.0))
	# The door itself: coursed granite, black rock hung with bone, or a body
	# turned inside out, with the promise's sheet standing in its opening.
	var model: Node3D = GateVisual.new()
	model.name = "Model"
	root.add_child(model)
	model.setup(biome_id, gate_glow(biome_id))
	# The plates hang clear above the lintel: a sign through a beam is a sign no
	# one reads.
	_plaque(root, biome_name, Vector3(0.0, 4.58, 0.0), gate_glow(biome_id),
		Mods.RARITY_EPIC, 1.70)
	var contract_label := str(payload.get("label", ""))
	if not contract_label.is_empty():
		_plaque(root, contract_label, Vector3(0.0, 4.10, 0.0),
			gate_glow(biome_id), Mods.RARITY_COMMON, 2.20)
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


# --- helpers ---------------------------------------------------------------

## The plate a prop hangs its name on: the tier's rendered plaque standing as a
## camera billboard, with the words laid over it in the display face. `width` is
## the plate's width in metres; the type is scaled to fit inside it, so a long
## contract line and a two-word name both sit on their plate.
static func _plaque(parent: Node3D, text: String, at: Vector3, colour: Color,
		rarity: String = "", width: float = 2.2) -> Node3D:
	var root := Node3D.new()
	root.name = "Plaque"
	root.position = at
	parent.add_child(root)
	var plate := Sprite3D.new()
	plate.texture = CardArt.plaque(rarity)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	plate.render_priority = 2
	plate.pixel_size = width / 1024.0
	root.add_child(plate)
	var label := Label3D.new()
	label.text = text
	label.font = DISPLAY_FONT
	label.font_size = 64
	# PirataOne advances about 0.46 em. The plate keeps two fifths of its width
	# clear as margin, so the name sits *on* a sign rather than filling it.
	var advance := 0.46 * 64.0
	var fitting := width * 0.60 / maxf(1.0, float(text.length()) * advance)
	label.pixel_size = clampf(fitting, 0.0008, 0.0024)
	label.modulate = colour.lightened(0.35)
	label.outline_modulate = Color(0.02, 0.02, 0.03, 0.62)
	label.outline_size = 8
	label.render_priority = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	root.add_child(label)
	return root


static func _rarity_colour(rarity: String) -> Color:
	return Mods.RARITY_COLOUR.get(rarity, Color(0.86, 0.90, 0.82))
