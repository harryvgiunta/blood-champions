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
const Props = preload("res://scripts/roguelite/roguelite_props.gd")
const MetaScript = preload("res://scripts/roguelite/roguelite_meta.gd")

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
	await _open_world()
	await _check_town()
	_check_run()
	await _check_waves()
	_check_rewards()
	_check_portal()
	_check_shop_and_boss()
	_check_arsenal_in_hand()
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
	# The press itself: the rack opens the board on the rack page.
	var service: String = game.town.interact_at(1, body.global_position)
	check(service == "roguelite_rack", "the rack's press resolves to the rack")
	check(game.town.forge_panel.is_open(), "and opens the run board")
	check(game.town.forge_panel.mode == "rack", "on the weapon rack")
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
	check(body.bounds > 1000.0, "the island lifts the world's bound")
	check(body.global_position.y > 600.0, "the body stands on the island, not in the wood")
	check(absf(body.global_position.y - StageScript.LIFT) < 2.0, "the first island sits at the lift")


func _check_waves() -> void:
	var guard_before: int = game.guards.size()
	var stormed := false
	for _round in 14:
		run.tick(2.5)
		if not run._mobs.is_empty():
			stormed = true
			break
	check(stormed, "the director queued and spawned the level's wave")
	check(game.guards.size() > guard_before, "the wave joined the world's hostile list")
	var first = run._mobs[0]
	check(first != null and is_instance_valid(first), "a mob exists")
	check(str(first.name).begins_with("Rogue"), "the mob carries a run name (%s)" % str(first.name))
	check(first.get("replica") != true, "a host wave is authoritative")
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
	# Clear the level's wave.
	for _round in 20:
		run.tick(2.5)
		for mob in run._mobs.duplicate():
			if is_instance_valid(mob) and mob.get("alive") != false:
				mob.take_damage(4096.0, 1)
		run.tick(0.2)
		if run.level_cleared:
			break
	check(run.level_cleared, "the level clears when its wave is dead")
	check(run.crystals > 0, "kills paid crystals (%d)" % run.crystals)
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


func _check_rewards() -> void:
	var chest := _prop_of("chest")
	check(chest != null, "a reward chest stands on the level")
	var pedestal := _prop_of("pedestal")
	check(pedestal != null, "an upgrade pedestal stands on the level")
	var greed := _prop_of("greed")
	check(greed != null, "a Greed Totem stands on the level")
	var portal := _prop_of("portal")
	check(portal != null, "one portal stands on the level")
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
	# The draft.
	var pedestal_serial := int(pedestal.get_meta("serial"))
	var offers: Array = run.draft_offers.get(pedestal_serial, [])
	if offers.is_empty():
		run._open_draft(pedestal_serial, body)
		offers = run.draft_offers.get(pedestal_serial, [])
	check(offers.size() == 3, "the pedestal holds three upgrades")
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
	# The shop's counter still sells for crystals.
	var wares := [{"id": "rapid_fire", "name": "Berserk Rate", "price": 10,
		"rarity": "common"}]
	var shop: Node3D = run._spawn_prop("shop", run.stage.rim_point(1, 6), {"wares": wares})
	run.shop_wares[int(shop.get_meta("serial"))] = wares
	run.crystals = 100
	var bought: Dictionary = run.buy(int(shop.get_meta("serial")), 0, 1)
	check(bool(bought.get("ok", false)), "the stall sells a ware")
	check(run.crystals == 90, "and takes its price")


func _check_portal() -> void:
	var portal := _prop_of("portal")
	check(portal != null, "a portal is standing")
	var before_level: int = run.level
	var before_island: int = run.stage_index
	run._take_portal(int(portal.get_meta("serial")), body)
	check(run.level == before_level + 1, "the portal takes the next level")
	check(run.stage_index == before_island, "and the same island keeps its ground")
	check(run.level_cleared == false and run.wave_active, "the next level opens on its wave")
	check(body.global_position.y > 600.0, "the party stands on the island")


func _check_shop_and_boss() -> void:
	# Level nine is the shop: no wave, a stall, the rack and the portal to the boss.
	run.wave = 9
	run.level = 8
	run.level_cleared = true
	run._begin_level()
	check(run.shop_level and run.level == 9, "level 9 is the shop level")
	check(not run.wave_active, "the shop level sends no wave")
	check(_prop_of("shop") != null, "the shop stall stands")
	check(_prop_of("rack") != null, "the weapon rack stands")
	check(_prop_of("pedestal") != null, "an upgrade pedestal stands")
	var portal := _prop_of("portal")
	check(portal != null and str(Props.payload_of(portal).get("kind", "")) == "boss",
		"the shop's portal leads to the boss")
	# The rack opens mid-run, and a bind reaches the body.
	game.town.forge_panel.open("rack")
	check(game.town.forge_panel.mode == "rack", "the shop rack opens the board")
	game.town.forge_panel.close_panel()
	# Take the portal: the boss level begins, and its queue carries the boss.
	run._take_portal(int(portal.get_meta("serial")), body)
	check(run.level == 10 and run.boss_level, "level 10 is the boss")
	check(run.stage_index == 0, "the boss closes the first island")
	var has_boss := false
	for spec in run._queue:
		if bool((spec as Dictionary).get("boss", false)):
			has_boss = true
	check(has_boss, "the boss level's queue carries the faction's boss")
	var keys_before: int = int(meta.keys)
	for _round in 20:
		run.tick(2.5)
		for mob in run._mobs.duplicate():
			if is_instance_valid(mob) and mob.get("alive") != false:
				mob.take_damage(4096.0, 1)
		run.tick(0.2)
		if run.level_cleared:
			break
	check(run.level_cleared, "the boss level clears")
	check(int(meta.keys) > keys_before, "the boss pays unlock keys (%d)" % int(meta.keys))
	# The level after the boss is a new island.
	run._open_chest(int((_prop_of("chest") as Node3D).get_meta("serial")), body)
	var out := _prop_of("portal")
	run._take_portal(int(out.get_meta("serial")), body)
	check(run.level == 11 and run.stage_index == 1, "level 11 stands on island 2")
	check(run.biome_id == "caves", "and the biome changed (%s)" % run.biome_id)
	check(run.stage != null and is_instance_valid(run.stage), "the new island is built")
	check(body.global_position.y > 600.0, "the party stands on the new island")


func _check_close() -> void:
	var town_point: Vector3 = game.town.global_position
	var runs_before: int = int(meta.runs)
	run._finish_run(false)
	check(not run.is_running(), "the run closes")
	check(run.stage == null, "the island is gone")
	check(int(meta.runs) == runs_before + 1, "the ledger books the run")
	check(int(meta.best_level) >= 11, "the deepest level is on the books (%d)" % int(meta.best_level))
	check(body.global_position.distance_to(town_point) < 60.0, "the body is back in the square")
	check(body.bounds < 2000.0, "and the world's bound is restored")
	check(game.roguelite_hud.open_panels() == false, "no plate is left open")
	# The net surface a run needs, present even offline.
	var session_script = load("res://scripts/warband/warband_session.gd")
	check(session_script != null, "the session script still loads")
	var session = session_script.new()
	for method in ["send_roguelite_event", "send_roguelite_request", "receive_roguelite",
			"roguelite_request"]:
		check(session.has_method(method), "the session carries %s" % method)
	session.free()
	run.apply_event({"t": "crystals", "total": 321})
	check(run.crystals == 321, "the purse follows the host's total, not a delta")
	run.apply_event({"t": "fx", "kind": "nova", "at": body.global_position, "points": []})
	check(true, "a proc flash applies without a world-side error")


func _finish() -> void:
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	print("ROGUELITE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
