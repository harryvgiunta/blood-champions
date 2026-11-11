extends SceneTree
## Blood Champions end to end: the player ledger, the armory, the upgrade engine,
## the town's two fixtures, and one endless run from level one through a market,
## a shop, a boss, and the island after it.
##
## What this owns: that a new player has no keys and only the starters, that the
## rack opens a named weapon for its price and wears it out of the inventory, that
## the run carries the kit the town shows, that the stacking rules
## still answer, that a run writes its level and island, that a boss is the only
## key drop, that level 6 is the market and level 9 the shop, that the portal
## carries the party on, and that closing back onto the square restores the body.

const WORLD = "res://scenes/warband_world.tscn"
const TEST_STATE := "user://roguelite_regression_state.json"
const TEST_WARBAND := "user://roguelite_regression_warband.json"
const TEST_META := "user://roguelite_regression_meta.json"

const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const ProcEngineScript = preload("res://scripts/roguelite/proc_engine.gd")
const StageScript = preload("res://scripts/roguelite/roguelite_stage.gd")
const DirectorScript = preload("res://scripts/roguelite/run_director.gd")
const CorpseHold = preload("res://scripts/corpse_hold.gd")
const Props = preload("res://scripts/roguelite/roguelite_props.gd")
const ChestVisual = preload("res://scripts/roguelite/chest_visual.gd")
const GateVisual = preload("res://scripts/roguelite/gate_visual.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const ArmorLoot = preload("res://scripts/roguelite/armor_loot.gd")
const RunPlayerScript = preload("res://scripts/roguelite/run_player.gd")
const AbilityIndex = preload("res://scripts/roguelite/ability_index.gd")
const CloneScript = preload("res://scripts/ranger_clone.gd")
const CloneAi = preload("res://scripts/clone_ai.gd")
const CaveRoomScript = preload("res://scripts/roguelite/cave_room.gd")
const CaveLayout = preload("res://scripts/world/cave_plan.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const DodgeRoll = preload("res://scripts/dodge_roll.gd")
const RunningSlide = preload("res://scripts/running_slide.gd")

## The one field `AbilityRules.damage_for` reads off a rig for the spell channel.
class SpellRig extends RefCounted:
	var scale := 2.0
	func spell_scale() -> float:
		return scale

## The six hands a body can hold, as `carrier_tags()` names them: the weapon
## family, the group it belongs to, and the wildcard. A chest deals every body
## its own hand from the surface its gate promised, out of the rows it has left.
const BODY_HANDS := [
	{"tags": ["bow", "ranged", "any"], "taken": []},
	{"tags": ["staff", "ranged", "any"], "taken": []},
	{"tags": ["sword", "melee", "any"], "taken": []},
	{"tags": ["dagger", "melee", "any"], "taken": []},
	{"tags": ["shield", "melee", "any"], "taken": []},
	{"tags": ["unarmed", "melee", "any"], "taken": []},
]

## A ranger rig that only records what it was handed, for the pit's loadout roll:
## the clone's own `_roll_loadout` needs a `rig` and nothing else of it.
class KitRig extends Node:
	var loadout: Dictionary = {}
	## The item skill the clone rolled for itself, as it handed it to the rig. A
	## real `Archer` keeps it on its own bench; the stub only has to accept it.
	var ability_loadout: Variant = null

	func apply_loadout(rolled: Dictionary) -> void:
		loadout = rolled

	func set_ability_loadout(ids: Variant) -> void:
		ability_loadout = ids

	## The rig fields the clone's skill roll reads (`AbilityRules.fits_rig`). A
	## bare Node answers null for them, which is not a shape the real rig has.
	var weapon := "sword"
	var staff_active := false
	var shield_equipped := false

	func swings_two_handed() -> bool:
		return false

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
		print("BLOOD_FAIL  ", message)


func _initialize() -> void:
	call_deferred("execute")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func execute() -> void:
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	_check_ledger()
	_check_armory()
	_check_engine()
	_check_pool()
	_check_cave_rooms()
	_check_ability_index()
	_check_ladder()
	_check_speed_shelf()
	_check_armor_loot()
	_check_starter_ability()
	_check_clone_armoury()
	_check_clone_tiers()
	await _open_world()
	await _check_town()
	await _check_run()
	await _check_ability_in_hand()
	await _check_waves()
	_check_rewards()
	_check_kept_offers()
	_check_prop_models()
	_check_run_kit()
	await _check_portal()
	_check_shop_and_boss()
	_check_arsenal_in_hand()
	await _check_double_chest()
	await _check_bounds()
	_check_island_carry()
	_check_close()
	_finish()


# --- pure systems ----------------------------------------------------------

func _check_ledger() -> void:
	meta = root.get_node("Roguelite")
	meta.save_path = TEST_META
	meta.reset(false)
	body = null
	check(meta.keys == 0, "a new player carries no keys")
	check(meta.unlocked_ids().size() == 2, "two starters and nothing else")
	check(meta.is_unlocked("bow_long"), "the war bow is free")
	check(meta.is_unlocked("hatchet_makeshift"), "the hatchet is free")
	check(not meta.is_unlocked("bow_twig"), "the twig bow is the rack's to sell")
	check(not meta.is_unlocked("xbow_heavy"), "the heavy crossbow is locked")
	# The rack's own unlock: named, priced, no roll.
	var price: int = meta.unlock_cost_of("xbow_heavy")
	check(price == 4, "the heavy crossbow costs four keys")
	var refused: Dictionary = meta.unlock_weapon("xbow_heavy")
	check(not bool(refused.get("ok", false)), "an empty player cannot open the crossbow")
	meta.keys = 10
	var bought: Dictionary = meta.unlock_weapon("xbow_heavy")
	check(bool(bought.get("ok", false)), "the rack opens the named weapon")
	check(meta.keys == 10 - price, "and spends exactly its price")
	check(meta.unlocked_ids().size() == 3, "the pool grows by one")
	check(meta.is_unlocked("xbow_heavy"), "the opened weapon is in the pool")
	check(meta.needs_forge("xbow_heavy"), "and it owes the stash its one copy")
	check(not meta.needs_forge("bow_long"), "the starters owe no forge")
	var repeat: Dictionary = meta.unlock_weapon("xbow_heavy")
	check(not bool(repeat.get("ok", false)), "an open weapon cannot be bought twice")
	meta.save_meta()
	meta.load_meta()
	check(meta.is_unlocked("xbow_heavy"), "the ledger survives a reload")
	check(meta.keys == 10 - price, "and so do its keys")
	check(meta.best_level == 0, "a fresh record is level zero")
	meta.note_run(12, 4)
	check(meta.best_level == 12 and meta.runs == 1, "a run books its deepest level")


func _check_armory() -> void:
	check(Weapons.has("bow_long") and Weapons.has("hatchet_makeshift"), "both starters are in the registry")
	check(Weapons.slot_of("bow_long") == "ranged", "the starter bow is ranged")
	check(Weapons.slot_of("hatchet_makeshift") == "melee", "the hatchet is melee")
	var heavy: Dictionary = Weapons.get_weapon("xbow_heavy")
	check(float(heavy.get("proc", 0.0)) == 1.5, "the heavy crossbow carries a 1.5 proc coefficient")
	check(int(heavy.get("pierce", 0)) >= 1, "and a pierce budget")
	var auto: Dictionary = Weapons.get_weapon("xbow_auto")
	check(float(auto.get("proc", 0.0)) == 0.5, "the repeater carries a 0.5 proc coefficient")
	check(float(auto.get("spread", 0.0)) > 0.0, "and a spread")
	check(Weapons.all_ids().size() >= 12, "every catalog blade and bow is registered (%d)" % Weapons.all_ids().size())
	check(Weapons.has("sword_great") and Weapons.has("bow_long") and Weapons.has("staff_fire"),
		"the world's own weapons are in the pool")
	for id in Weapons.unlock_pool():
		check(not Weapons.is_default(id), "the unlock pool holds no starter (%s)" % id)
	check(Weapons.unlock_pool().has("bow_twig"),
		"the sapling the warband used to wake with is on the rack")
	check(Mods.all().size() >= 20, "the upgrade pool is broad enough to draft from (%d)" % Mods.all().size())
	for rarity in Mods.RARITIES:
		var found := false
		for row in Mods.all():
			if str(row.rarity) == rarity:
				found = true
				break
		check(found, "the %s tier has rows" % rarity)


## Every new archetype has to be liftable: the rig builds a crossbow from a bow's
## data, a spear from a sword's and a throwing knife from a dagger's, and a loadout
## that crashes a rig is a weapon nobody can use.
func _check_arsenal_in_hand() -> void:
	var merc: int = game.controller.merc_of(body)
	for weapon_id in ["xbow_auto", "javelin_iron", "dagger_throwing", "axe_makeshift",
			"hatchet_makeshift", "bow_twig"]:
		check(run._dress_weapon(body, merc, weapon_id), "the rig takes %s" % weapon_id)
	check(str(body.rig.weapon) != "none", "the rig is holding something")
	check(Weapons.resolve("javelin_iron").get("archetype") == "javelin",
		"the javelin keeps its archetype")


func _check_engine() -> void:
	var engine = ProcEngineScript.new(77, 3)
	engine.add_mod("split_shot", 2)
	engine.add_mod("rapid_fire", 5)
	engine.add_mod("heavy_caliber", 1)
	check(int(engine.stats().split_shots) == 2, "two Arc Split stacks are +2 arrows")
	check(absf(engine.attack_scale() - (1.0 + 0.18 * 5.0 - 0.1)) < 0.0001,
		"rates stack linearly (+18% x5, -10% heavy)")
	check(absf(engine.damage_multiplier() - (1.0 + 0.35)) < 0.0001, "damage stacks linearly")
	var plan: Dictionary = engine.on_weapon_fire(Weapons.get_weapon("bow_twig"),
		Vector3.ZERO, Vector3.FORWARD)
	check(int(plan.get("shots", 0)) >= 3, "a split shot fires the fan")
	# Broadhead's point has to leave the pool, not just sit in it: a flat row is
	# added to each shaft's number, and it is a point rather than a share.
	var flat = ProcEngineScript.new(78, 1)
	flat.add_mod("broadhead", 3)
	var flat_plan: Dictionary = flat.on_weapon_fire(Weapons.get_weapon("bow_twig"),
		Vector3.ZERO, Vector3.FORWARD)
	check(is_equal_approx(float(flat_plan.get("damage_add", 0.0)), 3.0),
		"three Broadhead stacks carry three points into the shot plan")
	check(is_equal_approx(flat.damage_multiplier(), 1.0),
		"and a flat point never turns into a share of the base")
	# Ten copies of a 15% proc must not reach the cap, let alone certainty.
	var chance = ProcEngineScript.new(11, 1)
	chance.add_mod("chain_lightning", 6)
	chance.stacks["chain_lightning"] = 100
	chance._dirty = true
	var rolled := 0
	for _index in 2000:
		if chance.chance_roll("chain_chance"):
			rolled += 1
	var rate := float(rolled) / 2000.0
	check(rate > 0.60 and rate < 0.72, "hyperbolic proc chance approaches 70%%, not 100%% (%.3f)" % rate)
	check(chance.stat("chain_chance") <= 0.70, "the chance curve is capped")
	var greed = ProcEngineScript.new(5, 1)
	greed.add_mod("glass_cannon", 5)
	check(greed.health_factor() >= ProcEngineScript.MIN_HEALTH_FACTOR,
		"five Glass Cannons cannot delete the pool")
	check(absf(greed.damage_multiplier() - 6.0) < 0.0001, "+100% damage five times is +500%")
	var crit = ProcEngineScript.new(9, 1)
	crit.add_mod("crit_sharpshooter", 6)
	check(absf(crit.stat("crit_chance") - 0.72) < 0.0001, "crit chance stacks linearly to the cap")
	var draft_rng := RandomNumberGenerator.new()
	draft_rng.seed = 31
	var offers: Array = Mods.roll_shelf(draft_rng, Mods.SOURCE_WELD, 1, 3)
	check(offers.size() == 3, "a shelf rolls three")
	var unique := {}
	for id in offers:
		unique[id] = true
		check(Mods.rarity_of(str(id)) != Mods.RARITY_GREED, "a weld shelf holds no greed")
	check(unique.size() == 3, "a shelf never repeats a row")
	# The keys phase 3 added, read back from the engine rather than from the data.
	var hand = ProcEngineScript.new(21, 1)
	hand.add_mod("ring_of_precision", 2)
	hand.add_mod("power_punch", 3)
	check(absf(hand.crit_multiplier() - (2.0 + 0.75 * 2.0 + 0.2 * 3.0)) < 0.0001,
		"crit multiplier stacks on top of the base 2.0x")
	var marked := Node3D.new()
	root.add_child(marked)
	var triggers = ProcEngineScript.new(22, 1)
	triggers.add_mod("splash_shot", 1)
	triggers.add_mod("crit_blast", 1)
	triggers.add_mod("money_shot", 1)
	triggers.add_mod("health_shot", 1)
	var kinds := {}
	for request in triggers.on_hit({"kind": "ranged", "target": marked,
			"position": Vector3.ZERO, "damage": 100.0, "crit": true, "proc": 1.0}):
		kinds[str((request as Dictionary).get("kind", ""))] = true
	check(kinds.has("splash"), "a splash row always spills the blow")
	check(kinds.has("currency"), "a gold-on-hit row pays for the blow")
	check(kinds.has("heal"), "a leech row heals on the blow")
	var hurt := triggers.on_player_damaged(50.0, 1)
	check(hurt.has("requests"), "an incoming blow answers with its own requests")
	marked.free()


## The pool's own census and the ceiling its table prices. Every row is data, so
## the only way to know the data is the design is to add all of it and read the
## numbers back: a duplicated stack, a mis-transcribed tier or a row that forgot
## its multiplier all show up here and nowhere else.
func _check_pool() -> void:
	var tiers := {}
	var families := {}
	var ready := 0
	var ids := {}
	for row in Mods.all():
		var id := str(row.id)
		ids[id] = true
		tiers[str(row.rarity)] = int(tiers.get(str(row.rarity), 0)) + 1
		families[str(row.family)] = int(families.get(str(row.family), 0)) + 1
		if Mods.ready_of(id):
			ready += 1
		check(not str(row.get("description", "")).is_empty(), "%s says what it does" % id)
		check(int(row.get("max_stacks", 0)) >= 1, "%s has a ceiling" % id)
	check(Mods.all().size() == 173,
		"the pool is 120 base + 42 ability + 11 speed rows (%d)" % Mods.all().size())
	check(ids.size() == Mods.all().size(), "every row has its own id")
	check(int(tiers.get(Mods.RARITY_COMMON, 0)) == 67,
		"67 commons (%d)" % int(tiers.get(Mods.RARITY_COMMON, 0)))
	check(int(tiers.get(Mods.RARITY_EPIC, 0)) == 55,
		"55 epics (%d)" % int(tiers.get(Mods.RARITY_EPIC, 0)))
	check(int(tiers.get(Mods.RARITY_LEGENDARY, 0)) == 37,
		"37 legendaries (%d)" % int(tiers.get(Mods.RARITY_LEGENDARY, 0)))
	check(int(tiers.get(Mods.RARITY_GREED, 0)) == 14,
		"14 greed rows (%d)" % int(tiers.get(Mods.RARITY_GREED, 0)))
	check(int(families.get("shot", 0)) == 30 and int(families.get("hand", 0)) == 11
		and int(families.get("ability", 0)) == 61 and int(families.get("perk", 0)) == 59
		and int(families.get("relic", 0)) == 12, "the five families keep their share")
	check(ready == 142, "142 live rows are the pool the surfaces offer (%d)" % ready)
	# Every row at its ceiling, read back as the design's own table.
	var ceiling = ProcEngineScript.new(4242, 1)
	for row in Mods.all():
		ceiling.add_mod(str(row.id), Mods.max_stacks(str(row.id)))
	check(absf(ceiling.stat("damage_mult") + ceiling.stat("damage_planted_mult")
		- 16.42) < 0.001, "the damage ceiling is +16.42")
	check(absf(ceiling.stat("max_hp_flat") - 280.0) < 0.001, "the flat HP ceiling is +280")
	check(absf(ceiling.stat("max_hp_mult") - 3.59) < 0.001, "the HP multiplier ceiling is +3.59")
	check(absf(ceiling.stat("crit_chance") - 0.32) < 0.001, "the crit chance ceiling is +0.32")
	check(absf(ceiling.stat("crit_mult_flat") - 2.70) < 0.001, "the crit multiplier ceiling is +2.70")
	check(absf(ceiling.stat("melee_damage_mult") - 4.50) < 0.001,
		"the hand ceiling is +4.50 after Heavy Robes' price")
	check(absf(ceiling.stat("throw_damage_mult") - 3.40) < 0.001, "the throw ceiling is +3.40")
	check(absf(ceiling.stat("attack_mult") - 1.20) < 0.001, "the rate ceiling is +1.20")
	check(absf(ceiling.stat("enemy_count_mult") - 2.25) < 0.001, "the wave ceiling is +2.25")
	check(absf(ceiling.stat("currency_mult") - 7.25) < 0.001, "the gold ceiling is +7.25")
	check(int(round(ceiling.stat("luck"))) == 6, "the luck ceiling is +6")
	check(absf(ceiling.stat("move_mult") - 1.41) < 0.001, "the speed ceiling is +1.41")


## The chambers the demons' island may be cut from: every one of them is a hall
## the party's own line fits in with its wall margin, and every area of the
## Hollow keeps at least one, so no part of the plan can stop being drawn.
func _check_cave_rooms() -> void:
	var rooms := CaveRoomScript.room_ids()
	check(rooms.size() >= CaveLayout.AREAS.size(),
		"the Hollow offers a chamber for every area (%d rooms)" % rooms.size())
	var line := CaveRoomScript.SPREAD * 2.0 + CaveRoomScript.WALL_MARGIN * 2.0
	for id in rooms:
		var index: int = CaveLayout.room_index(id)
		check(index >= 0, "the chamber %s is a room of the plan" % id)
		if index < 0:
			continue
		var room: Dictionary = CaveLayout.ROOMS[index]
		var rect: Rect2 = room["rect"]
		check(not bool(room.get("tunnel", false)), "no passage is offered as a chamber (%s)" % id)
		check(minf(rect.size.x, rect.size.y) >= line,
			"the chamber %s holds the party's line with its wall margin (%s)" % [id, rect.size])
	for area in CaveLayout.AREAS:
		var halls := 0
		for room in CaveLayout.ROOMS:
			if str(room["area"]) != str(area) or bool(room.get("tunnel", false)):
				continue
			if rooms.has(str(room["id"])):
				halls += 1
		check(halls > 0, "the Hollow keeps a fight chamber in %s" % str(area))


## The two catalogs that use the word "ability" are joined by one index, not
## confused: 36 active skills, 60 ability upgrades, 96 rows, unique ids.
func _check_ability_index() -> void:
	var active := AbilityIndex.active_entries()
	var upgrades := AbilityIndex.upgrade_entries()
	var all_entries := AbilityIndex.entries()
	check(active.size() == 36, "the active ability catalog holds 36 (%d)" % active.size())
	check(upgrades.size() == 60, "the ability upgrade set holds 60 (%d)" % upgrades.size())
	check(all_entries.size() == 96, "the merged index holds 96 (%d)" % all_entries.size())
	var ids := {}
	var dupes: Array[String] = []
	for entry in all_entries:
		var id := str(entry.get("id", ""))
		if ids.has(id):
			dupes.append(id)
		ids[id] = true
	check(dupes.is_empty(), "no id is both an ability and an upgrade (%s)" % str(dupes))
	var barrage := AbilityIndex.find("barrage")
	check(str(barrage.get("kind", "")) == AbilityIndex.KIND_ACTIVE
			and str(barrage.get("family", "")) == AbilityRules.TYPE_BOW,
		"Barrage is an active bow ability")
	var ball := AbilityIndex.find("fireball")
	check(str(ball.get("kind", "")) == AbilityIndex.KIND_ACTIVE
			and str(ball.get("family", "")) == AbilityRules.TYPE_STAFF,
		"Fireball is an active staff ability")
	var fleet := AbilityIndex.find("fleet_roll")
	check(str(fleet.get("kind", "")) == AbilityIndex.KIND_UPGRADE
			and str(fleet.get("verb", "")) == "roll"
			and not bool(fleet.get("ready", true)),
		"Fleet Roll is an unready roll upgrade, not an ability")
	var missing: Array[String] = []
	for row in Mods.all():
		var id := str(row.id)
		if Mods.family_of(id) != Mods.FAMILY_ABILITY:
			continue
		var tags := Mods.tags_of(id)
		if tags.is_empty():
			if Mods.verb_of(id).is_empty() or not Mods.VERB_ORDER.has(Mods.verb_of(id)):
				missing.append(id)
		elif not Mods.verb_of(id).is_empty():
			missing.append(id)
	check(missing.is_empty(), "every kit row names a known verb (%s)" % str(missing))
	var grouped := AbilityIndex.upgrades_by_verb()
	var grouped_count := 0
	for verb in Mods.VERB_ORDER:
		grouped_count += (grouped.get(verb, []) as Array).size()
	check(grouped_count == 19, "the verb groups hold every kit row (%d)" % grouped_count)
	check(Mods.family_label_of("fleet_roll") == "ABILITY  ·  ROLL",
		"the card label names the verb (%s)" % Mods.family_label_of("fleet_roll"))


## The ladder: what each surface may carry, what luck may move, and the one tier a
## surface guarantees.
func _check_ladder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# A weld on island one is commons, and a luck-stacked one on island nine is
	# still commons and epics: luck moves weight, never the shelf.
	var off_shelf := 0
	for _round in 120:
		for id in Mods.roll_shelf(rng, Mods.SOURCE_WELD, 1, 3, 0):
			if Mods.rarity_of(str(id)) != Mods.RARITY_COMMON:
				off_shelf += 1
		for id in Mods.roll_shelf(rng, Mods.SOURCE_WELD, 9, 3, 6):
			var tier := Mods.rarity_of(str(id))
			if tier == Mods.RARITY_LEGENDARY or tier == Mods.RARITY_GREED:
				off_shelf += 1
			if not Mods.ready_of(str(id)):
				off_shelf += 1
	check(off_shelf == 0, "a weld never carries a legendary, a greed row or a pending row")
	# The rule luck cannot bend, stated once for every unpromised source: the rows
	# it deals are always inside the tiers it lists for that island.
	var off_source := 0
	var drawn := 0
	for source in [Mods.SOURCE_WELD, Mods.SOURCE_STALL, Mods.SOURCE_HOARD,
			Mods.SOURCE_CACHE]:
		for island in [1, 3, 6]:
			var sells := Mods.source_tiers(source, island)
			for luck in [0, 8]:
				for id in Mods.roll_shelf(rng, source, island, 4, luck):
					drawn += 1
					if not sells.has(Mods.rarity_of(str(id))):
						off_source += 1
	check(off_source == 0,
		"a source never sells a tier it does not list (%d of %d)" % [off_source, drawn])
	# A boss's hoard pays the ceiling: one legendary, every time.
	var missing := 0
	for _round in 80:
		var found := false
		for id in Mods.hoard(rng, 2, 0, 6, []):
			if Mods.rarity_of(str(id)) == Mods.RARITY_LEGENDARY:
				found = true
		if not found:
			missing += 1
	check(missing == 0, "a boss's hoard always contains one legendary")
	# The roll itself: luck leans, and the chest's legendary stays the figure the
	# design names.
	var plain := Mods.tier_weights(Mods.RARITIES, 0, 5)
	var bent := Mods.tier_weights(Mods.RARITIES, 6, 5)
	check(absf(float(plain.get(Mods.RARITY_COMMON, 0.0))
		+ float(plain.get(Mods.RARITY_EPIC, 0.0))
		+ float(plain.get(Mods.RARITY_LEGENDARY, 0.0)) - 100.0) < 0.01,
		"the ladder's three tiers sum to a hundred")
	check(float(bent.get(Mods.RARITY_COMMON, 0.0))
		< float(plain.get(Mods.RARITY_COMMON, 0.0)),
		"six luck leans the roll away from common")
	check(float(bent.get(Mods.RARITY_LEGENDARY, 0.0)) <= Mods.LUCK_LEGENDARY_CAP + 0.001,
		"the legendary share has a ceiling")
	# A promise is a surface and a tier, and the chest lays out exactly that pair:
	# a band is one rarity, and every row on a surface's shelf is on it.
	check(Mods.promise(Mods.CHEST_ATTACK, Mods.RARITY_EPIC).tier == Mods.RARITY_EPIC,
		"a promise names the one tier it lays out")
	var off_surface := 0
	var short_shelves := 0
	var promises := 0
	for surface in Mods.CHEST_SURFACES:
		if Mods.surface_payout(surface) != Mods.PAYOUT_CARDS:
			continue
		for tier in [Mods.RARITY_COMMON, Mods.RARITY_EPIC, Mods.RARITY_LEGENDARY]:
			var rows := Mods.shelf(surface, tier)
			var offered := Mods.keeps_promise(Mods.promise(surface, tier))
			if offered:
				promises += 1
			if offered != (rows.size() >= Mods.SURFACE_MIN_ROWS):
				short_shelves += 1
			if rows.is_empty():
				continue
			for id in rows:
				if not Mods.in_chest_surface(str(id), surface):
					off_surface += 1
				if Mods.rarity_of(str(id)) != tier:
					off_surface += 1
				if not Mods.ready_of(str(id)):
					off_surface += 1
	check(off_surface == 0,
		"a surface's shelf only holds ready rows of its own surface and tier")
	check(short_shelves == 0,
		"and a promise is only offered where a whole hand fits (%d short)" % short_shelves)
	check(promises >= 20, "the surfaces lay out a shelf at most tiers (%d promises)" % promises)
	# A promise is absolute, not a roll. Island one's ladder row carries no
	# legendary at all, and a legendary chest promised there - an elite gate, a
	# lucky roll - once laid out nothing, because the tier the chest allowed was
	# re-weighted by the ladder; the luck ceiling then spent the promise's whole
	# mass on epics the promise never sold.
	var promise_rng := RandomNumberGenerator.new()
	promise_rng.seed = 2027
	var empty_promise := 0
	var off_promise := 0
	for _round in 120:
		var cards := Mods.deal(promise_rng,
			Mods.promise(Mods.CHEST_STAMINA, Mods.RARITY_LEGENDARY), 3)
		if cards.is_empty():
			empty_promise += 1
		for id in cards:
			if Mods.rarity_of(str(id)) != Mods.RARITY_LEGENDARY:
				off_promise += 1
	check(empty_promise == 0,
		"a legendary promise lays out cards where the ladder has no legendary (%d empty)"
			% empty_promise)
	check(off_promise == 0,
		"and every card it lays out is a legendary (%d off)" % off_promise)
	# A chest deals each body its own hand, so a promise is only made where every
	# body in the party can lay out a whole one: a party-wide row count is what
	# promised an Ability epic chest to a dagger body whose own epic shelf is bare.
	var short_hands := 0
	var hand_promises := 0
	for surface in Mods.CHEST_SURFACES:
		if Mods.surface_payout(surface) != Mods.PAYOUT_CARDS:
			continue
		for tier in [Mods.RARITY_COMMON, Mods.RARITY_EPIC, Mods.RARITY_LEGENDARY]:
			if not Mods.keeps_promise(Mods.promise(surface, tier), BODY_HANDS):
				continue
			hand_promises += 1
			for hand in BODY_HANDS:
				if Mods.deal(promise_rng, Mods.promise(surface, tier), 3,
						hand["taken"], hand["tags"]).size() < 3:
					short_hands += 1
	check(hand_promises >= 12,
		"a promise is still made at most tiers for a whole party (%d promises)" % hand_promises)
	check(short_hands == 0,
		"and every body a promise is dealt to can lay out a whole hand (%d short)"
			% short_hands)
	# A body spends a shelf as it takes the rows, so the promise is asked with the
	# rows it has left: a shelf it has taken to its ceiling is not promised again.
	var bow_tags := ["bow", "ranged", "any"]
	var kept_hand := {"tags": bow_tags, "taken": []}
	var stamina_legendary := Mods.promise(Mods.CHEST_STAMINA, Mods.RARITY_LEGENDARY)
	var spent_shelf := Mods.shelf(Mods.CHEST_STAMINA, Mods.RARITY_LEGENDARY, bow_tags)
	var spent_hand := {"tags": bow_tags, "taken": spent_shelf}
	check(spent_shelf.size() >= Mods.SURFACE_MIN_ROWS
		and Mods.keeps_promise(stamina_legendary, [kept_hand]),
		"a legendary stamina shelf a body can still fill is promised (%d rows)" % spent_shelf.size())
	check(not Mods.keeps_promise(stamina_legendary, [spent_hand]),
		"and the same shelf spent to its ceiling is not")
	# The tier a gate rolls is the ladder's, and luck leans it: the same six points
	# of Streamer Loot that bend a roll bend a promise.
	var luck_rng := RandomNumberGenerator.new()
	luck_rng.seed = 1234
	var plain_epic := 0
	var lucky_legendary := 0
	for _round in 400:
		var rolled := str(Mods.roll_promise(luck_rng, 5, 0).get("tier", ""))
		if rolled == Mods.RARITY_EPIC:
			plain_epic += 1
		if str(Mods.roll_promise(luck_rng, 5, 6).get("tier", "")) == Mods.RARITY_LEGENDARY:
			lucky_legendary += 1
	check(plain_epic > 0, "an unmodified island 5 gate still promises epics (%d)" % plain_epic)
	check(lucky_legendary > 0,
		"and six points of luck promise legendaries (%d)" % lucky_legendary)
	check(Mods.raise_tier(Mods.RARITY_COMMON) == Mods.RARITY_EPIC
		and Mods.raise_tier(Mods.RARITY_LEGENDARY) == Mods.RARITY_LEGENDARY,
		"the elite trial raises a promise one rung and no further")
	check(Mods.payout_count(Mods.RARITY_COMMON) == 1
		and Mods.payout_count(Mods.RARITY_LEGENDARY) == 3,
		"a key or gear chest pays one a tier, three on a legendary")
	# The set floor a legendary Gear chest welds on is a set this island never
	# rolls: floor_add is the whole of that promise.
	var floor_rng := RandomNumberGenerator.new()
	floor_rng.seed = 99
	var early := ArmorLoot.roll_set(floor_rng, 1, ArmorData.NONE, 0)
	var raised := ArmorLoot.roll_set(floor_rng, 1, ArmorData.NONE, 5)
	check(ArmorLoot.quality_rank(early) <= ArmorLoot.quality_rank(raised),
		"a Gear chest's floor raises the set (%d -> %d)" % [
			ArmorLoot.quality_rank(early), ArmorLoot.quality_rank(raised)])
	check(ArmorLoot.quality_rank(raised) >= 4,
		"and an island-one row cannot answer it (%d)" % ArmorLoot.quality_rank(raised))
	check(Mods.stall_price(Mods.RARITY_COMMON, 9) == 67
		and Mods.stall_price(Mods.RARITY_LEGENDARY, 9) == 137,
		"the stall prices a common at 67 and a legendary at 137 on level 9")


## The Speed chest: the body's own travel. It reads the three movement state
## machines' keys, so the shelf is checked against that list in both directions -
## no card on it writes a key the roll, the step or the slide never ask for, and
## every key they do ask for is answered by the engine the card is priced against.
func _check_speed_shelf() -> void:
	check(Mods.CARD_SURFACES.has(Mods.CHEST_SPEED),
		"speed owns a shelf of cards")
	check(Mods.surface_payout(Mods.CHEST_SPEED) == Mods.PAYOUT_CARDS,
		"and a speed chest pays cards")
	check(Mods.surface_label(Mods.CHEST_SPEED) == "SPEED",
		"the gate's label names it (%s)" % Mods.surface_label(Mods.CHEST_SPEED))
	var keys: Array = Mods.CHEST_KEYS.get(Mods.CHEST_SPEED, [])
	check(keys.size() >= 4, "the surface reads the body's travel (%d keys)" % keys.size())
	var engine = ProcEngineScript.new(4242, 1)
	var answers := engine.stats()
	var silent: Array[String] = []
	for key in keys:
		if not answers.has(str(key)):
			silent.append(str(key))
	check(silent.is_empty(), "the engine answers every movement key (%s)" % str(silent))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for tier in [Mods.RARITY_COMMON, Mods.RARITY_EPIC, Mods.RARITY_LEGENDARY]:
		var shelf: Array = Mods.shelf(Mods.CHEST_SPEED, tier)
		check(shelf.size() >= Mods.SURFACE_MIN_ROWS,
			"a speed chest lays out a whole hand at %s (%d)" % [tier, shelf.size()])
		var off := 0
		for id in shelf:
			for key in (Mods.get_mod(str(id)).get("stats", {}) as Dictionary):
				if not keys.has(str(key)):
					off += 1
		check(off == 0, "every %s speed row writes a movement key (%d off)" % [tier, off])
		var dealt: Array = Mods.deal(rng, Mods.promise(Mods.CHEST_SPEED, tier), 3)
		var wrong := 0
		for id in dealt:
			if Mods.rarity_of(str(id)) != tier:
				wrong += 1
		check(dealt.size() == 3 and wrong == 0,
			"and its cards are the promised tier (%d cards, %d off)" % [dealt.size(), wrong])
	# A movement row is a Speed card wherever its family sits: the two the pool
	# already shipped are the ones a player sees first, so they are not left off.
	check(Mods.in_chest_surface("speed_demon", Mods.CHEST_SPEED)
		and Mods.in_chest_surface("ring_of_swiftness", Mods.CHEST_SPEED),
		"Speed Demon and Ring Of Swiftness are speed cards too")
	var kit = RunPlayerScript.new()
	var plain := kit.movement()
	check(plain.is_empty(), "a body with no run asks for no tuning (%s)" % str(plain.size()))
	kit.free()


## The chest's armour: one piece at a random slot, a set the level's ladder can
## pay, and one to three welded modifiers on a chance that grows with the level.
## All pure rolls, so the shape is checked without a world standing.
func _check_armor_loot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var samples := 400
	var early_rank := 0.0
	var late_rank := 0.0
	var early_mods := 0
	var late_mods := 0
	var most := 0
	var naked := ArmorData.SET_IDS.find("naked")
	for _index in samples:
		for pair in [[5, 1], [95, 10]]:
			var level := int(pair[0])
			var piece: Dictionary = ArmorLoot.roll(rng, level, int(pair[1]))
			var slot := str(piece.get("slot", ""))
			check(ArmorData.SLOTS.has(slot), "a piece rolls a real slot (%s)" % slot)
			var set_index := int(piece.get("set", -1))
			check(set_index >= 0 and set_index < ArmorData.SET_IDS.size(),
				"a piece rolls a real set (%d)" % set_index)
			check(not (str(ArmorData.SET_IDS[set_index]) in ["naked", "cloth"]),
				"a chest never rolls a set that guards nothing (%s)"
				% str(ArmorData.SET_IDS[set_index]))
			check(int(piece.get("level", 0)) == level, "the piece carries its level")
			var mods := _piece_mods(piece)
			most = maxi(most, mods.size())
			for id in mods:
				check(Mods.has(str(id)) and Mods.ready_of(str(id)),
					"a welded modifier is a ready row (%s)" % str(id))
			if level == 5:
				early_rank += ArmorData.reduction_for(set_index, slot)
				early_mods += mods.size()
			else:
				late_rank += ArmorData.reduction_for(set_index, slot)
				late_mods += mods.size()
	check(most <= 3, "a piece welds at most three modifiers (%d)" % most)
	check(late_rank > early_rank,
		"level 95 pays better sets than level 5 (%.2f vs %.2f)" % [late_rank, early_rank])
	check(late_mods > early_mods,
		"and more welded modifiers (%d vs %d over %d pieces)" % [
			late_mods, early_mods, samples])
	check(early_mods > 0 and late_mods < samples * 3,
		"modifiers are a chance, not a guarantee")
	# The chance itself is the level's, and the counts stay inside the contract.
	check(ArmorLoot.mod_chance(1) < 0.10 and ArmorLoot.mod_chance(95) > 0.30,
		"the modifier chance grows with the level (%.2f -> %.2f)" % [
			ArmorLoot.mod_chance(1), ArmorLoot.mod_chance(95)])
	var count_rng := RandomNumberGenerator.new()
	count_rng.seed = 7
	var low := 0
	var high := 0
	var floor_count := 99
	for _index in 400:
		low = maxi(low, ArmorLoot.modifier_count(count_rng, 1))
		high = maxi(high, ArmorLoot.modifier_count(count_rng, 95))
		floor_count = mini(floor_count, ArmorLoot.modifier_count(count_rng, 40))
	check(low <= 2, "level-one armour never welds a third modifier (%d)" % low)
	check(high == 3, "high-level armour can weld three (%d)" % high)
	check(floor_count >= 1, "a modified piece always carries at least one")
	# A floor by quality: a plate body is handed plate on every island, and no
	# chest ever hands out bare skin.
	var floored := true
	for _index in 120:
		floored = floored and ArmorLoot.roll_set(rng, 6, 2) == 2
	check(floored, "a plate body is handed plate, never a downgrade")
	var bare := 0
	for _index in 300:
		var piece: Dictionary = ArmorLoot.roll(rng, 60, 6)
		if int(piece.get("set", -1)) == naked:
			bare += 1
	check(bare == 0, "and no chest hands out bare skin")


## A piece's welded modifier ids, whatever array type arrived from the wire.
func _piece_mods(piece: Dictionary) -> Array:
	var raw: Variant = piece.get("mods", [])
	return raw if raw is Array else []


## The starter ability: a staff skill priced off the staff's own base, scaled by
## the rig's spell channel and upgraded by the pool's damage rows.
func _check_starter_ability() -> void:
	var ball: Dictionary = AbilityRules.by_id("fireball")
	check(not ball.is_empty(), "the starter spell exists")
	check(str(AbilityRules.STARTER_BY_FAMILY[AbilityRules.TYPE_STAFF]) == "fireball",
		"the staff starter is the fireball")
	check(AbilityRules.STARTER_BY_FAMILY.size() == 8,
		"every family has a free starter (%d)" % AbilityRules.STARTER_BY_FAMILY.size())
	var starters := AbilityRules.starter_ids_for_gear(State.ITEMS["bow_short"], {})
	check(starters == ["snap_shot", "focus"],
		"a bow earns Snap Shot and the any-hand Focus (%s)" % str(starters))
	var great_starters := AbilityRules.starter_ids_for_gear(State.ITEMS["sword_great"], {})
	check(great_starters == ["heavy_swing", "focus"],
		"a greatsword earns the two-hand starter only (%s)" % str(great_starters))
	var board_starters := AbilityRules.starter_ids_for_gear(State.ITEMS["sword_short"],
		State.ITEMS["shield_kite"])
	check(board_starters == ["quick_cut", "shield_shove", "focus"],
		"sword and board earns both family starters (%s)" % str(board_starters))
	var effect: Dictionary = ball.get("effect", {})
	check(absf(float(effect.get("damage_scale", 0.0)) - 0.4) < 0.001,
		"it is priced at 40% of the staff base (50 x 0.4 = 20)")
	check(absf(float(ball.get("cooldown", 0.0)) - 10.0) < 0.001,
		"on a ten-second cooldown")
	check(absf(AbilityRules.damage_for(ball, null) - 20.0) < 0.001,
		"and 20 is what the cast reads without a rig behind it")
	# The family is the staff's: the spell fits a staff and nothing else.
	var staff_row: Dictionary = State.ITEMS["staff_fire"]
	var bow_row: Dictionary = State.ITEMS["bow_short"]
	check(AbilityRules.fits_gear(ball, staff_row, {}),
		"a staff performs the starter spell")
	check(not AbilityRules.fits_gear(ball, bow_row, {}),
		"a bow does not")
	# The spell channel scales it exactly as it scales every staff cast.
	var scaled := SpellRig.new()
	check(absf(AbilityRules.damage_for(ball, scaled) - 40.0) < 0.001,
		"a 2.0 spell channel doubles the cast (%.1f)" % AbilityRules.damage_for(ball, scaled))
	# Two dressings: a player body is marked for the starter spell, and a body
	# that was not given one carries nothing.
	var given: Dictionary = State.build_loadout("bow_twig", "", {}, {}, true)
	check(str(given.get("starter", "")) == AbilityRules.STARTER_GRANT,
		"a player body is marked for its family starters")
	var plain: Dictionary = State.build_loadout("bow_twig", "", {}, {})
	check(str(plain.get("starter", "")).is_empty(),
		"and a body that was not given one has none")
	# The pool upgrades it: the cast `damage_for` prices, through a run's own
	# planner - the same path a staff cast takes on a body in a run.
	var base := AbilityRules.damage_for(ball, null)
	var caster = RunPlayerScript.new()
	caster.bind(null, null, 1, -1, "bow_twig", "hatchet_makeshift")
	check(absf(float(caster.spell_plan(base).get("damage", 0.0)) - 20.0) < 0.001,
		"an unupgraded caster throws the spell's own 20")
	caster.engine.add_mod("heavy_caliber", 1)
	check(absf(float(caster.spell_plan(base).get("damage", 0.0)) - 27.0) < 0.001,
		"and a damage row upgrades the cast (%.1f)" % float(
			caster.spell_plan(base).get("damage", 0.0)))
	caster.free()


## The pit's armoury, block by block. A deeper block keeps every kit the blocks
## before it issued, so a wave in the deep pit is still an array of duellists - a
## dagger, a short bow, a great sword and a fire staff in the same four bodies -
## and never a wall of the newest piece. A retired kit would quietly change what
## the pit is, so the ladder is checked rather than trusted.
func _check_clone_armoury() -> void:
	var ladder: Array = CloneScript.DEPTH_KIT
	check(ladder.size() >= 3, "the pit's armoury is a ladder of rungs (%d)" % ladder.size())
	for rung in range(1, ladder.size()):
		var earlier: Dictionary = ladder[rung - 1]
		var later: Dictionary = ladder[rung]
		var earlier_main: Array = earlier.get("main", [])
		var later_main: Array = later.get("main", [])
		var lost: Array[String] = []
		for item in earlier_main:
			if not later_main.has(item):
				lost.append(str(item))
		check(lost.is_empty(), "block %d still issues every kit of block %d (%s)" % [
			rung + 1, rung, str(lost)])
		var earlier_sets: Array = earlier.get("armor", [])
		var later_sets: Array = later.get("armor", [])
		var lost_sets: Array[int] = []
		for set_id in earlier_sets:
			if not later_sets.has(set_id):
				lost_sets.append(int(set_id))
		check(lost_sets.is_empty(), "and every armour set of block %d (%s)" % [
			rung, str(lost_sets)])
		check(later_main.size() + later_sets.size()
				> earlier_main.size() + earlier_sets.size(),
			"block %d adds a piece the block before it did not have" % (rung + 1))
	# The table is the contract; the roll is what a wave actually gets. A body in
	# the last block still rolls the first block's kit, and its own.
	var first_main: Array = (ladder[0] as Dictionary).get("main", [])
	var last_main: Array = (ladder[ladder.size() - 1] as Dictionary).get("main", [])
	var saw_first := false
	var saw_last := false
	for serial in 24:
		var clone = CloneScript.new()
		var rig := KitRig.new()
		clone.rig = rig
		clone.clone_id = serial
		clone.depth = ladder.size()
		clone._roll_loadout()
		var item := str(clone.get("_main_item"))
		saw_first = saw_first or first_main.has(item)
		saw_last = saw_last or last_main.has(item)
		clone.free()
		rig.free()
	check(saw_first, "a deep-pit body still rolls a first-block kit")
	check(saw_last, "and its own block's newest piece is in the mix")


## The pit's brain is a ladder, and a ladder is only a ladder if every rung is
## above the one under it: a typo in `CloneAi` would otherwise ship a "Very Easy"
## body that swings faster than a "Fuck you" one, and nothing would say so.
func _check_clone_tiers() -> void:
	var tiers: Array = CloneAi.TIERS
	check(tiers.size() == 6, "the pit's brain has six tiers (%d)" % tiers.size())
	var names: Array[String] = CloneAi.labels()
	check(names == ["Very Easy", "Easy", "Medium", "Hard", "Very Hard", "Fuck you"],
		"named shallowest first (%s)" % str(names))
	check(CloneAi.name_of(CloneAi.DEFAULT_TIER) == "Hard",
		"the default is Hard, the body the pit shipped")
	check(CloneAi.current_tier == CloneAi.DEFAULT_TIER,
		"and a fresh session stands on it")
	# Every tier carries the same knobs: the brain reads them unguarded, so a hole
	# in the table is an error at the first swing rather than a slow clone.
	var keys := ["name", "swing_gap", "blow", "guard_answer", "reaction",
		"step_gap", "step_chance", "speed", "turn", "sight", "lead"]
	for tier in tiers:
		var missing: Array[String] = []
		for key in keys:
			if not (tier as Dictionary).has(key):
				missing.append(str(key))
		check(missing.is_empty(), "%s carries every knob (%s)" % [
			str((tier as Dictionary).get("name", "?")), str(missing)])
	# Which way each knob has to move as the ladder gets deeper.
	var rising := ["blow", "guard_answer", "step_chance", "speed", "turn", "sight", "lead"]
	var falling := ["swing_gap", "reaction", "step_gap"]
	for index in range(1, tiers.size()):
		var before: Dictionary = tiers[index - 1]
		var after: Dictionary = tiers[index]
		for key in rising:
			check(float(after[key]) >= float(before[key]),
				"%s never falls from %s to %s" % [key, str(before["name"]), str(after["name"])])
		for key in falling:
			check(float(after[key]) <= float(before[key]),
				"%s never rises from %s to %s" % [key, str(before["name"]), str(after["name"])])
	# Hard is the authored body: every multiplier is the one the brain was written
	# with, and its swing is the pit's own - a fifth slower than the flat 0.85 s it
	# shipped with, which is the owner's change and not a drift.
	var hard: Dictionary = CloneAi.profile(CloneAi.DEFAULT_TIER)
	for key in ["blow", "speed", "turn", "sight"]:
		check(absf(float(hard[key]) - 1.0) < 0.0001, "Hard leaves %s at 1.0" % key)
	check(float(hard["swing_gap"]) > 0.85, "Hard swings slower than the flat 0.85 s it shipped with")
	check(absf(float(hard["swing_gap"]) - 1.05) < 0.0001, "at the tier table's 1.05 s")
	# A skill is the tier's own: nothing below `Medium` performs one, and among the
	# tiers that do, the deeper the body stands the more willing it is to spend the
	# beat rather than the blade.
	for index in tiers.size():
		var row: Dictionary = tiers[index]
		check(bool(row.get("casts", false)) == (index >= 2),
			"%s casts: %s" % [str(row["name"]), str(bool(row.get("casts", false)))])
	for index in range(3, tiers.size()):
		check(float(tiers[index]["cast_gap"]) < float(tiers[index - 1]["cast_gap"]),
			"%s performs a beat sooner than %s" % [
				str((tiers[index] as Dictionary)["name"]),
				str((tiers[index - 1] as Dictionary)["name"])])
	check(float(tiers[1]["cast_gap"]) == 0.0 and float(tiers[2]["cast_gap"]) > 0.0,
		"the first casting tier names a wait and the shy tiers name none")
	# A tier asked for outside the ladder lands on the default rather than nowhere.
	check(CloneAi.clamp_tier(-4) == CloneAi.DEFAULT_TIER, "a tier under the ladder is Hard")
	check(CloneAi.clamp_tier(99) == CloneAi.DEFAULT_TIER, "so is one past it")
	check(CloneAi.set_tier(7) == CloneAi.DEFAULT_TIER, "and set_tier refuses it the same way")
	check(CloneAi.set_tier(5) == 5 and CloneAi.current_tier == 5, "a real tier takes")
	check(CloneAi.cycle_tier() == 0, "and the ladder wraps from the deepest to the shallowest")
	CloneAi.set_tier(CloneAi.DEFAULT_TIER)


# --- the world and the square ----------------------------------------------

func _open_world() -> void:
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	var flow = root.get_node("GameFlow")
	state.save_path = TEST_STATE
	state.reset(false)
	warband.save_path = TEST_WARBAND
	warband.reset_state()
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
	check(game.get("roguelite_hud") != null, "and a plate")
	if game.bodies.size() >= 1:
		body = game.bodies[0]


func _check_town() -> void:
	var saved_at: Vector3 = body.global_position
	for service in ["roguelite_rack", "roguelite_portal"]:
		var point: Vector3 = game.town.service_point(service)
		check(point != Vector3.ZERO, "the square has a %s" % service)
		check(game.town.service_at(point) == service, "and it resolves as its own service (%s)" % service)
		body.global_position = point
		check(game.town.prompt_line(body).begins_with("G - "), "and writes a prompt when stood at")
		check(point.distance_to(game.town.global_position) < 40.0,
			"the %s stands inside the wall" % service)
	body.global_position = saved_at
	check(game.town.service_point("roguelite_rack").distance_to(
		game.town.service_point("roguelite_portal")) > 3.0,
		"the two fixtures have room between them")
	# The totem is gone from the square, and so is the altar's annoint page.
	check(game.town.service_point("roguelite_totem") == Vector3.ZERO,
		"the square has no unlock totem")
	check(game.town.service_at(game.town.global_position + Vector3(-5.5, 0.0, -1.5)) != "roguelite_totem",
		"nothing answers where the totem stood")
	check(game.town.service_point("altar") == Vector3.ZERO, "the square has no annoint altar")
	# The kit is the run's: the square holds the body's own hands, and the pair
	# the portal will carry is read straight out of the inventory.
	var merc_in_square := int(game.controller.merc_of(body))
	var pair: Dictionary = run.hand_pair_for(merc_in_square)
	check(str(pair.get("ranged", "")) == "bow_long",
		"the starter body carries its war bow (%s)" % str(pair.get("ranged", "")))
	check(str(pair.get("melee", "")) == "hatchet_makeshift",
		"and its makeshift hatchet (%s)" % str(pair.get("melee", "")))
	check(str(body.rig.weapon) == "bow", "the square holds the kit's own bow")
	check(int(body.rig.bow_index) == 2, "and it is the longbow's own piece")
	# A piece in the inventory is the piece the run carries: wear the arming
	# sword on the page and the portal's pair names it, with no starter behind it.
	game.warband.stash.add("sword_arming", 1)
	game.paperdoll.open(merc_in_square)
	game.paperdoll.open_slot_menu("main")
	var arming_row: Button = null
	for child in game.paperdoll._menu_rows.get_children():
		if str(child.get_meta("item_id", "")) == "sword_arming":
			arming_row = child
	check(arming_row != null, "the main hand offers the stashed arming sword")
	if arming_row != null:
		arming_row.pressed.emit()
	check(str(game.warband.roster.equipped_of(merc_in_square).get("main", "")) == "sword_arming",
		"the page wears the stashed arming sword")
	check(str(body.rig.weapon) == "sword", "and the body in the square holds it")
	check(int(body.rig.sword_index) == 1, "as the arming sword's own piece")
	var worn_pair: Dictionary = run.hand_pair_for(merc_in_square)
	check(str(worn_pair.get("ranged", "")) == "sword_arming",
		"the pair the portal carries is the inventory's sword (%s)" % str(worn_pair.get("ranged", "")))
	check(str(worn_pair.get("melee", "")) == "hatchet_makeshift",
		"beside the hatchet still in the other hand")
	game.paperdoll.close()
	# The starter bow goes back so the rack below binds into the kit the rest of
	# the suite expects, and the test's sword leaves the pool.
	game.warband.equip_hand(merc_in_square, "ranged", "bow_long")
	game.warband.stash.remove("sword_arming", 1)
	# The press itself: the rack opens the board on the rack page, and a row the
	# ledger has opened wears the piece the stash holds.
	body.global_position = game.town.service_point("roguelite_rack")
	var service: String = game.town.interact_at(1, body.global_position)
	check(service == "roguelite_rack", "the rack's press resolves to the rack")
	check(game.town.forge_panel.is_open(), "and opens the run board")
	check(game.town.forge_panel.mode == "rack", "on the weapon rack")
	var heavy_name := Weapons.display_name("xbow_heavy")
	var heavy_row = null
	for child in game.town.forge_panel._body.get_children():
		if child is Button and str((child as Button).text).contains(heavy_name):
			heavy_row = child
			break
	check(heavy_row != null, "the rack lists the opened heavy crossbow")
	if heavy_row != null:
		(heavy_row as Button).pressed.emit()
	check(game.warband.stash.owns("xbow_heavy", game.warband.roster),
		"the opened piece is the warband's own")
	check(meta.forged.has("xbow_heavy") and not meta.needs_forge("xbow_heavy"),
		"and the forge is booked once")
	check(str(game.warband.roster.weapon_set_pair(merc_in_square, 0).get("main", ""))
		== "xbow_heavy", "and the rack put it in the body's ranged hand")
	var bound_pair: Dictionary = run.hand_pair_for(merc_in_square)
	check(str(bound_pair.get("ranged", "")) == "xbow_heavy",
		"the portal's pair reads it out of the kit")

	# The ledger is the ownership, not a spare on a shelf: a second body may carry
	# the piece the keys opened, and nothing is left lying in the shared stash.
	check(game.warband.stash.pooled_count("xbow_heavy") == 0,
		"the opened piece left the pool as the body took it up")
	for other_id in game.warband.roster.ids():
		if int(other_id) == merc_in_square:
			continue
		var other: Dictionary = game.warband.equip_hand(int(other_id), "ranged", "xbow_heavy")
		check(bool(other.get("ok", false)),
			"a second body is armed with an opened piece (%s)"
			% str(other.get("message", "")))
		check(str(game.warband.roster.weapon_set_pair(int(other_id), 0).get("main", ""))
			== "xbow_heavy", "and both bodies carry it at once")
		check(str(game.warband.roster.weapon_set_pair(merc_in_square, 0).get("main", ""))
			== "xbow_heavy", "the first body keeps the piece it was wearing")
		check(game.warband.stash.pooled_count("xbow_heavy") == 0,
			"and no spare is minted into the stash")
		break
	# The ability page is part of the same board: locked rows are the unlock and
	# the body's hands decide which opened rows can be equipped.
	game.town.forge_panel.open("abilities")
	check(game.town.forge_panel.mode == "abilities", "the book opens on the abilities page")
	var saw_barrage := false
	var saw_starter := false
	for child in game.town.forge_panel._body.get_children():
		var text := str(child.text) if child is Button or child is Label else ""
		if text.to_upper().contains("BARRAGE"):
			saw_barrage = true
		if text.to_upper().contains("FIREBALL") and text.to_upper().contains("STARTER"):
			saw_starter = true
	check(saw_barrage, "the book lists the locked Barrage")
	check(saw_starter, "and marks the starter as automatic")
	game.town.forge_panel.close_panel()
	check(not game.town.forge_panel.is_open(), "which closes again")
	body.global_position = saved_at


# --- one run ---------------------------------------------------------------

func _check_run() -> void:
	var start: Dictionary = run.start_run()
	check(bool(start.get("ok", false)), "the portal opens the run: %s" % str(start.get("message", "")))
	check(run.is_running(), "the director is live")
	# A level opens quiet: the first body waits out the lead, and the island holds
	# nothing until it lands.
	check(absf(float(run._spawn_clock) - DirectorScript.SPAWN_LEAD) < 0.01,
		"a level opens on its %.0f-second lead (%0.2f)" % [
			DirectorScript.SPAWN_LEAD, float(run._spawn_clock)])
	check(run.live_mobs().is_empty(), "with no body on the field yet")
	check(run._live_cap() == 10,
		"the opening block keeps ten bodies at once (%d)" % run._live_cap())
	check(run.level == 1 and run.wave == 1 and run.stage_index == 0, "the run starts at level 1, island 1")
	check(run.stage != null and is_instance_valid(run.stage), "an island was built")
	check(run.players.size() >= 1, "the body has a run runtime")
	var player = run.players.get(1)
	check(player != null and is_instance_valid(player), "the runtime is bound to peer 1")
	check(str(player.ranged_id) == "xbow_heavy", "the kit's ranged hand rides into the run")
	check(str(player.melee_id) == "hatchet_makeshift", "and the melee hand beside it")
	check(int(body.rig.bow_index) == 4, "the heavy crossbow is in the rig's hand")
	# The page reads the hand the body is holding, not the wardrobe's: the run's
	# pair is on it and the page's own TAB brings the other hand up with the rig.
	var page_merc := int(game.controller.merc_of(body))
	game.paperdoll.open(page_merc)
	check(str(game.paperdoll.slot_rows.get("main", {}).get("item_id", "")) == str(player.ranged_id),
		"the character page shows the hand the run put up")
	check(str(game.paperdoll.slot_rows.get("off", {}).get("item_id", "")) == str(player.melee_id),
		"and the other one TAB reaches")
	check(str(game.paperdoll.slot_rows.get("off", {}).get("item_id", ""))
		== str(game.warband.roster.weapon_set_pair(page_merc, 1).get("main", "")),
		"which is the piece the inventory holds for that hand")
	# The pair belongs to the run: a slot press cannot change a hand out from
	# under the island, and the page says so instead of offering the swap.
	var run_main_before := str(game.warband.roster.equipped_of(page_merc).get("main", ""))
	game.warband.stash.add("sword_short", 1)
	game.paperdoll._on_slot_pressed("main")
	check(str(game.warband.roster.equipped_of(page_merc).get("main", "")) == run_main_before,
		"a slot press cannot change the hand a run is carrying")
	check(not game.paperdoll._menu_box.visible,
		"and the page offers no alternatives for a hand the run owns")
	check(str(player.ranged_id) == "xbow_heavy", "and the run's pair is untouched")
	game.warband.stash.remove("sword_short", 1)
	# The island's own TAB is what brings the other hand up; the page reads it.
	game._swap_weapon_set()
	check(str(game.paperdoll.slot_rows.get("main", {}).get("item_id", "")) == str(player.melee_id),
		"the island's TAB brings the other hand up")
	check(str(body.rig.weapon) != "bow", "and the rig is holding it")
	game._swap_weapon_set()
	check(str(game.paperdoll.slot_rows.get("main", {}).get("item_id", "")) == str(player.ranged_id),
		"swapping back returns the ranged hand")
	game.paperdoll.close()
	check(body.bounds > 1000.0, "the island lifts the world's bound")
	check(body.global_position.y > 600.0, "the body stands on the island, not in the wood")
	check(absf(body.global_position.y - StageScript.LIFT) < 2.0, "the first island sits at the lift")



## A chest's armour is the run's, not the wardrobe's - but the character page is
## the screen a player checks after the pop. It must show the piece the chest
## actually handed out, the stage must wear it, and a click must never strip the
## roster slot it hides.
func _check_run_kit() -> void:
	var opener = run.players.get(1)
	check(opener != null and not opener.armor.is_empty(),
		"the Gear chest left the run pieces to show on the page (%d slots)" % (
			opener.armor.size() if opener != null else -1))
	if opener == null or opener.armor.is_empty():
		return
	var slot := str(opener.armor.keys()[0])
	var piece: Dictionary = opener.armor_piece(slot)
	var item_id := str(piece.get("item_id", ""))
	var set_index := int(piece.get("set", ArmorData.NONE))
	var merc := int(game.controller.merc_of(body))
	check(str(run.armor_for_merc(merc).get(slot, {}).get("item_id", "")) == item_id,
		"the director exposes the run's armour by mercenary")
	var roster_worn := str(game.warband.roster.equipped_of(merc).get(slot, ""))
	game.paperdoll.open(merc)
	var row: Dictionary = game.paperdoll.slot_rows.get(slot, {})
	check(str(row.get("item_id", "")) == item_id,
		"the character page shows the piece the run won (%s, %s)"
		% [str(row.get("item_id", "")), item_id])
	check(str((row.get("button") as Button).text).contains("RUN"),
		"and the row says it is the run's own")
	check(int(game.paperdoll.preview.rig.armor_piece(slot)) == set_index,
		"the stage ranger wears it too")
	game.paperdoll._on_slot_pressed(slot)
	check(str(game.warband.roster.equipped_of(merc).get(slot, "")) == roster_worn,
		"clicking the run's piece never strips the wardrobe")
	game.paperdoll.close()


## The starter spell is a staff skill: the crossbow run body does not carry it,
## and the same body dressed with a staff does. The cast cue lands half a second
## into the activation, so the check waits for the projectile rather than
## assuming it is there on the frame the key went down.
func _check_ability_in_hand() -> void:
	var grants: Array = AbilityRules.granted(body.rig)
	var on_bow := false
	for grant in grants:
		if str((grant as Dictionary).get("id", "")) == "fireball":
			on_bow = true
	check(not on_bow, "a crossbow run body does not carry the staff starter")
	# Dress the same body with a staff: the starter takes key 1.
	var armor: Dictionary = body.rig.armor_pieces.duplicate()
	var trinkets: Dictionary = body.rig.trinkets.duplicate()
	body.rig.apply_loadout(State.build_loadout("staff_fire", "", armor, trinkets, true))
	body.rig.set_ability_loadout(Array(body.rig.ability_loadout))
	body.ability._refresh_grants()
	grants = AbilityRules.granted(body.rig)
	check(not grants.is_empty() and str(grants[0].get("id", "")) == "fireball",
		"a staff run body starts with the fireball on its first key, got %s"
		% str(grants[0].get("id", "") if not grants.is_empty() else ""))
	body.stamina = maxf(float(body.stamina), 40.0)
	var cast: Dictionary = body.try_ability(0)
	check(bool(cast.get("ok", false)),
		"and the key casts it: %s" % str(cast.get("message", "")))
	# The spell is the world's, not the body's: `WarbandAbilities` owns the beat
	# that turns a cast cue into a projectile, and tracks what it spawned.
	var abilities = game.get("abilities")
	var ball = null
	for _frame in 90:
		await physics_frame
		for missile in abilities.missiles() if abilities != null else []:
			if str(missile.get("kind")) == "fireball":
				ball = missile
				break
		if ball != null:
			break
	check(ball != null, "the press puts a fireball in the air")
	if ball != null:
		var expected := 20.0 * float(body.rig.spell_scale())
		check(absf(float(ball.get("damage")) - expected) < 0.05,
			"and it flies with the spell's own 20 (%.2f, robe %.2f)" % [
				float(ball.get("damage")), float(body.rig.spell_scale())])
	check(float(cast.get("definition", {}).get("cooldown", 0.0)) == 10.0,
		"on its ten-second clock")
	# The crossbow goes back in the hand for the wave checks behind this one.
	body.rig.apply_loadout(State.build_loadout("xbow_heavy", "", armor, trinkets, true))
	body.rig.set_ability_loadout(Array(body.rig.ability_loadout))
	body.ability._refresh_grants()


func _check_waves() -> void:
	var gold_before: int = run.gold()
	var guard_before: int = game.guards.size()
	# The pacing rhythm: ten seconds before the opening body, nine before the next,
	# down to one, with the tail quicker than a straight countdown. These are the
	# waits the level is tuned to.
	var rhythm: Array[float] = [10.0, 9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.2, 2.2, 1.0]
	for step in rhythm.size():
		check(absf(run.spawn_interval(step) - rhythm[step]) < 0.001,
			"wait %d is %.1f s (%0.2f)" % [step + 1, rhythm[step], run.spawn_interval(step)])
	check(absf(run.spawn_interval(40) - DirectorScript.SPAWN_TAIL) < 0.001,
		"every body past the tenth comes at the one-second tail")
	var stormed := false
	for _round in 14:
		run.tick(2.5)
		if not run._mobs.is_empty():
			stormed = true
			break
	check(stormed, "the director queued and spawned the level's wave")
	var wave_total: int = run._queue.size() + run.live_mobs().size()
	print("ROGUELITE_WAVE level=%d bodies=%d" % [run.level, wave_total])
	check(wave_total >= 8, "a level is a crowd, not a skirmish (%d bodies)" % wave_total)
	check(game.guards.size() > guard_before, "the wave joined the world's hostile list")
	var first = run._mobs[0]
	check(first != null and is_instance_valid(first), "a mob exists")
	check(str(first.name).begins_with("Rogue"), "the mob carries a run name (%s)" % str(first.name))
	check(first.get("replica") != true, "a host wave is authoritative")
	# An island is an arena, not a town: its bodies name no safe ring, so a wave
	# engages a ranger standing in the middle of it instead of holding off from a
	# sanctuary that covers most of the ground.
	var ring: Variant = first.get("safe_center")
	check(ring is Vector3 and not (ring as Vector3).is_finite(),
		"a run mob is given no town safe ring")
	check(bool(first.hunting()), "and it is hunting the party the moment it lands")
	# `SquadDrive.retarget` calls `hunt`/`hunting` on every guard it owns, whatever
	# family the body is. A family without them raised an error on every pass and
	# never got the nudge, which is one of the ways a wave went inert.
	for family in ["res://scripts/devil_mob.gd", "res://scripts/ranger_clone.gd"]:
		var script = load(family)
		check(script != null and (script as GDScript).can_instantiate(),
			"%s loads" % family)
		var probe = (script as GDScript).new()
		check(probe.has_method("hunt") and probe.has_method("hunting"),
			"%s answers the squad's hunt verbs" % family)
		probe.free()
	# Immediate aggro, in motion: the wave is already running at the party inside
	# the first second, at a run and not at the walk of its idle orbit.
	var charging := false
	for _frame in 60:
		await physics_frame
		for mob in run.live_mobs():
			if Vector2(mob.velocity.x, mob.velocity.z).length() > 2.5:
				charging = true
				break
		if charging:
			break
	check(charging, "a wave runs at the party the moment it lands")
	# Stand the body in front of the mob it is fighting (a mob's back is blind by
	# design) and let the two of them settle it on the physics clock.
	body.global_position = first.global_position \
		- (first as Node3D).global_basis.z * 2.4 + Vector3.UP * 1.0
	first.hunt(body)
	var health_before_blow: float = float(body.health)
	for _frame in 300:
		await physics_frame
		if float(body.health) < health_before_blow:
			break
	check(float(body.health) < health_before_blow,
		"the wave lands a blow on a standing body (%d -> %d)" % [
			int(health_before_blow), int(body.health)])
	# A proc chain: give the player a blood arc and hit the mob once.
	var player = run.players.get(1)
	var before := int(player.engine.mod_list().size())
	player.take_mod("chain_lightning")
	check(player.engine.stacks_of("chain_lightning") == 1, "the upgrade stack took")
	check(player.engine.mod_list().size() == before + 1, "and is listed")
	# The trickle may have fielded only one body: the chain needs a second to arc
	# to, so the queue gives one up for the check.
	if run.live_mobs().size() < 2 and not run._queue.is_empty():
		run._spawn_next()
	var second = first
	for mob in run._mobs:
		if is_instance_valid(mob) and mob != first:
			second = mob
			break
	second.global_position = first.global_position + Vector3(1.2, 0.0, 0.0)
	var chain_before: float = float(second.get("health"))
	run.execute_effect(player, {"kind": "chain", "target": first,
		"position": first.global_position, "damage": 4096.0, "proc": 1.0,
		"targets": 4})
	check(float(second.get("health")) < chain_before or second.get("alive") == false,
		"a chain arc spends damage on the next body")
	check(player.kills >= 1, "and the kill is booked to the shooter")
	# Crescent Wave is the one trigger with no die: every swing pays it.
	player.take_mod("melee_shockwave")
	player.take_mod("split_shot")
	# Arrows are unlimited in this game: no quiver is read and no shaft is spent.
	var arrows_before: int = game.projectiles.size()
	var quiver_before: int = int(game.warband.arrows())
	var fired: bool = run.fire(body, body.global_position + Vector3.UP * 1.4,
		Vector3.FORWARD, 60.0, 1.0)
	check(fired, "the director owns a run body's shot")
	check(game.projectiles.size() >= arrows_before + 2, "Arc Split puts more than one shaft in the air")
	check(int(game.warband.arrows()) == quiver_before, "a shot spends no shaft from any quiver")
	var left: Vector3 = (game.projectiles[arrows_before].velocity as Vector3).normalized()
	var right: Vector3 = (game.projectiles[arrows_before + 1].velocity as Vector3).normalized()
	check(absf(left.dot(right) - 1.0) > 0.000001, "the split shafts carry a real spread")
	var newest = game.projectiles[game.projectiles.size() - 1]
	check(int(newest.get("pierce")) >= 1, "the heavy crossbow's pierce rides the arrow")
	check(absf(float(newest.get("proc_coeff")) - 1.5) < 0.001, "and its proc coefficient")
	var throw_before: int = game.projectiles.size()
	var charged_before: int = int(run._throw_charges.get(1, 0))
	var thrown_ok: bool = run.throw_weapon(body, body.global_position + Vector3.UP * 1.4,
		Vector3.FORWARD, 26.0, 1.0, "sword", 5)
	check(thrown_ok, "the director owns a run body's throw")
	check(game.projectiles.size() == throw_before + 1, "a throwing blade leaves the hand")
	check(int(run._throw_charges.get(1, 0)) == charged_before - 1, "and spends a charge")
	var waves_before := _count_procs("ProcWave")
	var swing: Dictionary = player.melee_swing(Vector3.FORWARD)
	check(swing.has("crit"), "a swing answers its crit")
	check(_count_procs("ProcWave") > waves_before, "a melee swing throws its crescent")
	# A field with nothing on it never waits for the clock: the next body comes
	# in at once. Kill what is standing and the queue gives up its next body on
	# the same tick, so a clean fight sets its own pace.
	var queued_before: int = run._queue.size()
	for mob in run._mobs.duplicate():
		if is_instance_valid(mob) and mob.get("alive") != false:
			mob.take_damage(4096.0, 1)
	run.tick(0.05)
	check(run.live_mobs().size() == 1,
		"an empty field pulls the next body in at once (%d)" % run.live_mobs().size())
	check(run._queue.size() < queued_before, "and the queue gives it up")
	# Clear the level's wave. The spawner feeds it one body a beat and an empty
	# field pulls the next at once, so the round cap covers the whole budget.
	for _round in 60:
		run.tick(2.5)
		for mob in run._mobs.duplicate():
			if is_instance_valid(mob) and mob.get("alive") != false:
				mob.take_damage(4096.0, 1)
		run.tick(0.2)
		if run.level_cleared:
			break
	check(run.level_cleared, "the level clears when its wave is dead")
	check(run.gold() > gold_before,
		"kills paid gold (%d -> %d)" % [gold_before, run.gold()])
	check(run.gold() == int(game.warband.gold()),
		"and the run's purse is the one purse the town spends")
	check(run.keys_earned == 0, "a non-boss level pays no unlock keys")
	# An elite advertises its rank over its head while it fights. The corpse is
	# not an elite, so the tag leaves on the frame the body dies instead of
	# floating over the five-minute hold. The forced body is the test's, not the
	# run's: the director's RNG is put back where it was so the rest of the walk
	# is the same game it would have been.
	var elite_rng: int = run._rng.state
	var elite_spec: Dictionary = run._pick_spec(true)
	run._spawn_spec(elite_spec, body.global_position + Vector3(0.0, 0.0, 4.0))
	run._rng.state = elite_rng
	var elite = run._mobs[run._mobs.size() - 1]
	var rank_tag = elite.get_node_or_null(CorpseHold.RANK_TAG)
	check(rank_tag is Label3D and str(rank_tag.text) == "ELITE",
		"a forced elite wears its rank over the body")
	elite.take_damage(1.0e7, 1)
	await process_frame
	check(not is_instance_valid(rank_tag), "and the corpse carries no ELITE tag")
	check(is_instance_valid(elite), "while the body still lies where it fell")


func _count_procs(name_prefix: String) -> int:
	var count := 0
	for child in game.get_children():
		if is_instance_valid(child) and str(child.name).begins_with(name_prefix):
			count += 1
	return count


func _prop_of(kind: String) -> Node3D:
	for prop in run._props:
		if is_instance_valid(prop) and Props.prop_kind(prop) == kind:
			return prop
	return null


## The recruiter's board on the island: three bodies for sale, one of each
## archetype, sold for the party's gold, sworn into the warband as a body that
## spends no deployment place and dies for good. Bought on the real world so the
## spawn, the runtime and the reap are all the game's own.
func _check_recruiter(actor) -> void:
	var desk := _prop_of("recruiter")
	if desk == null:
		check(false, "the market stands a recruiter (no desk)")
		return
	var serial := int(desk.get_meta("serial"))
	var board: Array = run.recruit_board.get(serial, [])
	check(board.size() == DirectorScript.SHOP_HIRES,
		"the recruiter sells three bodies (%d)" % board.size())
	if board.size() < 3:
		return
	var archetypes: Dictionary = {}
	for offer in board:
		check(str(offer.get("kind", "")) == "hire", "a row is a body for sale")
		check(int(offer.get("price", 0)) > 0,
			"%s costs gold (%d)" % [str(offer.get("name", "?")),
				int(offer.get("price", 0))])
		archetypes[str(offer.get("archetype", ""))] = true
	check(archetypes.size() == 3, "one of each archetype is on the board")
	# The desk's own prompt and its panel. The body is stood at the desk first: the
	# prompt is the prop inside reach, so a check that read it from wherever the
	# last check left the body was a check that passed or failed on the seed's own
	# island geometry rather than on the desk.
	var was_at: Vector3 = (actor as Node3D).global_position
	(actor as Node3D).global_position = desk.global_position + Vector3(0.0, 0.0, 1.6)
	check(run.prompt_line(actor).contains("RECRUITER"),
		"the desk names itself on the prompt (%s)" % run.prompt_line(actor))
	(actor as Node3D).global_position = was_at
	var hud = game.get("roguelite_hud")
	run._open_recruiter(serial, actor)
	if hud != null:
		check(hud._overlay.visible, "a press opens the recruiter's board")
		hud.close_all()
	# Buying a body is the hire verb's own contract and it is measured where it
	# lands (`tests/recruit_regression.gd`, on a market it opens itself): this test
	# owns the stop - the desk, the board and the panel - and stays out of the
	# party's composition, which the levels after it read.


## Every gate standing on the ground, in the order the director stood them.
func _gates() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for prop in run._props:
		if is_instance_valid(prop) and Props.prop_kind(prop) == "portal":
			out.append(prop)
	return out


## The one gate that leads to a biome.
func _gate(biome: String) -> Node3D:
	for gate in _gates():
		if str(Props.payload_of(gate).get("biome", "")) == biome:
			return gate
	return null


func _check_rewards() -> void:
	var chest := _prop_of("chest")
	check(chest != null, "a reward chest stands on the level")
	check(_prop_of("pedestal") == null,
		"and it is the level's only growth surface: no second prop deals a draft")
	check(_prop_of("greed") == null,
		"no Greed Totem stands on the level: the bargain is the boss's hoard and the stall")
	var gates := _gates()
	check(gates.size() == 3, "three gates stand on the cleared level (%d)" % gates.size())
	var biomes: Array[String] = []
	var factions: Array[String] = []
	for gate in gates:
		var payload := Props.payload_of(gate)
		biomes.append(str(payload.get("biome", "")))
		factions.append(str(payload.get("faction", "")))
	check(biomes == ["wilderness", "caves", "arena"],
		"one gate per faction, in order (%s)" % str(biomes))
	check(factions == ["watchers", "demons", "clones"],
		"and each names the faction behind it (%s)" % str(factions))
	var trials: Array[String] = []
	var surfaces: Array[String] = []
	var doubles := 0
	var unpaid := 0
	var wrongly_elite := 0
	var broken_hands := 0
	var off_contract := 0
	var promise_rng := RandomNumberGenerator.new()
	promise_rng.seed = 8181
	for gate in gates:
		var contract: Dictionary = Props.payload_of(gate).get("contract", {})
		check(not contract.is_empty(), "the gate carries its contract")
		trials.append(str(contract.get("trial", "")))
		var contract_chest: Dictionary = contract.get("chest", {})
		var surface := str(contract_chest.get("surface", ""))
		var tier := str(contract_chest.get("tier", ""))
		surfaces.append(surface)
		if not Mods.CHEST_SURFACES.has(surface):
			unpaid += 1
		elif not Mods.keeps_promise(Mods.promise(surface, tier)):
			unpaid += 1
		if str(Mods.surface_payout(surface)) == Mods.PAYOUT_CARDS \
				and not tier.is_empty():
			# The promise is dealt body by body: each body in the run gets a whole
			# hand of the promised surface and tier out of the rows it has left, so
			# a gate can only price a shelf the whole party can still use.
			for hand in run._party_hands():
				var dealt := Mods.deal(promise_rng, Mods.promise(surface, tier), 3,
					hand["taken"], hand["tags"])
				if dealt.size() < 3:
					broken_hands += 1
				for id in dealt:
					if Mods.rarity_of(str(id)) != tier:
						off_contract += 1
		if str(contract.get("trial", "")) == "elite" \
				and Mods.tier_rank(tier) < 1:
			wrongly_elite += 1
		if int(contract_chest.get("mult", 1)) > 1:
			doubles += 1
	trials.sort()
	check(trials == ["elite", "open", "swarm"],
		"one gate each of open, elite and swarm (%s)" % str(trials))
	check(unpaid == 0,
		"every gate promises a real surface at a tier it can pay (%s)" % str(surfaces))
	check(surfaces[0] != surfaces[1] and surfaces[1] != surfaces[2]
		and surfaces[0] != surfaces[2],
		"the three gates promise three different chests (%s)" % str(surfaces))
	check(wrongly_elite == 0, "and an elite trial never promises a common chest")
	check(broken_hands == 0,
		"every body a gate's chest is dealt to draws a whole hand (%d short)"
			% broken_hands)
	check(off_contract == 0,
		"and every card in it is the rarity the gate promised (%d off)" % off_contract)
	check(doubles == 1, "the swarm gate promises a 2X chest (%d)" % doubles)
	check(str(Props.payload_of(gates[0]).get("title", "")) == str(StageScript.biome("wilderness").name),
		"a gate's lintel carries its own biome")
	var first_label := str(Props.payload_of(gates[0]).get("label", ""))
	check(not first_label.is_empty(), "and the contract line under it")
	var first_surface := str((Props.payload_of(gates[0]).get("contract", {}) as Dictionary)
		.get("chest", {}).get("surface", ""))
	check(first_label.find(Mods.surface_label(first_surface)) >= 0,
		"the lintel names the chest it promises (%s)" % first_label)
	var first_trial := str(Props.payload_of(gates[0]).get("contract", {}).get("trial", ""))
	check(first_label.find(str(first_trial).to_upper()) >= 0,
		"and the trial that prices it (%s)" % first_label)
	check(chest.global_position.distance_to(gates[0].global_position) < 14.0,
		"the gates stand one walk from the chest (%.1f m)" % chest.global_position.distance_to(gates[0].global_position))
	var closest := INF
	for first in gates.size():
		for second in range(first + 1, gates.size()):
			closest = minf(closest, gates[first].global_position.distance_to(gates[second].global_position))
	check(closest > 3.2, "the three gates stand apart (%.1f m)" % closest)
	# Downed, then the chest's contract.
	body.health = 0.0
	body.enter_downed(1)
	check(bool(body.downed), "a lethal wave puts the body on the dirt")
	body.take_damage(50.0, 1)
	check(bool(body.alive), "a held body cannot be finished")
	run.tick(0.2)
	check(bool(body.alive), "and it does not bleed out while the run holds it")
	var chest_serial := int(chest.get_meta("serial"))
	var chest_owner := int(Props.payload_of(chest).get("owner", 0))
	check(chest_owner == 1, "the box is stood for the soul that owns it (%d)" % chest_owner)
	check(not str(Props.payload_of(chest).get("owner_name", "")).is_empty(),
		"and it wears that soul's name on its own plate (%s)"
			% str(Props.payload_of(chest).get("owner_name", "")))
	var draft_table: Dictionary = run.draft_offers.get(chest_serial, {})
	check(draft_table.size() == 1 and draft_table.has(1),
		"the box carries one row, for its owner (%s)" % str(draft_table.keys()))
	var short_rows := 0
	for peer in draft_table:
		if (draft_table[peer] as Array).size() != 3:
			short_rows += 1
	check(short_rows == 0, "and that row is three cards (%d short)" % short_rows)
	# A chest never stands with nothing in it, or with one card and no choice. A
	# promise the opener's own shelf cannot pay - a bare surface at that tier, a
	# shelf spent to its ceiling - is topped up at the promised rarity instead.
	var probe_body = run.players.get(1)
	var bare: Array = []
	if probe_body != null:
		bare = probe_body.chest_draft(Mods.CHEST_CRITICAL, Mods.RARITY_LEGENDARY, 3)
	check(not Mods.keeps_promise(Mods.promise(Mods.CHEST_CRITICAL,
		Mods.RARITY_LEGENDARY)),
		"a surface with no legendary row is never promised at legendary")
	check(bare.size() == 3,
		"yet a chest standing on it still deals three cards (%d)" % bare.size())
	var rescued: Dictionary = run._chest_offers(Mods.CHEST_CRITICAL, Mods.RARITY_LEGENDARY)
	var rescued_short := 0
	var rescued_off := 0
	for peer in rescued:
		if (rescued[peer] as Array).size() != 3:
			rescued_short += 1
		for id in rescued[peer] as Array:
			if Mods.rarity_of(str(id)) != Mods.RARITY_LEGENDARY:
				rescued_off += 1
	check(rescued.size() == run.players.size() and rescued_short == 0,
		"the chest stands with a whole hand for every body (%d rows)" % rescued.size())
	check(rescued_off == 0,
		"at the rarity it promised (%d off)" % rescued_off)
	# The chest is the level's one source: everything it takes is taken here.
	var player = run.players.get(1)
	run._open_chest(chest_serial, body)
	check(not run._opened.has(chest_serial), "the chest waits for its pick")
	var chest_offers: Array = run._offers_for(chest_serial, 1)
	check(chest_offers.size() == 3, "the chest offers three promised rows")
	var chest_payload := Props.payload_of(chest)
	var promised := str(chest_payload.get("surface", ""))
	var promised_tier := str(chest_payload.get("tier", ""))
	# The first chest on an island is an ABILITY chest: level one's promise is a
	# skill, not the teaching card chest it used to be.
	check(promised == Mods.CHEST_ABILITY and promised_tier == Mods.RARITY_COMMON,
		"level one opens on the island's first ABILITY chest, commons (%s/%s)"
			% [promised, promised_tier])
	check(str(chest_payload.get("payout", "")) == Mods.PAYOUT_SKILLS,
		"an ability surface pays a skill")
	check(str(chest_payload.get("offer_kind", "")) == "skill",
		"and its draft is drawn as a skill")
	var worn_main: Dictionary = State.ITEMS.get(str(player.ranged_id), {})
	var worn_off: Dictionary = State.ITEMS.get(str(player.melee_id), {})
	var fitting := 0
	for id in chest_offers:
		var definition: Dictionary = AbilityRules.by_id(str(id))
		check(not definition.is_empty(),
			"an ability chest only offers skills (%s)" % str(id))
		check(not meta.is_ability_unlocked(str(id)),
			"and only skills this player has not opened (%s)" % str(id))
		if AbilityRules.fits_gear(definition, worn_main, worn_off):
			fitting += 1
	check(fitting >= 1,
		"at least one offer fits the pair the body is wearing (%d of %d)"
			% [fitting, chest_offers.size()])
	# A skill pick: the unlock is the player's, the bar is the body's.
	var pick := str(chest_offers[0])
	check(run.choose_draft(1, chest_serial, 0).get("ok", false),
		"the chest's first skill is taken")
	check(meta.is_ability_unlocked(pick),
		"the skill is the player's from the pick onward (%s)" % pick)
	var bar: Array = game.warband.roster.hotbar_order_of(int(player.merc_id))
	var fits_pick: bool = AbilityRules.fits_gear(AbilityRules.by_id(pick),
		worn_main, worn_off)
	check(bar.has(pick) == fits_pick,
		"and it rides the bar exactly when the hands fit it (%s, fits=%s)"
			% [pick, str(fits_pick)])
	check(run._opened.has(chest_serial), "the chest opens on its pick")
	check(not bool(body.downed) and float(body.health) > 0.0,
		"the chest wakes a downed body at half the pool")
	check(run._opened.has("chest"), "the chest unseals the portal")
	# An ability chest pays no armour: a piece is the Gear chest's surface, and
	# its tier is the set floor. A Key chest pays keys and no card at all.
	var opener = run.players.get(1)
	check(opener != null and opener.armor.is_empty(),
		"an ability chest hands out no armour (%d slots)" % (
			opener.armor.size() if opener != null else -1))
	var gear_payload := {"surface": Mods.CHEST_GEAR, "tier": Mods.RARITY_LEGENDARY,
		"payout": Mods.PAYOUT_GEAR, "style": "chest", "mult": 1}
	var gear_chest = run._spawn_prop("chest", run.stage.rim_point(2, 6), gear_payload)
	check(gear_chest != null, "a Gear chest stands where the director stands it")
	var gear_serial := int(gear_chest.get_meta("serial"))
	run._open_chest(gear_serial, body)
	check(not opener.armor.is_empty(),
		"the Gear chest hands its opener armour (%d slots)" % opener.armor.size())
	var floor_rank := ArmorLoot.quality_rank(ArmorData.NONE) + Mods.tier_rank(
		Mods.RARITY_LEGENDARY)
	var low_pieces := 0
	var off_rig := 0
	for slot in opener.armor:
		var won: Dictionary = opener.armor_piece(str(slot))
		if ArmorLoot.quality_rank(int(won.get("set", ArmorData.NONE))) < floor_rank:
			low_pieces += 1
		if int(body.rig.armor_piece(str(slot))) != int(won.get("set", -1)):
			off_rig += 1
		for id in _piece_mods(won):
			check(opener.engine.stacks_of(str(id)) >= 1,
				"a welded modifier is on the body (%s)" % str(id))
	check(low_pieces == 0, "every piece clears the set floor its tier welds on")
	check(off_rig == 0, "and the rig wears what the run's own table won")
	check(not run._props_by_serial.has(gear_serial),
		"the Gear chest is spent on its open")
	var gear_slot := str(opener.armor.keys()[0])
	var gear_piece: Dictionary = opener.armor_piece(gear_slot)
	print("ROGUELITE_ARMOUR %s" % ArmorLoot.status_line(gear_piece))
	check(game.hud.status_line().find("GEAR CHEST") >= 0,
		"the Gear chest's line names its own payout: %s" % game.hud.status_line())
	# A second press cannot milk a second set out of the same chest, and a hand
	# flip re-dresses from the roster without dropping what the run won.
	var slots_after: int = int(opener.armor.size())
	run._open_chest(gear_serial, body)
	check(opener.armor.size() == slots_after,
		"a spent chest cannot be milked for a second set")
	run._apply_hands(opener, "melee")
	check(int(body.rig.armor_piece(gear_slot)) == int(gear_piece.get("set", -1)),
		"a hand swap keeps the Gear chest's piece on the body")
	run._apply_hands(opener, "ranged")
	# The Key chest: the one surface that pays the meta currency.
	var keys_before: int = int(run.keys_earned)
	var key_payload := {"surface": Mods.CHEST_KEY, "tier": Mods.RARITY_EPIC,
		"payout": Mods.PAYOUT_KEYS, "style": "chest", "mult": 1}
	var key_chest = run._spawn_prop("chest", run.stage.rim_point(3, 6), key_payload)
	var key_serial := int(key_chest.get_meta("serial"))
	run._open_chest(key_serial, body)
	check(run.keys_earned == keys_before + Mods.payout_count(Mods.RARITY_EPIC),
		"an epic Key chest banks its keys (%d -> %d)" % [keys_before, run.keys_earned])
	check(not run.draft_offers.has(key_serial), "and lays out no card")
	check(not run._props_by_serial.has(key_serial), "the Key chest is spent")
	# The wear path itself, without a body behind it: a welded modifier lands on
	# the engine, a row the engine refuses is dropped from the piece rather than
	# left lying about what the piece carries, and a clean piece keeps its shape.
	var probe = RunPlayerScript.new()
	probe.engine = ProcEngineScript.new(4242, 9)
	var probe_piece := {"slot": "head", "set": 2, "item_id": "armor_plate_head",
		"name": "Warden Sallet", "level": 40,
		"mods": ["rapid_fire", "not_a_real_mod"]}
	var kept: Dictionary = probe.wear_armor(probe_piece)
	check(probe.engine.stacks_of("rapid_fire") == 1,
		"a welded modifier lands on the engine")
	check(_piece_mods(kept) == ["rapid_fire"],
		"and a row the engine refuses is not left on the piece")
	check(str(kept.get("slot", "")) == "head" and int(kept.get("set", -1)) == 2,
		"the clean piece keeps its slot and set")
	probe.free()
	# The shop's counter sells for the same gold the town spends.
	var wares := [{"id": "rapid_fire", "name": "Berserk Rate", "price": 10,
		"rarity": "common"}]
	var shop: Node3D = run._spawn_prop("shop", run.stage.rim_point(1, 6), {"wares": wares})
	run.shop_wares[int(shop.get_meta("serial"))] = wares
	var purse_before: int = run.gold()
	var bought: Dictionary = run.buy(int(shop.get_meta("serial")), 0, 1)
	check(bool(bought.get("ok", false)), "the stall sells a ware")
	check(run.gold() == purse_before - 10, "and takes its price in gold")
	check(int(game.warband.gold()) == run.gold(), "from the shared purse")


## The authored model stands on the prop's own origin: every plaque, the chest's
## lamp and the gate's promise sheet hang from that origin. The GLB lays its
## variants out along +x for the bake sheet, so a variant left where the sheet
## put it stands beside its own name.
func _check_prop_models() -> void:
	for style in ["chest", "mini", "elite"]:
		var visual: Node3D = ChestVisual.new()
		visual.setup(style, Color.WHITE)
		var box := _model_bounds(visual)
		check(box.size.x > 0.0 and absf(box.get_center().x) < 0.02,
			"the %s chest is centred on the prop its plate hangs from (%.2f m off)"
				% [style, box.get_center().x])
		visual.free()
	for biome in ["wilderness", "caves", "arena"]:
		var visual: Node3D = GateVisual.new()
		visual.setup(biome, Color.WHITE)
		var box := _model_bounds(visual)
		check(box.size.x > 0.0 and absf(box.get_center().x) < 0.02,
			"the %s gate is centred on the prop its sheet and plates hang from (%.2f m off)"
				% [biome, box.get_center().x])
		visual.free()


## The authored model's bounds in the prop's own space. The variant node is the
## prop's first child; the plates, lamp and sheet that follow are the prop's own.
func _model_bounds(prop: Node3D) -> AABB:
	var model := prop.get_child(0) as Node3D
	if model == null:
		return AABB()
	var meshes: Array = []
	if model is MeshInstance3D:
		meshes.append(model)
	meshes.append_array(model.find_children("*", "MeshInstance3D", true, false))
	var total := AABB()
	var first := true
	for mesh_node in meshes:
		var placed: AABB = _relative(mesh_node, prop) * (mesh_node as MeshInstance3D).get_aabb()
		total = placed if first else total.merge(placed)
		first = false
	return total


func _relative(node: Node, ancestor: Node) -> Transform3D:
	var out := Transform3D.IDENTITY
	while node != null and node != ancestor:
		out = (node as Node3D).transform * out
		node = node.get_parent()
	return out


func _check_portal() -> void:
	# The dead of level one lie on its ground until another level begins: a gate
	# press is a new level's ground, and no corpse should walk through it.
	var old_corpses: Array = run._corpses.duplicate()
	check(not old_corpses.is_empty(), "the cleared level left its dead on the island")
	# The gate taken is the biome fought: the party walks into the demons' gate
	# and level two is the caves.
	check(run.biome_id == "wilderness", "the run opened in the wood (%s)" % run.biome_id)
	var gate := _gate("caves")
	check(gate != null, "the demons' gate is standing")
	check(int(Props.payload_of(gate).get("next_level", -1)) == run.level + 1,
		"each gate names the level behind it")
	var before_level: int = run.level
	var before_island: int = run.stage_index
	var stage_before = run.stage
	# The press a player actually makes: stand at the gate and use it.
	body.global_position = gate.global_position + Vector3(0.0, 0.0, 2.0)
	check(run.nearest_prop(body.global_position) == gate, "the gate is the prop in reach")
	check(run.interact(body), "the gate takes the press")
	check(run.level == before_level + 1, "the gate takes the next level")
	check(run.stage_index == before_island, "and the same depth block keeps its number")
	check(run.biome_id == "caves", "the gate taken is the biome fought (%s)" % run.biome_id)
	check(str(run.state().get("faction", "")) == "demons",
		"and the faction behind it owns the wave (%s)" % str(run.state().get("faction", "")))
	check(run.stage != null and is_instance_valid(run.stage) and run.stage != stage_before,
		"the new biome stands on new ground")
	check(run.level_cleared == false and run.wave_active, "the next level opens on its wave")
	check(body.global_position.y > 600.0, "the party stands on the island")
	# The Hollow Beneath is a chamber of the real cave, not the old turf ring:
	# the stage names the room, the party lands inside its walls, and the only
	# way on is the run's own gates.
	check(run.stage.is_chamber(), "the demons' island is a Hollow chamber")
	check(run.stage.room_label().begins_with("THE "),
		"and it names the room it was cut from (%s)" % run.stage.room_label())
	check(run.stage.contains(body.global_position), "the party lands inside its walls")
	var chamber_middle: Vector3 = run.stage.middle()
	check(run.stage.contains(chamber_middle), "the chamber's middle is inside the fight")
	check(not run.stage.contains(chamber_middle + Vector3(200.0, 0.0, 0.0)),
		"and the rock past its walls is not")
	check(absf(run.stage.floor_point(Vector2.ZERO).y - chamber_middle.y) < 4.0,
		"the middle stands on the room's own floor")
	var chamber: Node = run.stage.get_node_or_null("Dressing/CaveChamber")
	check(chamber != null, "the chamber is cut from the Hollow's plan")
	var skin: MeshInstance3D = null
	if chamber != null:
		skin = chamber.get_node_or_null("Room/Skin") as MeshInstance3D
	check(skin != null and skin.mesh != null and skin.mesh.get_surface_count() > 0,
		"and walled in the Hollow's own rock")
	check(chamber != null and chamber.get_node_or_null("Room/Formations") != null,
		"with the dripstone the plan grows in it")
	check(run.stage.get_node_or_null("ChamberWall") == null,
		"there is no turf-ring shell under the chamber")
	check(run.stage.get_node_or_null("IslandFloor") == null,
		"and no flat island floor")
	for slot in 3:
		var gate_at: Vector3 = run.stage.gate_point(slot, 0.4189, 9.5)
		check(run.stage.contains(gate_at),
			"gate %d stands inside the chamber" % slot)
	check(run.stage.air() != null, "the chamber carries its own air")
	await process_frame
	var lying := 0
	for corpse in old_corpses:
		if is_instance_valid(corpse):
			lying += 1
	check(lying == 0, "a new level clears the old corpses (%d still lying)" % lying)
	check(run._corpses.is_empty(), "and the director forgets them")


func _check_shop_and_boss() -> void:
	# Level six is the mid-block market: five combat levels first, then no wave,
	# a stall and a reward chest, no rack, and gates back to combat rather than a boss.
	# The market begins on the island the portal reached, with no ground rebuilt,
	# so a body of the level before it is the same-island case: it still goes.
	# The forced body is the test's, so the run's RNG is left where it was.
	var market_rng: int = run._rng.state
	run._spawn_spec(run._pick_spec(false), body.global_position + Vector3(0.0, 0.0, 4.0))
	run._rng.state = market_rng
	var market_corpse = run._mobs[run._mobs.size() - 1]
	market_corpse.take_damage(1.0e7, 1)
	run.wave = 6
	run.level = 5
	run.level_cleared = true
	run._begin_level()
	# The free is queued for the end of the frame, so the corpse's own flag is
	# the evidence here: this function runs on the caller's frame.
	check(not is_instance_valid(market_corpse)
			or (market_corpse as Node).is_queued_for_deletion(),
		"a level begun on the same island clears the old corpse")
	check(run.market_level and run.shop_level and run.level == 6,
		"level 6 is the market level")
	check(not run.wave_active, "the market sends no wave")
	check(_prop_of("shop") != null, "the market stall stands")
	check(_prop_of("recruiter") != null, "and so does the recruiter's desk")
	await _check_recruiter(body)
	check(_prop_of("rack") == null, "the market has no weapon rack")
	var market_chest := _prop_of("chest")
	check(market_chest != null, "the market stands a reward chest")
	var market_payload := Props.payload_of(market_chest)
	var market_surface := str(market_payload.get("surface", ""))
	check(Mods.CHEST_SURFACES.has(market_surface),
		"and the stop rolls a real surface (%s)" % market_surface)
	check([Mods.RARITY_COMMON, Mods.RARITY_EPIC, Mods.RARITY_LEGENDARY].has(
		str(market_payload.get("tier", ""))),
		"at one of the three ladder tiers (%s)" % str(market_payload.get("tier", "")))
	check(not str(market_payload.get("label", "")).is_empty(),
		"and says so on its lid (%s)" % str(market_payload.get("label", "")))
	check(str(run.state().get("kind", "")) == "market"
		and bool(run.state().get("market_level", false)),
		"the state names the market")
	var market_gates := _gates()
	check(market_gates.size() == 3, "the market stands three gates (%d)" % market_gates.size())
	var all_combat := true
	for gate in market_gates:
		if str(Props.payload_of(gate).get("kind", "")) != "combat":
			all_combat = false
	check(all_combat, "the market's gates lead back to combat")
	# The stop's chest is a reward chest like any other: a card surface lays out a
	# card a body and the allies have already taken theirs; a key or a gear chest
	# pays on the open. Either way it seals no gate - a market's were never barred.
	var market_serial := int(market_chest.get_meta("serial"))
	var market_player = run.players.get(1)
	var market_payout := str(market_payload.get("payout", ""))
	if market_payout == Mods.PAYOUT_CARDS:
		var market_table: Dictionary = run.draft_offers.get(market_serial, {})
		check(market_table.size() == 1 and market_table.has(1),
			"the market's box carries one row, for the soul it stands for (%s)" % str(
				market_table.keys()))
		var ally_rows := 0
		for peer in run.ai_peers():
			if market_table.has(int(peer)):
				ally_rows += 1
		check(ally_rows == 0,
			"and no ally's row sits in a player's box (%d)" % ally_rows)
		run._open_chest(market_serial, body)
		var market_offers: Array = run._offers_for(market_serial, 1)
		check(market_offers.size() == 3,
			"the market's chest lays out three cards a body")
		var market_stacks: int = market_player.engine.total_stacks()
		check(run.choose_draft(1, market_serial, 0).get("ok", false),
			"the market's first card is taken")
		check(market_player.engine.total_stacks() == market_stacks + 1,
			"and it lands on the body")
	else:
		var keys_before: int = int(run.keys_earned)
		run._open_chest(market_serial, body)
		check(run.keys_earned >= keys_before,
			"a stop's key chest pays on the open")
		check(not run.draft_offers.has(market_serial),
			"and holds no card to choose")
	check(not run._opened.has("chest"),
		"a stop's chest seals no gate: the market's were never barred")
	check(not run._props_by_serial.has(market_serial), "and the market's chest is spent")
	run._take_portal(int(market_gates[0].get_meta("serial")), body)
	check(run.level == 7 and run.wave_active and not run.shop_level
		and not run.market_level,
		"the market's gate opens level 7's wave")
	# Level nine is the full shop: no wave, a stall, the rack and the gates to
	# the boss.
	run.wave = 9
	run.level = 8
	run.level_cleared = true
	run._begin_level()
	check(run.shop_level and not run.market_level and run.level == 9,
		"level 9 is the full shop level")
	check(not run.wave_active, "the shop level sends no wave")
	check(_prop_of("shop") != null, "the shop stall stands")
	check(_prop_of("rack") != null, "the weapon rack stands")
	check(_prop_of("chest") != null,
		"the shop level's own reward chest stands")
	var gates := _gates()
	check(gates.size() == 3, "the shop level stands all three gates (%d)" % gates.size())
	var all_boss := true
	for gate in gates:
		if str(Props.payload_of(gate).get("kind", "")) != "boss":
			all_boss = false
	check(all_boss, "and every one of them leads to the boss")
	# The rack opens mid-run, and a press wears the piece the stash can hold: the
	# run's hand is then the inventory's piece, not a ledger's id.
	game.town.forge_panel.open("rack")
	check(game.town.forge_panel.mode == "rack", "the shop rack opens the board")
	var shop_player = run.players.get(1)
	var axe_name := Weapons.display_name("axe_makeshift")
	var axe_row = null
	for child in game.town.forge_panel._body.get_children():
		if child is Button and str((child as Button).text).contains(axe_name):
			axe_row = child
			break
	check(axe_row != null, "the shop rack lists the locked axe")
	var keys_before_axe := int(meta.keys)
	if axe_row != null:
		(axe_row as Button).pressed.emit()
	check(int(meta.keys) == keys_before_axe - 2, "the press spends the axe's two keys")
	check(game.warband.stash.owns("axe_makeshift", game.warband.roster),
		"the opened axe is in the inventory")
	check(not meta.needs_forge("axe_makeshift"), "and its forge is booked once")
	check(shop_player != null and str(shop_player.melee_id) == "axe_makeshift",
		"and the run's melee hand is the piece the inventory holds")
	check(str(run.hands_for_merc(int(shop_player.merc_id)).get("main", "")) == "axe_makeshift",
		"which is the hand the page is told the run is holding")
	game.town.forge_panel.close_panel()
	# Take the demons' gate: the boss level begins in the caves, and its queue
	# carries that faction's boss.
	run._take_portal(int(_gate("caves").get_meta("serial")), body)
	check(run.level == 10 and run.boss_level, "level 10 is the boss")
	check(run.biome_id == "caves", "and it is fought in the biome of the gate taken")
	check(run.stage_index == 0, "the boss closes the first island")
	var has_boss := false
	for spec in run._queue:
		if bool((spec as Dictionary).get("boss", false)):
			has_boss = true
	check(has_boss, "the boss level's queue carries the faction's boss")
	var keys_before: int = int(meta.keys)
	for _round in 60:
		run.tick(2.5)
		for mob in run._mobs.duplicate():
			if is_instance_valid(mob) and mob.get("alive") != false:
				mob.take_damage(4096.0, 1)
		run.tick(0.2)
		if run.level_cleared:
			break
	check(run.level_cleared, "the boss level clears")
	check(int(meta.keys) > keys_before, "the boss pays unlock keys (%d)" % int(meta.keys))
	# The level after the boss is a new depth block, and the gate taken decides
	# what stands on it.
	run._open_chest(int((_prop_of("chest") as Node3D).get_meta("serial")), body)
	var out := _gate("arena")
	check(out != null, "the clones' gate stands past the boss")
	run._take_portal(int(out.get_meta("serial")), body)
	check(run.level == 11 and run.stage_index == 1, "level 11 stands on island 2")
	check(run.biome_id == "arena", "and the biome is the gate taken (%s)" % run.biome_id)
	check(str(run.state().get("faction", "")) == "clones", "with the clones behind it")
	check(run.stage != null and is_instance_valid(run.stage), "the new island is built")
	check(body.global_position.y > 600.0, "the party stands on the new island")
	# The pit's brain performs item skills from `Medium` up, and the session stands
	# on `Hard`: every clone this island lands carries one skill of its own, fit to
	# the hand that will fire it.
	for _round in 14:
		run.tick(2.5)
		if not run._mobs.is_empty():
			break
	var pit: Array = []
	for mob in run.live_mobs():
		if mob.has_method("ai_tier_name"):
			pit.append(mob)
	check(not pit.is_empty(), "the clones' island lands clone bodies (%d)" % pit.size())
	var armed := 0
	var fit := 0
	for mob in pit:
		check(str(mob.ai_tier_name()) == CloneAi.name_of(CloneAi.current_tier),
			"a pit body fights on the session's tier (%s)" % str(mob.ai_tier_name()))
		var skill := str(mob.get("ability_id"))
		if skill.is_empty():
			continue
		armed += 1
		if AbilityRules.fits_rig(AbilityRules.by_id(skill), mob.rig):
			fit += 1
	check(armed == pit.size(), "every pit body carries a skill of its own (%d of %d)"
		% [armed, pit.size()])
	check(armed == fit, "and each is one their own hand can fire (%d of %d)" % [fit, armed])
	run.queue_clear()
	run._free_mobs()


## A swarm contract promises a 2X chest, and a chest is stood one a soul: a 2X
## promise under a party of two is four boxes, two for each player, each with its
## own three offers and its owner's name on the plate.
func _check_double_chest() -> void:
	run.queue_clear()
	run._free_mobs()
	run.wave_active = false
	run.level_cleared = false
	run._clear_stage_props()
	run.active_contract = {
		"kind": "combat", "biome": run.biome_id, "faction": "clones",
		"trial": "swarm",
		"trial_params": {"budget_mult": 1.5, "live_cap_add": 6},
		"chest": {"surface": Mods.CHEST_ATTACK, "tier": Mods.RARITY_COMMON,
			"mult": 2},
		"label": "ATTACK  ·  COMMON  ·  2X  ·  SWARM",
	}
	# One soul at the table first: the promise is two boxes for that soul.
	run._clear_level()
	var contracted := _contracted_chests()
	check(contracted.size() == 2,
		"a 2X contract stands two boxes for the one soul in the run (%d)"
			% contracted.size())
	check(_chest_owners(contracted) == [1, 1],
		"both of them that soul's (%s)" % str(_chest_owners(contracted)))
	check(_chest_drafts(contracted) == 2,
		"each with its own three-card draft (%d)" % _chest_drafts(contracted))
	# A second soul joins the run. The promise doubles again, and neither player
	# can spend the other's box.
	var second: int = game.warband.add_mercenary("Brine")
	for _beat in 4:
		await physics_frame
	check(second > 0 and game.controller.body_of(second) != null,
		"The second body stands on the run's field")
	if second <= 0 or game.controller.body_of(second) == null:
		return
	game.controller.activate(2, second)
	run._spawn_runners()
	check(run.players.has(2), "The second soul is in the run (%s)" % str(run.players.keys()))
	run._clear_stage_props()
	run._clear_level()
	contracted = _contracted_chests()
	check(contracted.size() == 4,
		"a 2X contract under two players stands four boxes (%d)" % contracted.size())
	var owners := _chest_owners(contracted)
	check(owners.count(1) == 2 and owners.count(2) == 2,
		"two for each soul (%s)" % str(owners))
	check(_chest_drafts(contracted) == 4,
		"and every one of them carries a three-card draft of its own (%d)"
			% _chest_drafts(contracted))
	# A press on somebody else's box spends nothing at all.
	var foreign = null
	for chest in contracted:
		if int(Props.payload_of(chest).get("owner", 0)) == 2:
			foreign = chest
			break
	if foreign != null:
		var stacks_before: int = run.players.get(1).engine.total_stacks()
		run._open_chest(int(foreign.get_meta("serial")), body)
		check(run.players.get(1).engine.total_stacks() == stacks_before,
			"a player cannot open another player's chest")
		check(run.draft_offers.has(int(foreign.get_meta("serial"))),
			"and the box keeps its own owner's draft")


## Every chest standing on the level that wears a contract: the level's main boxes.
func _contracted_chests() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for prop in run._props:
		if not is_instance_valid(prop) or Props.prop_kind(prop) != "chest":
			continue
		if not Props.payload_of(prop).get("contract", {}).is_empty():
			out.append(prop)
	return out


## The owner each of those boxes was stood for, in the order they stand.
func _chest_owners(chests: Array[Node3D]) -> Array:
	var out: Array = []
	for chest in chests:
		out.append(int(Props.payload_of(chest).get("owner", 0)))
	out.sort()
	return out


## How many of those boxes carry a whole three-card hand for their owner.
func _chest_drafts(chests: Array[Node3D]) -> int:
	var count := 0
	for chest in chests:
		var payload := Props.payload_of(chest)
		var owner := int(payload.get("owner", 0))
		var offers: Variant = run.draft_offers.get(int(chest.get_meta("serial")),
			payload.get("offers", {}))
		if not offers is Dictionary:
			continue
		var row: Variant = (offers as Dictionary).get(owner, [])
		if row is Array and (row as Array).size() == 3:
			count += 1
	return count


## Faulty Chests: the cards a body walks away from do not vanish. Each stack
## keeps one, laid at the box's own feet as a one-card pickup with that soul's
## name on it. A chest with no stack behind it still spends what it was not
## asked for, so the two halves are checked against each other.
func _check_kept_offers() -> void:
	var hand = run.players.get(1)
	check(hand != null and is_instance_valid(hand), "the soul has a runtime")
	if hand == null or not is_instance_valid(hand) or run.stage == null:
		return
	var offered: Array[String] = ["steady_draw", "rapid_fire", "heavy_caliber"]
	# Without the row, the two cards the body did not take are only spent.
	var plain := _stand_test_chest(1, offered)
	var props_before: int = run._props.size()
	var answer: Dictionary = run.choose_draft(1, plain, 0)
	check(bool(answer.get("ok", false)),
		"a card chest takes the choice (%s)" % str(answer.get("message", "")))
	check(_kept_cards() == 0 and run._props.size() == props_before - 1,
		"and a chest with no Faulty Chests behind it leaves nothing (%d props)" % run._props.size())
	# One stack, and the card walked past waits on the ground.
	hand.engine.add_mod("faulty_chests", 1)
	hand.apply_stats()
	var kept := _stand_test_chest(1, offered)
	var picked: Dictionary = run.choose_draft(1, kept, 0)
	check(bool(picked.get("ok", false)),
		"the chest takes the choice (%s)" % str(picked.get("message", "")))
	var cards := _kept_cards()
	check(cards == 1, "one Faulty Chests stack keeps one card (%d)" % cards)
	var left := ""
	for prop in run._props:
		if not is_instance_valid(prop) or Props.prop_kind(prop) != "chest":
			continue
		var payload := Props.payload_of(prop)
		if str(payload.get("label", "")) != "AN UNCHOSEN CARD":
			continue
		check(int(payload.get("owner", 0)) == 1, "the kept card is the chooser's own")
		var row: Variant = (payload.get("offers", {}) as Dictionary).get(1, [])
		check(row is Array and (row as Array).size() == 1,
			"and it carries the one card it kept")
		if row is Array and (row as Array).size() == 1:
			left = str((row as Array)[0])
	check(not left.is_empty() and left != str(offered[0]),
		"the card kept is one the body did not take (%s)" % left)
	# Clean up: the shelf's own numbers belong to other checks.
	for id in offered + ["faulty_chests"]:
		hand.engine.stacks.erase(id)
	hand.engine._dirty = true
	hand.apply_stats()
	for prop in run._props.duplicate():
		if not is_instance_valid(prop) or Props.prop_kind(prop) != "chest":
			continue
		if str(Props.payload_of(prop).get("label", "")) != "AN UNCHOSEN CARD":
			continue
		run._props.erase(prop)
		run._props_by_serial.erase(int(prop.get_meta("serial")))
		prop.queue_free()


## A box standing on the level with a hand of cards for one soul.
func _stand_test_chest(peer: int, offers: Array[String]) -> int:
	var payload := {
		"payout": Mods.PAYOUT_CARDS, "style": "mini", "level": run.level,
		"owner": peer, "owner_name": run._peer_name(peer),
		"owner_colour": run._peer_colour(peer), "label": "A TESTED CHEST",
		"offers": {peer: offers},
	}
	var chest = run._spawn_prop("chest", run.stage.reward_point(0, 4, 3.2), payload)
	if chest == null:
		return 0
	var serial := int(chest.get_meta("serial"))
	run.draft_offers[serial] = payload["offers"]
	return serial


## How many cards are lying on the island because a chest was left half-taken.
func _kept_cards() -> int:
	var count := 0
	for prop in run._props:
		if not is_instance_valid(prop) or Props.prop_kind(prop) != "chest":
			continue
		if str(Props.payload_of(prop).get("label", "")) == "AN UNCHOSEN CARD":
			count += 1
	return count


## The draft is the run's, not the island's. Level eleven is a new depth block -
## new ground, new biome, new wave - and the body that walks onto it still holds
## every stack it fought for, on the same runtime it took them on.
func _check_island_carry() -> void:
	var hand = run.players.get(1)
	check(hand != null and is_instance_valid(hand), "the soul has a runtime")
	if hand == null or not is_instance_valid(hand):
		return
	check(bool(hand.take_mod("steady_draw").get("ok", false)), "a card lands on the body")
	var stacks := int(hand.engine.stacks_of("steady_draw"))
	check(stacks >= 1, "and is booked in its engine (%d)" % stacks)
	run.queue_clear()
	run._free_mobs()
	run.wave_active = false
	run.level = 10
	run.stage_index = 0
	run.wave = 10
	run.level_cleared = true
	run.advance_level("wilderness")
	check(run.stage_index == 1 and run.level == 11,
		"level eleven is a new island (island %d, level %d)" % [run.stage_index, run.level])
	var carried = run.players.get(1)
	check(carried == hand, "the body keeps the runtime it took the card on")
	check(carried != null and is_instance_valid(carried)
		and int(carried.engine.stacks_of("steady_draw")) == stacks,
		"and the stack crosses the gate with it (%s)" % str(carried.engine.stacks if carried != null else {}))


## The island's edge is a warning, not a wall. A body that stands out past the
## fight ring is told to come back; one that does not is put in the middle of the
## map and pays a share of whatever life it had left. Both halves of it are the
## report the fix was made for, so both halves are checked.
func _check_bounds() -> void:
	var stage = run.stage
	check(is_instance_valid(stage) and stage.play_radius() > 0.0,
		"the island names the ring it is fought in")
	if not is_instance_valid(stage):
		return
	# A quiet island: a live wave would put the body on the dirt mid-check, and a
	# downed body has no bounds clock to run out. A standing drain or bleed would
	# move the pool under the arithmetic, so those are cleared too.
	run.queue_clear()
	run._free_mobs()
	run.wave_active = false
	run._bleeds.clear()
	run._zones.clear()
	if not bool(body.alive):
		body.revive()
	await physics_frame
	var centre: Vector3 = stage.global_position
	var outside: Vector3 = centre + Vector3(0.0, 0.2, stage.play_radius() + 3.0)
	# Out, and warned.
	var health_before: float = body.health
	body.global_position = outside
	for frame in 30:
		await physics_frame
	check(run._outside.size() == 1, "standing outside the ring starts a clock for that body")
	check(game.hud._status_label.text.begins_with("RETURN TO THE FIGHT"),
		"and the run says so before it costs anything: %s" % game.hud._status_label.text)
	# Back in, and forgiven.
	body.global_position = stage.middle()
	for frame in 20:
		await physics_frame
	check(run._outside.is_empty(), "walking back in clears the clock")
	check(body.health >= health_before - 1.0, "and costs nothing at all")
	# Out, and staying out: the run is left to act, so the body is not touched
	# again until it has been moved.
	body.global_position = outside
	var frames := 0
	var health_outside: float = body.health
	while frames < 460 and body.global_position.distance_to(stage.middle()) > 1.0:
		await physics_frame
		frames += 1
		if body.global_position.distance_to(stage.middle()) > 1.0:
			health_outside = body.health
	check(run._outside.is_empty() and body.global_position.distance_to(stage.middle()) < 1.0,
		"a body that will not come back is put in the middle of the island (%d frames)" % frames)
	var paid := health_outside * float(DirectorScript.BOUNDS_COST)
	check(absf(health_outside - body.health - paid) <= 0.6,
		"having paid %.0f%% of the life it had left (%.1f of %.1f)"
		% [float(DirectorScript.BOUNDS_COST) * 100.0, health_outside - body.health, health_outside])
	for frame in 10:
		await physics_frame
	# The Speed chest is the body's own feet: a card on the run has to reach the
	# three movement state machines, or the shelf is a plate of numbers that do
	# nothing. Each card here is one key, so one check a machine.
	var speed_hand = run.players.get(1)
	check(absf(float(body.dodge.travel) - DodgeStep.TRAVEL) < 0.001
		and absf(float(body.roll.speed) - DodgeRoll.SPEED) < 0.001
		and absf(float(body.slide.duration) - RunningSlide.DURATION) < 0.001,
		"a run body walks, rolls and slides on its own constants before a card")
	check(bool(speed_hand.take_mod("lightfoot").get("ok", false))
		and bool(speed_hand.take_mod("long_roll").get("ok", false))
		and bool(speed_hand.take_mod("low_slide").get("ok", false)),
		"the Speed shelf deals a step, a roll and a slide card")
	body._tune_movement()
	check(absf(float(body.dodge.travel) - (DodgeStep.TRAVEL + 0.30)) < 0.001,
		"Lightfoot carries the side step %.2f m" % float(body.dodge.travel))
	check(absf(float(body.roll.speed) - (DodgeRoll.TRAVEL + 1.5) / DodgeRoll.DURATION) < 0.001,
		"Long Roll pays its metre on the roll's own clock (%.2f m/s)" % float(body.roll.speed))
	check(absf(float(body.slide.duration) - RunningSlide.DURATION * 1.18) < 0.001,
		"Low Slide runs the slide 18%% longer (%.2f s)" % float(body.slide.duration))


func _check_close() -> void:
	var town_point: Vector3 = game.town.global_position
	var runs_before: int = int(meta.runs)
	run._finish_run(false)
	check(not run.is_running(), "the run closes")
	check(run.stage == null, "the island is gone")
	# The chest's kit went with the run: the page is the wardrobe's again.
	var merc := int(game.controller.merc_of(body))
	game.paperdoll.open(merc)
	check(str(game.paperdoll.slot_rows.get("chest", {}).get("item_id", ""))
		== str(game.warband.roster.equipped_of(merc).get("chest", "")),
		"the character page drops the run's kit when the run closes")
	game.paperdoll.close()
	check(int(meta.runs) == runs_before + 1, "the ledger books the run")
	check(int(meta.best_level) >= 11, "the deepest level is on the books (%d)" % int(meta.best_level))
	check(body.global_position.distance_to(town_point) < 60.0, "the body is back in the square")
	check(body.bounds < 2000.0, "and the world's bound is restored")
	check(game.roguelite_hud.open_panels() == false, "no plate is left open")
	# The starter is a staff skill: the bow campaign kit the body walks out in
	# does not carry it, and the rig's own family check is what says so.
	var kept := false
	for grant in AbilityRules.granted(body.rig):
		if str((grant as Dictionary).get("id", "")) == "fireball":
			kept = true
	check(not kept, "a bow campaign kit carries no staff starter")
	# The net surface a run needs, present even offline.
	var session_script = load("res://scripts/warband/warband_session.gd")
	check(session_script != null, "the session script still loads")
	var session = session_script.new()
	for method in ["send_roguelite_event", "send_roguelite_request", "receive_roguelite",
			"roguelite_request"]:
		check(session.has_method(method), "the session carries %s" % method)
	session.free()
	run.apply_event({"t": "gold", "total": 321})
	check(run.gold_mirror == 321, "the purse follows the host's total, not a delta")
	run.apply_event({"t": "fx", "kind": "nova", "at": body.global_position, "points": []})
	check(true, "a proc flash applies without a world-side error")
	await _check_ability_book_actions()


## The rack's ability page is the **equip** now, not the unlock: a skill is opened
## by an ABILITY chest, so a row the player has not found carries no price and no
## button, and an opened one equips on the body the soul is inside.
func _check_ability_book_actions() -> void:
	meta.award_keys(5)
	var keys_before := int(meta.keys)
	var merc := int(game.controller.merc_of(body))
	game.town.forge_panel.open("abilities")
	game.town.forge_panel._refresh()
	var locked := _panel_button(game.town.forge_panel, "DASH", "LOCKED")
	check(locked == null, "the book sells no locked Dash row")
	var locked_row := _panel_label(game.town.forge_panel, "DASH", "ABILITY CHEST")
	check(locked_row != null,
		"the not-found row says where a skill comes from (%s)"
			% (str(locked_row.text) if locked_row != null else "no row"))
	check(int(meta.keys) == keys_before, "and the book spends no keys")
	# The chest is what opens it; the book is what wears it.
	check(bool(meta.grant_ability("dash").get("ok", true)),
		"an ability chest's grant opens Dash for the player")
	game.town.forge_panel._refresh()
	var equip := _panel_button(game.town.forge_panel, "DASH", "EQUIP")
	check(equip != null, "the opened Dash row becomes an equip")
	if equip != null:
		equip.pressed.emit()
	check(Array(game.warband.roster.hotbar_order_of(merc)).has("dash"),
		"and the body's equipped list names Dash")
	var granted := false
	for definition in AbilityRules.granted(body.rig):
		if str((definition as Dictionary).get("id", "")) == "dash":
			granted = true
	check(granted, "Dash reaches the live bar")
	game.town.forge_panel.close_panel()


## The first button whose text contains both needles, for the page's rows.
func _panel_button(panel, first: String, second: String) -> Button:
	for child in panel._body.get_children():
		if not child is Button:
			continue
		var text := str((child as Button).text).to_upper()
		if text.contains(first.to_upper()) and text.contains(second.to_upper()):
			return child
	return null


## The same, for a row the page writes as a line of text rather than a button.
func _panel_label(panel, first: String, second: String) -> Label:
	for child in panel._body.get_children():
		if not child is Label:
			continue
		var text := str((child as Label).text).to_upper()
		if text.contains(first.to_upper()) and text.contains(second.to_upper()):
			return child
	return null


func _finish() -> void:
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	print("ROGUELITE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
