extends SceneTree
## Blood Champions end to end: the player ledger, the armory, the upgrade engine,
## the town's two fixtures, and one endless run from level one through a shop, a
## boss, and the island after it.
##
## What this owns: that a new player has no keys and only the starters, that the
## rack opens a named weapon for its price and binds it, that the stacking rules
## still answer, that a run writes its level and island, that a boss is the only
## key drop, that the level before a boss is a shop, that the portal carries the
## party on, and that closing back onto the square restores the body.

const WORLD = "res://scenes/warband_world.tscn"
const TEST_STATE := "user://roguelite_regression_state.json"
const TEST_WARBAND := "user://roguelite_regression_warband.json"
const TEST_META := "user://roguelite_regression_meta.json"

const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const ProcEngineScript = preload("res://scripts/roguelite/proc_engine.gd")
const StageScript = preload("res://scripts/roguelite/roguelite_stage.gd")
const DirectorScript = preload("res://scripts/roguelite/run_director.gd")
const Props = preload("res://scripts/roguelite/roguelite_props.gd")
const MetaScript = preload("res://scripts/roguelite/roguelite_meta.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const ArmorLoot = preload("res://scripts/roguelite/armor_loot.gd")
const RunPlayerScript = preload("res://scripts/roguelite/run_player.gd")
const AbilityIndex = preload("res://scripts/roguelite/ability_index.gd")
const CloneScript = preload("res://scripts/ranger_clone.gd")

## The one field `AbilityRules.damage_for` reads off a rig for the spell channel.
class SpellRig extends RefCounted:
	var scale := 2.0
	func spell_scale() -> float:
		return scale

## A ranger rig that only records what it was handed, for the pit's loadout roll:
## the clone's own `_roll_loadout` needs a `rig` and nothing else of it.
class KitRig extends Node:
	var loadout: Dictionary = {}

	func apply_loadout(rolled: Dictionary) -> void:
		loadout = rolled

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
	_check_ability_index()
	_check_ladder()
	_check_armor_loot()
	_check_starter_ability()
	_check_clone_armoury()
	await _open_world()
	await _check_town()
	await _check_run()
	await _check_ability_in_hand()
	await _check_waves()
	_check_rewards()
	_check_run_kit()
	_check_portal()
	_check_shop_and_boss()
	_check_arsenal_in_hand()
	await _check_bounds()
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
	check(meta.is_unlocked("bow_twig"), "the twig bow is free")
	check(meta.is_unlocked("hatchet_makeshift"), "the hatchet is free")
	check(not meta.is_unlocked("xbow_heavy"), "the heavy crossbow is locked")
	check(meta.loadout_for("ranged") == MetaScript.DEFAULT_RANGED, "ranged slot starts the twig bow")
	check(meta.loadout_for("melee") == MetaScript.DEFAULT_MELEE, "melee slot starts the hatchet")
	check(not meta.set_loadout_slot("ranged", "javelin_iron").ok, "a locked piece cannot be bound")
	check(not meta.set_loadout_slot("ranged", "hatchet_makeshift").ok, "a melee piece cannot take the ranged slot")
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
	var repeat: Dictionary = meta.unlock_weapon("xbow_heavy")
	check(not bool(repeat.get("ok", false)), "an open weapon cannot be bought twice")
	meta.save_meta()
	meta.load_meta()
	check(meta.is_unlocked("xbow_heavy"), "the ledger survives a reload")
	check(meta.keys == 10 - price, "and so do its keys")
	check(meta.best_level == 0, "a fresh record is level zero")
	meta.note_run(12, 4)
	check(meta.best_level == 12 and meta.runs == 1, "a run books its deepest level")
	check(meta.set_loadout_slot("ranged", "xbow_heavy").ok, "an opened piece takes its slot")
	check(meta.loadout_for("ranged") == "xbow_heavy", "and the slot remembers it")


func _check_armory() -> void:
	check(Weapons.has("bow_twig") and Weapons.has("hatchet_makeshift"), "both starters are in the registry")
	check(Weapons.slot_of("bow_twig") == "ranged", "the twig bow is ranged")
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
	var offers: Array = Mods.draft(draft_rng, 3, false)
	check(offers.size() == 3, "a draft offers three")
	var unique := {}
	for id in offers:
		unique[id] = true
		check(Mods.rarity_of(str(id)) != Mods.RARITY_GREED, "a normal draft holds no greed")
	check(unique.size() == 3, "a draft never repeats a row")
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
	check(Mods.all().size() == 161, "the pool is 120 base + 41 ability rows (%d)" % Mods.all().size())
	check(ids.size() == Mods.all().size(), "every row has its own id")
	check(int(tiers.get(Mods.RARITY_COMMON, 0)) == 63,
		"63 commons (%d)" % int(tiers.get(Mods.RARITY_COMMON, 0)))
	check(int(tiers.get(Mods.RARITY_EPIC, 0)) == 51,
		"51 epics (%d)" % int(tiers.get(Mods.RARITY_EPIC, 0)))
	check(int(tiers.get(Mods.RARITY_LEGENDARY, 0)) == 33,
		"33 legendaries (%d)" % int(tiers.get(Mods.RARITY_LEGENDARY, 0)))
	check(int(tiers.get(Mods.RARITY_GREED, 0)) == 14,
		"14 greed rows (%d)" % int(tiers.get(Mods.RARITY_GREED, 0)))
	check(int(families.get("shot", 0)) == 30 and int(families.get("hand", 0)) == 11
		and int(families.get("ability", 0)) == 60 and int(families.get("perk", 0)) == 48
		and int(families.get("relic", 0)) == 12, "the five families keep their share")
	check(ready == 130, "130 live rows are the pool the surfaces offer (%d)" % ready)
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


## The two catalogs that use the word "ability" are joined by one index, not
## confused: 35 active skills, 60 ability upgrades, 95 rows, unique ids.
func _check_ability_index() -> void:
	var active := AbilityIndex.active_entries()
	var upgrades := AbilityIndex.upgrade_entries()
	var all_entries := AbilityIndex.entries()
	check(active.size() == 35, "the active ability catalog holds 35 (%d)" % active.size())
	check(upgrades.size() == 60, "the ability upgrade set holds 60 (%d)" % upgrades.size())
	check(all_entries.size() == 95, "the merged index holds 95 (%d)" % all_entries.size())
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
	# An island-one pedestal is commons, and a luck-stacked one on island nine is
	# still commons and epics: luck moves weight, never the shelf.
	var off_shelf := 0
	for _round in 120:
		for id in Mods.draft(rng, 3, Mods.surface_tiers(Mods.SURFACE_PEDESTAL, 1),
				0, 1, []):
			if Mods.rarity_of(str(id)) != Mods.RARITY_COMMON:
				off_shelf += 1
		for id in Mods.draft(rng, 3, Mods.surface_tiers(Mods.SURFACE_PEDESTAL, 9),
				6, 9, []):
			var tier := Mods.rarity_of(str(id))
			if tier == Mods.RARITY_LEGENDARY or tier == Mods.RARITY_GREED:
				off_shelf += 1
			if not Mods.ready_of(str(id)):
				off_shelf += 1
	check(off_shelf == 0, "a pedestal never carries a legendary, a greed row or a pending row")
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
	var chest := Mods.tier_weights(Mods.surface_tiers(Mods.SURFACE_CHEST, 4), 0, 4,
		Mods.CHEST_LEGENDARY_SCALE, true)
	check(absf(float(chest.get(Mods.RARITY_LEGENDARY, 0.0)) - 4.0) < 0.01,
		"a reward chest's legendary is 4%% on island 4 (%.2f)" % float(
			chest.get(Mods.RARITY_LEGENDARY, 0.0)))
	var chest_late := Mods.tier_weights(Mods.surface_tiers(Mods.SURFACE_CHEST, 5), 0, 5,
		Mods.CHEST_LEGENDARY_SCALE, true)
	check(absf(float(chest_late.get(Mods.RARITY_LEGENDARY, 0.0)) - 5.5) < 0.01,
		"and 5.5%% on island 5+ (%.2f)" % float(chest_late.get(Mods.RARITY_LEGENDARY, 0.0)))
	check(Mods.stall_price(Mods.RARITY_COMMON, 9) == 67
		and Mods.stall_price(Mods.RARITY_LEGENDARY, 9) == 137,
		"the stall prices a common at 67 and a legendary at 137 on level 9")


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
	# The square dresses a body in the rack's ranged piece, and puts the world's
	# kit back when the body walks out of the walls.
	check(str(body.rig.weapon) == "bow", "a body in the square holds the rack's bow")
	check(int(body.rig.bow_index) == 4, "and it is the piece the rack bound")
	body.global_position = game.town.global_position + Vector3(0.0, 0.0, -60.0)
	game._sync_town_dress()
	check(str(body.rig.weapon) == "bow" and int(body.rig.bow_index) == 3,
		"walking out restores the body's own starter bow")
	body.global_position = game.town.service_point("roguelite_rack")
	game._sync_town_dress()
	check(str(body.rig.weapon) == "bow", "walking back in dresses it again")
	# The page is a picture of that body: while it holds the rack's piece the hand
	# row names that piece, not the wardrobe's, so the piece the portal carries is
	# the piece P shows - and a press on it cannot strip the roster slot it hides.
	var merc_in_square := int(game.controller.merc_of(body))
	var rack_piece := str(root.get_node("Roguelite").loadout_for("ranged"))
	var roster_before := str(game.warband.roster.equipped_of(merc_in_square).get("main", ""))
	game.paperdoll.open(merc_in_square)
	check(str(game.paperdoll.slot_rows.get("main", {}).get("item_id", "")) == rack_piece,
		"the character page shows the rack's hand in the square (%s)" % rack_piece)
	check(str((game.paperdoll.slot_rows["main"]["button"] as Button).text).contains("RACK"),
		"and names the hand as the rack's")
	game.paperdoll._on_slot_pressed(WarbandContracts.slot_from_id("main"))
	check(str(game.warband.roster.equipped_of(merc_in_square).get("main", "")) == roster_before,
		"clicking the square's hand never strips the wardrobe")
	# A wardrobe piece worn from the page is the body's again: the square dresses
	# a body once, it does not lock the hand the page reports.
	game.warband.stash.add("sword_arming", 1)
	game.paperdoll._on_stash_pressed("sword_arming")
	check(str(game.warband.roster.equipped_of(merc_in_square).get("main", "")) == "sword_arming",
		"a stash weapon is still worn in the square")
	check(str(game.paperdoll.slot_rows.get("main", {}).get("item_id", "")) == "sword_arming",
		"and the page names it once the body holds it")
	# The body goes back to the kit it walked in with, so the run below starts
	# from the square the rest of the suite expects.
	game.warband.equip_merc(merc_in_square, "main", roster_before)
	game.warband.stash.remove("sword_arming", 1)
	game.paperdoll.close()
	# The press itself: the rack opens the board on the rack page.
	var service: String = game.town.interact_at(1, body.global_position)
	check(service == "roguelite_rack", "the rack's press resolves to the rack")
	check(game.town.forge_panel.is_open(), "and opens the run board")
	check(game.town.forge_panel.mode == "rack", "on the weapon rack")
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
	check(run.level == 1 and run.wave == 1 and run.stage_index == 0, "the run starts at level 1, island 1")
	check(run.stage != null and is_instance_valid(run.stage), "an island was built")
	check(run.players.size() >= 1, "the body has a run runtime")
	var player = run.players.get(1)
	check(player != null and is_instance_valid(player), "the runtime is bound to peer 1")
	check(str(player.ranged_id) == "xbow_heavy", "the rack's choice rides into the run")
	check(int(body.rig.bow_index) == 4, "the heavy crossbow is in the rig's hand")
	# The page reads the hand the body is holding, not the wardrobe's: the run's
	# pair is on it and the page's own TAB brings the other hand up with the rig.
	var page_merc := int(game.controller.merc_of(body))
	game.paperdoll.open(page_merc)
	check(str(game.paperdoll.slot_rows.get("main", {}).get("item_id", "")) == str(player.ranged_id),
		"the character page shows the hand the run put up")
	check(str(game.paperdoll.slot_rows.get("off", {}).get("item_id", "")) == str(player.melee_id),
		"and the other one TAB reaches")
	game.paperdoll._swap_set()
	check(str(game.paperdoll.slot_rows.get("main", {}).get("item_id", "")) == str(player.melee_id),
		"the page's swap brings the other hand up")
	check(str(body.rig.weapon) != "bow", "and the rig is holding it")
	game.paperdoll._swap_set()
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
	check(opener != null and opener.armor.size() == 1,
		"the reward left one run piece to show on the page")
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
	check(str((row.get("button") as Button).text).contains("WON THIS RUN"),
		"and the row says it is the run's own")
	check(int(game.paperdoll.preview.rig.armor_piece(slot)) == set_index,
		"the stage ranger wears it too")
	game.paperdoll._on_slot_pressed(WarbandContracts.slot_from_id(slot))
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
	# Clear the level's wave. The director feeds it two bodies a tick, so the
	# round cap has to cover the level's whole budget rather than a guess at it.
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
	var pedestal := _prop_of("pedestal")
	check(pedestal != null, "an upgrade pedestal stands on the level")
	var greed := _prop_of("greed")
	check(greed != null, "a Greed Totem stands on the level")
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
	check(str(Props.payload_of(gates[0]).get("title", "")) == str(StageScript.biome("wilderness").name),
		"a gate's lintel carries its own biome")
	check(chest.global_position.distance_to(pedestal.global_position) < 7.0,
		"the chest stands a few paces from the pedestal (%.1f m)" % chest.global_position.distance_to(pedestal.global_position))
	check(pedestal.global_position.distance_to(gates[0].global_position) < 14.0,
		"and the gates one walk from the pedestal (%.1f m)" % pedestal.global_position.distance_to(gates[0].global_position))
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
	run._open_chest(chest_serial, body)
	check(run._opened.has(chest_serial), "the chest opens")
	check(not bool(body.downed) and float(body.health) > 0.0,
		"the chest wakes a downed body at half the pool")
	check(run._opened.has("chest"), "the chest unseals the portal")
	# The chest's other half: one piece of armour per body that opens it, worn on
	# the rig, kept on the run's own table, and with its welded modifiers taken.
	var opener = run.players.get(1)
	check(opener != null and opener.armor.size() == 1,
		"the chest hands its opener one piece of armour (%d)" % (
			opener.armor.size() if opener != null else -1))
	var chest_slot := ""
	if opener != null and not opener.armor.is_empty():
		chest_slot = str(opener.armor.keys()[0])
	var piece: Dictionary = opener.armor_piece(chest_slot) if opener != null else {}
	check(ArmorData.SLOTS.has(chest_slot), "the piece lands in a real slot (%s)" % chest_slot)
	check(int(body.rig.armor_piece(chest_slot)) == int(piece.get("set", -1)),
		"and the rig wears the set the chest rolled")
	for id in _piece_mods(piece):
		check(opener.engine.stacks_of(str(id)) >= 1,
			"a welded modifier is on the body (%s)" % str(id))
	print("ROGUELITE_ARMOUR %s" % ArmorLoot.status_line(piece))
	check(game.hud.status_line().find(ArmorLoot.title_of(piece)) >= 0,
		"the chest's line names the piece: %s" % game.hud.status_line())
	# A second press cannot milk a second piece out of the same chest, and a hand
	# flip re-dresses from the roster without dropping what the run won.
	run._open_chest(chest_serial, body)
	check(opener.armor.size() == 1, "a body gets one piece per chest")
	run._apply_hands(opener, "melee")
	check(int(body.rig.armor_piece(chest_slot)) == int(piece.get("set", -1)),
		"a hand swap keeps the chest's piece on the body")
	run._apply_hands(opener, "ranged")
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
	# The draft: one row of three per body in the run, not one shared row.
	var pedestal_serial := int(pedestal.get_meta("serial"))
	var draft_table: Dictionary = run.draft_offers.get(pedestal_serial, {})
	check(draft_table.size() == run.players.size(),
		"every body in the run draws its own draft row (%d rows, %d bodies)" % [
			draft_table.size(), run.players.size()])
	check(draft_table.has(1), "the local body has a row")
	var offers: Array = draft_table.get(1, [])
	if offers.is_empty():
		run._open_draft(pedestal_serial, body)
		offers = (run.draft_offers.get(pedestal_serial, {}) as Dictionary).get(1, [])
	check(offers.size() == 3, "the pedestal holds three upgrades for it")
	var player = run.players.get(1)
	var stacks_before: int = player.engine.total_stacks()
	var chosen: Dictionary = run.choose_draft(1, pedestal_serial, 0)
	check(bool(chosen.get("ok", false)), "the first upgrade is taken")
	check(player.engine.total_stacks() == stacks_before + 1, "the upgrade lands on the body")
	check(not run._props_by_serial.has(pedestal_serial), "the pedestal is spent")
	# The Greed Totem.
	var greed_serial := int(greed.get_meta("serial"))
	var health_before: float = float(body.health)
	var greed_stacks: int = player.engine.total_stacks()
	run._open_greed(greed_serial, body)
	check(player.engine.total_stacks() > greed_stacks, "the totem sells a greed upgrade")
	check(float(body.health) < health_before, "and takes its price in blood")
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


func _check_portal() -> void:
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


func _check_shop_and_boss() -> void:
	# Level nine is the shop: no wave, a stall, the rack and the gates to the boss.
	run.wave = 9
	run.level = 8
	run.level_cleared = true
	run._begin_level()
	check(run.shop_level and run.level == 9, "level 9 is the shop level")
	check(not run.wave_active, "the shop level sends no wave")
	check(_prop_of("shop") != null, "the shop stall stands")
	check(_prop_of("rack") != null, "the weapon rack stands")
	check(_prop_of("pedestal") != null, "an upgrade pedestal stands")
	var gates := _gates()
	check(gates.size() == 3, "the shop level stands all three gates (%d)" % gates.size())
	var all_boss := true
	for gate in gates:
		if str(Props.payload_of(gate).get("kind", "")) != "boss":
			all_boss = false
	check(all_boss, "and every one of them leads to the boss")
	# The rack opens mid-run, and a bind reaches the body.
	game.town.forge_panel.open("rack")
	check(game.town.forge_panel.mode == "rack", "the shop rack opens the board")
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


## The rack's ability page is the unlock and the equip: a locked row spends its
## keys, the same row then equips on the body the soul is inside, and the bar
## picks the skill up on the next dress.
func _check_ability_book_actions() -> void:
	meta.award_keys(5)
	var merc := int(game.controller.merc_of(body))
	game.town.forge_panel.open("abilities")
	game.town.forge_panel._refresh()
	var locked := _panel_button(game.town.forge_panel, "DASH", "LOCKED")
	check(locked != null, "the book offers the locked Dash row")
	if locked != null:
		locked.pressed.emit()
	check(meta.is_ability_unlocked("dash"), "the pressed row opens Dash for the player")
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


func _finish() -> void:
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	print("ROGUELITE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
