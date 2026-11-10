extends SceneTree
## ABILITY chests: a skill is gated by a chest, not by a key.
##
## What this owns: that the `ability` surface pays skills (`PAYOUT_SKILLS`, never
## the mod pool) and is the rarest promise beside the key; that level one's chest
## is the island's first ABILITY chest; that its box lays out three skills a soul
## has not opened, at least one of them one the body can perform with the pair it
## is wearing; that the pick is the player's for good and on the bar when the hands
## fit it; that a gate into a new island promises an ABILITY chest whatever trial
## it prices; that a re-stood box never offers a skill already taken; and that a
## player who has opened every skill is promised a card chest instead of a box
## that would pay nothing.

const WORLD := "res://scenes/warband_world.tscn"
const TEST_STATE := "user://ability_chest_state.json"
const TEST_WARBAND := "user://ability_chest_warband.json"
const TEST_META := "user://ability_chest_meta.json"

const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const Props = preload("res://scripts/roguelite/roguelite_props.gd")
const DirectorScript = preload("res://scripts/roguelite/run_director.gd")
const State = preload("res://scripts/player_state.gd")

var game
var run
var body
var meta
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ABILITY_CHEST_FAIL  ", message)


func _initialize() -> void:
	call_deferred("execute")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func execute() -> void:
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	_check_catalog()
	await _open_world()
	_check_first_chest()
	_check_gate_promise()
	_check_no_repeat()
	_check_exhausted()
	game.queue_free()
	await process_frame
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	print("ABILITY_CHEST_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


## The catalog's half: the surface, its payout, its rarity next to the key's, and
## the fact that it no longer owns a shelf of mod cards.
func _check_catalog() -> void:
	check(Mods.surface_payout(Mods.CHEST_ABILITY) == Mods.PAYOUT_SKILLS,
		"an ability surface pays a skill (%s)"
			% Mods.surface_payout(Mods.CHEST_ABILITY))
	check(Mods.SKILL_SURFACES.has(Mods.CHEST_ABILITY), "it is a skill surface")
	check(not Mods.CARD_SURFACES.has(Mods.CHEST_ABILITY),
		"and it owns no shelf of mod cards any more")
	check(not Mods.in_chest_surface("double_nock", Mods.CHEST_ABILITY),
		"an ability-family row is no longer promised as an ability chest")
	var key_weight := float(Mods.CHEST_SURFACE_WEIGHT.get(Mods.CHEST_KEY, 1.0))
	var ability_weight := float(Mods.CHEST_SURFACE_WEIGHT.get(Mods.CHEST_ABILITY, 1.0))
	check(ability_weight < 1.0,
		"an ability promise is rare on the board (%0.2f)" % ability_weight)
	check(is_equal_approx(ability_weight, key_weight),
		"as rare as the key's (%0.2f vs %0.2f)" % [ability_weight, key_weight])
	check(Mods.keeps_promise(Mods.promise(Mods.CHEST_ABILITY, Mods.RARITY_LEGENDARY)),
		"a skill promise is kept at every tier")
	check(AbilityRules.unlockable_ids().size() > 3,
		"the catalog is deeper than one hand (%d)" % AbilityRules.unlockable_ids().size())


func _open_world() -> void:
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	var flow = root.get_node("GameFlow")
	meta = root.get_node("Roguelite")
	state.save_path = TEST_STATE
	state.reset(false)
	warband.save_path = TEST_WARBAND
	warband.reset_state()
	meta.save_path = TEST_META
	meta.reset(false)
	flow.active = false
	flow.world_start = "town"
	game = load(WORLD).instantiate()
	root.add_child(game)
	current_scene = game
	var waited := 0.0
	while waited < 40.0 and (game.get("controller") == null or game.bodies.size() < 1):
		await physics_frame
		waited += 0.016
	run = game.get("roguelite")
	check(game.bodies.size() >= 1, "the world stands a body up")
	check(run != null, "the world owns a run director")
	if game.bodies.size() >= 1:
		body = game.bodies[0]


## Level one's chest: the island's first ABILITY chest, three skills, one taken.
func _check_first_chest() -> void:
	var contract: Dictionary = run._starter_contract()
	check(str(contract.get("chest", {}).get("surface", "")) == Mods.CHEST_ABILITY,
		"level one's contract promises an ABILITY chest (%s)"
			% str(contract.get("chest", {}).get("surface", "")))
	check(str(contract.get("chest", {}).get("tier", "")) == Mods.RARITY_COMMON,
		"of commons")
	var start: Dictionary = run.start_run()
	check(bool(start.get("ok", false)), "the portal opens a run: %s"
		% str(start.get("message", "")))
	# The wave is killed outright and the level clears, which stands the box.
	var killed: Dictionary = run.admin_kill_all()
	check(bool(killed.get("ok", false)), "the field is emptied")
	run.tick(0.2)
	check(run.level_cleared, "the level clears")
	var chest = _chest()
	check(chest != null, "the clear stands the level's box")
	if chest == null:
		return
	var payload: Dictionary = Props.payload_of(chest)
	check(str(payload.get("surface", "")) == Mods.CHEST_ABILITY,
		"and it is the promised ABILITY chest (%s)" % str(payload.get("surface", "")))
	check(str(payload.get("payout", "")) == Mods.PAYOUT_SKILLS, "paying a skill")
	check(str(payload.get("offer_kind", "")) == "skill", "dealt as a skill draft")
	check(str(payload.get("label", "")).begins_with("ABILITY"),
		"the lid says what it is (%s)" % str(payload.get("label", "")))
	var serial := int(chest.get_meta("serial"))
	var offers: Array = run._offers_for(serial, 1)
	check(offers.size() == 3, "three skills stand on the lid (%d)" % offers.size())
	var player = run.players.get(1)
	var worn_main: Dictionary = State.ITEMS.get(str(player.ranged_id), {})
	var worn_off: Dictionary = State.ITEMS.get(str(player.melee_id), {})
	var fitting := 0
	for raw in offers:
		var definition: Dictionary = AbilityRules.by_id(str(raw))
		check(not definition.is_empty(), "an offer is a skill (%s)" % str(raw))
		check(not AbilityRules.is_automatic(str(raw)),
			"never a starter or a consumable (%s)" % str(raw))
		check(not meta.is_ability_unlocked(str(raw)),
			"and never one already open (%s)" % str(raw))
		if AbilityRules.fits_gear(definition, worn_main, worn_off):
			fitting += 1
	check(fitting >= 1,
		"at least one fits the pair the body is wearing (%d of %d)"
			% [fitting, offers.size()])
	# The pick.
	run._open_chest(serial, body)
	check(not run._opened.has(serial), "the box waits for its pick")
	var pick := str(offers[0])
	var answer: Dictionary = run.choose_draft(1, serial, 0)
	check(bool(answer.get("ok", false)), "the first skill is taken: %s"
		% str(answer.get("message", "")))
	check(meta.is_ability_unlocked(pick),
		"the skill is the player's from the pick onward (%s)" % pick)
	var fits := AbilityRules.fits_gear(AbilityRules.by_id(pick), worn_main, worn_off)
	check(Array(game.warband.roster.hotbar_order_of(int(player.merc_id))).has(pick) == fits,
		"and rides the bar exactly when the hands fit it (%s, fits=%s)"
			% [pick, str(fits)])
	check(run._opened.has(serial), "the box is spent on the pick")
	check(run._opened.has("chest"), "and the gates unseal")
	check(player.armor.is_empty(), "an ability chest pays no armour (%d slots)"
		% player.armor.size())
	check(int(run.keys_earned) == 0, "and no keys")


## The door onto a new island promises the same chest, whatever its trial prices.
func _check_gate_promise() -> void:
	var contracts: Array = run._gate_contracts(DirectorScript.LEVELS_PER_ISLAND + 1)
	check(contracts.size() == 3, "three gates stand into the new island")
	var surfaces: Dictionary = {}
	var texts: Dictionary = {}
	for contract in contracts:
		var chest: Dictionary = (contract as Dictionary).get("chest", {})
		surfaces[str(chest.get("surface", ""))] = true
		texts[str((contract as Dictionary).get("label", ""))] = true
	check(surfaces.size() == 1 and surfaces.has(Mods.CHEST_ABILITY),
		"every door into a new island promises an ABILITY chest (%s)"
			% str(surfaces.keys()))
	var labelled := 0
	for label in texts:
		if str(label).begins_with("ABILITY"):
			labelled += 1
	check(labelled == texts.size(),
		"and every one says so on its lintel (%s)" % str(texts.keys()))
	# The swarm trial still doubles the box: three doors, three prices.
	var doubled := 0
	for contract in contracts:
		var chest: Dictionary = (contract as Dictionary).get("chest", {})
		if int(chest.get("mult", 1)) > 1:
			doubled += 1
	check(doubled == 1, "one of the three is the swarm's 2X (%d)" % doubled)
	# A floor inside the block is not the island's first: it rolls a real surface.
	var inner: Array = run._gate_contracts(3)
	var inner_surfaces: Dictionary = {}
	for contract in inner:
		inner_surfaces[str((contract as Dictionary).get("chest", {}).get("surface", ""))] = true
	check(not (inner_surfaces.size() == 1 and inner_surfaces.has(Mods.CHEST_ABILITY)),
		"a mid-island door rolls the ordinary board (%s)" % str(inner_surfaces.keys()))


## A re-stood box draws from what the player has not opened: the skill just taken
## is out of the pool for good.
func _check_no_repeat() -> void:
	var taken := ""
	for id in AbilityRules.unlockable_ids():
		if meta.is_ability_unlocked(str(id)):
			taken = str(id)
			break
	check(not taken.is_empty(), "a skill was taken from the first box (%s)" % taken)
	var restood: Dictionary = run.admin_stand_chests(false)
	check(bool(restood.get("ok", false)), "the console re-stands the box")
	var chest = _chest()
	check(chest != null, "a fresh box stands")
	if chest == null:
		return
	var offers: Array = run._offers_for(int(chest.get_meta("serial")), 1)
	check(offers.size() == 3, "and deals three skills again (%d)" % offers.size())
	check(not offers.has(taken),
		"never the one the player already owns (%s)" % taken)


## A player with every skill open is promised a card chest: a box that could pay
## nothing is not a promise.
func _check_exhausted() -> void:
	for id in AbilityRules.unlockable_ids():
		meta.grant_ability(str(id))
	check(not run._ability_promise_available(),
		"with every skill open there is no skill left to promise")
	var contract: Dictionary = run._starter_contract()
	check(str(contract.get("chest", {}).get("surface", "")) != Mods.CHEST_ABILITY,
		"so level one's contract falls back to a card chest (%s)"
			% str(contract.get("chest", {}).get("surface", "")))
	check(str(contract.get("chest", {}).get("surface", "")) == Mods.CHEST_ATTACK,
		"the teaching Attack chest")
	var gates: Array = run._gate_contracts(DirectorScript.LEVELS_PER_ISLAND + 1)
	var still_ability := 0
	for gate in gates:
		var chest: Dictionary = (gate as Dictionary).get("chest", {})
		if str(chest.get("surface", "")) == Mods.CHEST_ABILITY:
			still_ability += 1
	check(still_ability == 0,
		"and no door into a new island promises one (%d)" % still_ability)


func _chest() -> Node3D:
	for prop in run._props:
		if is_instance_valid(prop) and Props.prop_kind(prop) == "chest":
			return prop
	return null
