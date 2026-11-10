extends SceneTree
## Warband abilities and HUD: a possessed body's three skills are reachable from
## the number row, the HUD reads stamina and the grants from that same body, stock
## steel carries no skill until the altar anoints it, the right mouse button
## guards and peeks out of cover, and the scene-level ability node resolves a cue
## into exactly one projectile on the authority only.

const Actor = preload("res://scripts/warband/warband_body.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const AbilitiesScript = preload("res://scripts/warband/warband_abilities.gd")
const CameraRig = preload("res://scripts/warband/possession_camera.gd")

const ARMOR := {"head": 0, "chest": 0, "hands": 0, "legs": 0, "feet": 0}

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_ABILITIES_FAIL  ", message)


func _on_watchdog() -> void:
	check(false, "the regression did not finish in time")
	print("WARBAND_ABILITIES_REGRESSION checks=", checks, " failures=", failures)
	quit(1)


func key_event(code: Key, pressed: bool, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	return event


## Pump the real input path until `predicate` answers, or the timeout expires.
func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func mouse_event(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


## The key line an ability tile currently reads.
func tile_key(tile) -> String:
	var label = tile.get("_key")
	return str(label.text) if label != null else ""


## The skill a tile is currently drawing, "" for an empty tile.
func tile_id(tile) -> String:
	var definition = tile.get("_definition")
	return str(definition.get("id", "")) if definition is Dictionary else ""


## A real arena body with its own rig, built the way the campaign spawns one.
func fighter(parent: Node3D, index: int, at: Vector3) -> Node3D:
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index + 1, "Probe", at)
	actor.set_process(false)
	actor.rig.set_physics_process(false)
	actor.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	actor.combat.target_mask = 1 | 2
	actor.combat.damage_enabled = true
	# A bare harness has no floor to stand on; the skills only ask that the body
	# is not falling.
	actor.combat.grounded = true
	return actor


func run() -> void:
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(_on_watchdog)
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var actor := fighter(world, 0, Vector3.ZERO)
	# The opening beat hands the player an empty main hand: slot 0 falls back to
	# the legacy unarmed Charge.
	actor.rig.apply_loadout(State.build_loadout("", "", ARMOR))
	check(str(actor.rig.weapon) == "none", "an empty main hand holds nothing, got %s"
		% str(actor.rig.weapon))
	var charge: Dictionary = AbilityRules.definition_for(actor.rig, 0)
	check(str(charge.get("id", "")) == "charge", "an empty main hand grants Charge")

	var controller := ControllerScript.new()
	controller.name = "Controller"
	controller.auto_simulate = false
	world.add_child(controller)
	controller.active_actor = actor
	await _check_number_row(actor)
	_check_hud(world, actor)
	_check_peek(controller, actor)
	_check_peek_side(controller, actor, world)
	_check_ability_node(world, actor, controller)

	world.queue_free()
	print("WARBAND_ABILITIES_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


## The number row is the warband's binding, and the tenth slot rides the 0 key.
## The key travels through the real input pump, so the controller's own
## `_unhandled_input` is what answers.
func _check_number_row(actor) -> void:
	Input.parse_input_event(key_event(KEY_1, true))
	Input.flush_buffered_events()
	var started := await _wait_until(func(): return bool(actor.ability.active), 1.5)
	Input.parse_input_event(key_event(KEY_1, false))
	Input.flush_buffered_events()
	check(started, "KEY_1 starts slot 0")
	check(str(actor.ability.active_id) == "charge",
		"KEY_1 starts the Charge, got %s" % str(actor.ability.active_id))

	# Shift is not part of this binding: the same press with a held shift still
	# starts the skill, because the warband never asks for a modifier.
	actor.ability.cancel()
	actor.ability.cooldowns[0] = 0.0
	actor.stamina = actor.max_stamina
	Input.parse_input_event(key_event(KEY_1, true, true))
	Input.flush_buffered_events()
	var shifted := await _wait_until(func(): return bool(actor.ability.active), 1.5)
	Input.parse_input_event(key_event(KEY_1, false, true))
	Input.flush_buffered_events()
	check(shifted, "Shift+1 is the same press, not a requirement")
	actor.ability.cancel()
	actor.ability.cooldowns[0] = 0.0
	actor.stamina = actor.max_stamina

	# The assigned skills sit on the keys the player gave them and the starters
	# fill the free ones; medicine is not on the bar at all.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR))
	actor.rig.set_ability_loadout([
		"barrage", "triple_volley", "piercing_shot", "rain_of_ash", "skewer",
		"dash", "energy_shield", "three_strike",
	])
	var grants: Array = AbilityRules.granted(actor.rig)
	check(grants.size() == AbilityRules.SLOT_COUNT,
		"the hotbar is five keys wide")
	check(_granted_ids(grants).size() == AbilityRules.SLOT_COUNT,
		"five assigning skills fill the five keys, got %s"
		% str(_granted_ids(grants)))
	check(_granted_ids(grants) == ["barrage", "triple_volley",
			"piercing_shot", "rain_of_ash", "skewer"],
		"the assigned row comes first, in its own order, got %s"
		% str(_granted_ids(grants)))
	check(not _granted_ids(grants).has("bandage")
			and not _granted_ids(grants).has("healing_potion"),
		"medicine is not on the bar")

	# A dressing is bought, not free: the body is the gate - an empty pack refuses,
	# a whole body refuses, and a spent dose keeps its cooldown. The band's own
	# stock is the `Warband` autoload.
	var pack = root.get_node_or_null("Warband")
	check(pack != null, "the warband's books are up, where the medicine is counted")
	if pack != null:
		pack.supplies["bandage"] = 0
		pack.supplies["potion"] = 0
	actor.health = actor.max_health
	check(not actor.try_consume("bandage"), "an empty pack refuses a bandage")
	check(not actor.try_consume("potion"), "an empty pack refuses a draught")

	# With a stocked pack the body's own refusal answers instead, and the dose is
	# kept: a whole body wastes no bandage.
	if pack != null:
		pack.supplies["bandage"] = 3
		pack.supplies["potion"] = 2
	actor.health = actor.max_health
	check(not actor.try_consume("bandage"), "a whole body refuses a bandage")
	check(not actor.try_consume("potion"), "a whole body refuses a draught")
	if pack != null:
		check(pack.supply_count("bandage") == 3 and pack.supply_count("potion") == 2,
			"a refused dose is never spent, got %d bandages / %d potions"
			% [pack.supply_count("bandage"), pack.supply_count("potion")])

	# A wound takes the dose only from a body standing on its feet with stock in
	# the pack, and a dose starts the catalogue's own cooldown on that medicine.
	# This harness has no floor under the body, so the standing gate itself is the
	# refusal here; the clock and the catalogue's figure are checked directly.
	actor.health = actor.max_health * 0.5
	check(float(actor.get("consume_ready").get("bandage", -1.0)) == 0.0,
		"a fresh body has its dressing ready")
	check(is_equal_approx(actor._consume_cooldown("bandage"),
		float(AbilityRules.by_id("bandage").get("cooldown", 0.0))),
		"and the dressing's clock is the catalogue's own, got %.1f"
		% actor._consume_cooldown("bandage"))
	check(is_equal_approx(actor._consume_cooldown("potion"),
		float(AbilityRules.by_id("healing_potion").get("cooldown", 0.0))),
		"as is the draught's, got %.1f" % actor._consume_cooldown("potion"))
	var stocked := 0
	if pack != null:
		stocked = pack.supply_count("bandage")
	check(not actor.try_consume("bandage"),
		"a body with no floor under it takes no dressing")
	if pack != null:
		check(pack.supply_count("bandage") == stocked,
			"and a refused dose is never spent, got %d of %d"
			% [pack.supply_count("bandage"), stocked])
	# A spent dose is gated by the clock the dose itself set.
	actor.consume_ready["bandage"] = 5.0
	check(not actor.try_consume("bandage"),
		"a spent dressing refuses until its clock runs out")
	actor.consume_ready["bandage"] = 0.0
	actor.ability.cancel()
	actor.rig.end_consumable()
	actor.consume_kind = ""
	actor.ability.reset()
	actor.rig.apply_loadout(State.build_loadout("", "", ARMOR))
	actor.stamina = actor.max_stamina


## The HUD reads the possessed body: stamina beside health, and one hotbar tile
## per slot labelled with the key that actually fires it.
func _check_hud(world: Node3D, actor) -> void:
	actor.rig.set_ability_loadout([])
	var hud := HudScript.new()
	hud.name = "Hud"
	world.add_child(hud)
	hud.set_body(actor, "Probe", 1)
	var bar: ProgressBar = hud.stamina_bar()
	check(bar != null, "the HUD owns a stamina bar")
	if bar != null:
		check(bar.max_value > 0.0, "the stamina bar has a positive maximum")
		check(is_equal_approx(bar.max_value, float(actor.max_stamina)),
			"the stamina bar reads the body's maximum, got %.1f vs %.1f"
			% [bar.max_value, float(actor.max_stamina)])
		check(is_equal_approx(bar.value, float(actor.stamina)),
			"the stamina bar reads the body's stamina, got %.1f vs %.1f"
			% [bar.value, float(actor.stamina)])
	var tiles: Array = hud.ability_tiles()
	check(tiles.size() == AbilityRules.MAX_SLOT_COUNT,
		"the HUD builds every key a bar can have, got %d" % tiles.size())
	check(tiles.size() == 10, "that ceiling is ten keys, got %d" % tiles.size())
	for index in tiles.size():
		check(str(tiles[index].name) == "Ability%d" % (index + 1),
			"tile %d is named Ability%d" % [index, index + 1])
	check(tiles[0].visible and tile_id(tiles[0]) == "charge",
		"the granted slot is shown")
	check(tile_key(tiles[0]) == "1", "the first tile is labelled 1, got %s"
		% tile_key(tiles[0]))
	check(tiles[1].visible and tile_id(tiles[1]).is_empty(),
		"a hand with no grant keeps an empty numbered slot")
	var base_shown := 0
	for index in tiles.size():
		if (tiles[index] as Control).visible:
			base_shown += 1
	check(base_shown == AbilityRules.SLOT_COUNT,
		"a five-key bar draws five frames, got %d" % base_shown)

	# Stock steel carries no skill: a dagger and a buckler with no assignment leave
	# every key empty (this dressing carries no starter: `starter_ability` is off).
	actor.rig.apply_loadout(State.build_loadout("dagger_iron", "shield_buckler", ARMOR))
	actor.rig.set_ability_loadout([])
	actor.stamina = actor.max_stamina
	hud.set_body(actor, "Probe", 1)
	check(tile_id(tiles[0]).is_empty() and tile_key(tiles[0]) == "1",
		"stock steel leaves the first key empty and numbered, got %s"
		% tile_id(tiles[0]))

	# Assigned on that dagger-and-shield kit: the dagger skill, the shield skill
	# and an any-hand ward fill the first three keys, and medicine is not on the
	# row at all.
	actor.rig.set_ability_loadout(["backstab", "shield_bash", "energy_shield"])
	hud.set_body(actor, "Probe", 1)
	var equipped_ids := ["backstab", "shield_bash", "energy_shield"]
	check(_granted(tiles) == equipped_ids.size(),
		"three assigned skills fill three keys, got %d" % _granted(tiles))
	for index in equipped_ids.size():
		check(tile_id(tiles[index]) == equipped_ids[index],
			"slot %d draws %s, got %s" % [index, equipped_ids[index],
			tile_id(tiles[index])])
		check(tile_key(tiles[index]) == str(index + 1),
			"tile %d is labelled %d, got %s" % [index, index + 1,
			tile_key(tiles[index])])

	# Every assigned skill takes its own hotbar slot in the order the player laid
	# it, rather than being hidden behind the first.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR))
	actor.rig.set_ability_loadout(["barrage", "triple_volley", "energy_shield", "dash"])
	hud.set_body(actor, "Probe", 1)
	var bow_ids := ["barrage", "triple_volley", "energy_shield", "dash"]
	check(_granted(tiles) == bow_ids.size(),
		"four assigned skills fill four keys, got %d" % _granted(tiles))
	for index in bow_ids.size():
		check(tile_id(tiles[index]) == bow_ids[index],
			"slot %d draws %s, got %s" % [index, bow_ids[index],
			tile_id(tiles[index])])
		check(tile_key(tiles[index]) == str(index + 1),
			"hotbar slot %d keeps its number, got %s" % [index + 1,
			tile_key(tiles[index])])
	check(tile_id(tiles[bow_ids.size()]).is_empty(),
		"the free key stays empty: this dressing carries no starter")
	check(not (tiles[AbilityRules.MAX_SLOT_COUNT - 1] as Control).visible,
		"a key past the five-key bar is hidden, not numbered")

	# A run's upgrade buys more keys: the frames past the five appear, and the
	# ceiling still holds.
	actor.rig.set("ability_extra_slots", 2)
	hud.set_body(actor, "Probe", 1)
	var widened := 0
	for index in tiles.size():
		if (tiles[index] as Control).visible:
			widened += 1
	check(widened == AbilityRules.SLOT_COUNT + 2,
		"two keys bought by the run draw two more frames, got %d" % widened)
	check(tile_key(tiles[AbilityRules.SLOT_COUNT + 1]) == "7",
		"the seventh key is labelled 7, got %s"
		% tile_key(tiles[AbilityRules.SLOT_COUNT + 1]))
	actor.rig.set("ability_extra_slots", 0)
	hud.set_body(actor, "Probe", 1)

	# Hand the later checks a melee kit back: the guard checks below need a blade
	# in the hand, and this test's last kit is a bow.
	actor.rig.apply_loadout(State.build_loadout("dagger_iron", "shield_buckler", ARMOR))
	actor.stamina = actor.max_stamina

	hud.set_body(null, "", -1)
	check(not tiles[0].visible, "no body hides every tile")
	hud.queue_free()


## The non-empty ids a grant list names, in key order.
func _granted_ids(definitions: Array) -> Array:
	var out := []
	for definition in definitions:
		var id := str(definition.get("id", ""))
		if not id.is_empty():
			out.append(id)
	return out


## How many hotbar slots are drawing a skill this frame.
func _granted(tiles: Array) -> int:
	var out := 0
	for tile in tiles:
		if not tile_id(tile).is_empty():
			out += 1
	return out


## RMB in cover is a guard that also leans out; outside cover it is only a
## guard, and releasing either one settles the body back.
func _check_peek(controller, actor) -> void:
	actor.cover.active = true
	controller._unhandled_input(mouse_event(MOUSE_BUTTON_RIGHT, true))
	check(bool(actor.peek_requested), "RMB in cover asks for a peek")
	check(bool(actor.combat.blocking), "RMB in cover keeps the guard up")
	controller._input(mouse_event(MOUSE_BUTTON_RIGHT, false))
	check(not bool(actor.peek_requested), "releasing RMB ends the peek")
	check(not bool(actor.combat.blocking), "releasing RMB drops the guard")

	actor.cover.active = false
	controller._unhandled_input(mouse_event(MOUSE_BUTTON_RIGHT, true))
	check(not bool(actor.peek_requested), "RMB outside cover does not peek")
	check(bool(actor.combat.blocking), "RMB outside cover still guards")
	controller._input(mouse_event(MOUSE_BUTTON_RIGHT, false))
	check(not bool(actor.combat.blocking), "the outside guard is released too")


## The peek side follows the shoulder: `_drive` writes the camera right vector
## into the body, and the same wall is leaned out of on the other side when the
## eye crosses.
func _check_peek_side(controller, actor, world: Node3D) -> void:
	var rig := CameraRig.new()
	rig.name = "Sight"
	world.add_child(rig)
	controller.camera_rig = rig
	actor.cover.active = true
	actor.cover.normal = Vector3(-1.0, 0.0, 0.0)
	rig.yaw = PI * 0.5
	controller._drive(actor)
	check(actor.peek_view_right.distance_to(Vector3(0.0, 0.0, -1.0)) < 0.01,
		"the peek view follows the camera right, got %s" % str(actor.peek_view_right))
	check(int(actor.combat.cover_side) == 1,
		"the peek side is the shoulder side, got %d" % int(actor.combat.cover_side))
	rig.yaw = -PI * 0.5
	controller._drive(actor)
	check(actor.peek_view_right.distance_to(Vector3(0.0, 0.0, 1.0)) < 0.01,
		"the peek view crosses with the shoulder, got %s" % str(actor.peek_view_right))
	check(int(actor.combat.cover_side) == -1,
		"the peek side crosses with the shoulder, got %d" % int(actor.combat.cover_side))
	actor.cover.active = false
	controller.camera_rig = null
	rig.queue_free()


## The scene half: binding is idempotent, a cue on the authority spawns one
## projectile, and a replica's cue is ignored.
func _check_ability_node(world: Node3D, actor, controller) -> void:
	var abilities = AbilitiesScript.new()
	abilities.name = "WarbandAbilities"
	world.add_child(abilities)
	abilities.setup(world, controller)
	abilities.bind_body(actor)
	abilities.bind_body(actor)
	check(abilities.bound_bodies().size() == 1,
		"binding one body twice leaves one connection, got %d"
		% abilities.bound_bodies().size())

	# A stock bow with an empty equipped list carries nothing: slot 0 is empty
	# and its key starts nothing.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR))
	actor.rig.set_ability_loadout([])
	check(AbilityRules.definition_for(actor.rig, 0).is_empty(), "a stock shortbow grants no skill")
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true
	check(not bool(actor.try_ability(0).get("ok", true)), "the stock bow's key starts nothing")

	# Equipped, the same bow fires the Barrage: the whole fan leaves on the press
	# itself - no draw, no nock, no wind-up to wait for.
	actor.rig.set_ability_loadout(["barrage"])
	check(str(AbilityRules.definition_for(actor.rig, 0).get("id", "")) == "barrage",
		"the equipped shortbow grants the Barrage")
	var outcome: Dictionary = actor.try_ability(0)
	check(bool(outcome.get("ok", false)), "the Barrage starts")
	check(abilities.missiles().size() == 6,
		"the whole barrage leaves on the press, got %d" % abilities.missiles().size())

	# A body that does not own the simulation must not spawn a second one, even
	# if its runner is still holding the skill.
	actor.authoritative = false
	actor.ability.cue.emit("barrage", "shot", 1)
	check(abilities.missiles().size() == 6,
		"a replica's cue spawns nothing, got %d" % abilities.missiles().size())
	actor.authoritative = true
	actor.ability.cancel()

	# A staff cast resolves through the same node: the spell projectile is the
	# seventh missile, and its blast is wired to the body's own combat.
	actor.rig.apply_loadout(State.build_loadout("staff_fire", "", ARMOR))
	actor.rig.set_ability_loadout([])
	actor.rig.starter_ability = AbilityRules.STARTER_GRANT
	check(str(AbilityRules.definition_for(actor.rig, 0).get("id", "")) == "fireball",
		"the starter spell rides any staff")
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true
	check(bool(actor.try_ability(0).get("ok", false)), "the Fireball starts")
	actor.ability.advance(0.6)
	check(abilities.missiles().size() == 7,
		"the cast cue spawns the spell, got %d missiles" % abilities.missiles().size())
	actor.ability.cancel()

	# A bow skill is castable while the string is being drawn. The activation
	# takes the body into the skill's own bow beat; the half draw is dropped.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR))
	actor.rig.set_ability_loadout(["barrage"])
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true
	actor.rig.begin_draw()
	check(str(actor.rig.phase) == "DRAWING",
		"the bow is drawing before the skill press (%s)" % str(actor.rig.phase))
	var drawn: Dictionary = actor.try_ability(0)
	check(bool(drawn.get("ok", false)),
		"a bow skill starts while the string is drawn: %s"
		% str(drawn.get("message", "")))
	check(str(actor.rig.phase) == "ABILITY",
		"and the skill takes the body into its own beat (%s)" % str(actor.rig.phase))
	actor.ability.cancel()

	# The previous shot's own recovery is not a lock on the key either: a bow
	# skill fires from the bow's beat instead of waiting for it to finish.
	actor.ability.cooldowns.fill(0.0)
	actor.stamina = actor.max_stamina
	actor.rig.phase = "RECOVER"
	actor.rig._phase_time = 0.12
	var recovering: Dictionary = actor.try_ability(0)
	check(bool(recovering.get("ok", false)),
		"a bow skill starts during the bow's recovery: %s"
		% str(recovering.get("message", "")))
	check(str(actor.rig.phase) == "ABILITY",
		"and the shot takes the body out of the recovery (%s)" % str(actor.rig.phase))
	actor.ability.cancel()
	_check_starter_venom(world, actor, abilities)
	await _check_fire_ray(world, actor, abilities)
	abilities.queue_free()


## The starter bow's venom: the shot's own arrow carries the dose, a landed shaft
## lays it on the body it opened, and the clock pays 5 a second for 5 s whether or
## not the skill is still being performed.
func _check_starter_venom(world: Node3D, actor, abilities) -> void:
	var victim := fighter(world, 6, Vector3(4.0, 0.0, -4.0))
	victim.health = 200.0
	victim.max_health = 200.0
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR))
	actor.rig.set_ability_loadout([])
	actor.rig.starter_ability = AbilityRules.STARTER_GRANT
	actor.ability.cancel()
	actor.ability.cooldowns.fill(0.0)
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true

	var effect: Dictionary = AbilityRules.by_id("snap_shot").get("effect", {})
	check(is_equal_approx(float(effect.get("poison_dps", 0.0)), 5.0),
		"the Snap Shot authors 5 dps, got %s" % str(effect.get("poison_dps")))
	check(str(AbilityRules.definition_for(actor.rig, 0).get("id", "")) == "snap_shot",
		"a bare bow draws the Snap Shot as its starter")
	# The earlier beats' shafts are still tracked; this check counts only its own.
	abilities._missiles.clear()
	var started: Dictionary = actor.try_ability(0)
	check(bool(started.get("ok", false)), "the Snap Shot starts: %s"
		% str(started.get("message", "")))
	var missiles: Array = abilities.missiles()
	check(missiles.size() == 1, "one shaft leaves, got %d" % missiles.size())
	if missiles.size() == 1:
		var arrow = missiles[0]
		check(arrow.on_hit.is_valid(), "the shaft carries an on-hit")
		var before: float = victim.health
		arrow.on_hit.call(victim, victim.global_position, 7.0, false, 1.0)
		for _step in 20:
			abilities._physics_process(0.25)
		var lost: float = before - victim.health
		check(absf(lost - 25.0) < 0.75,
			"5 dps for 5 s took %.2f, expected 25" % lost)
		var settled: float = victim.health
		for _step in 8:
			abilities._physics_process(0.25)
		check(is_equal_approx(victim.health, settled),
			"the dose stops when its clock runs out")
		# A second hit refreshes the dose; it never stacks a twin on the body.
		var rest: float = victim.health
		arrow.on_hit.call(victim, victim.global_position, 7.0, false, 1.0)
		arrow.on_hit.call(victim, victim.global_position, 7.0, false, 1.0)
		for _step in 20:
			abilities._physics_process(0.25)
		check(absf((rest - victim.health) - 25.0) < 0.75,
			"two doses on one body still pay 25, got %.2f"
			% (rest - victim.health))
	abilities._venoms.clear()
	actor.ability.cancel()
	actor.ability.cooldowns.fill(0.0)
	victim.queue_free()


## Fire Ray is the one held spell: the cue stands a beam, the beam pays its DPS
## on a fifth-second tick to every body in its line, ignores a body outside it,
## stops at a wall, and stops the same frame its caster's cast does. The bodies
## stand on the mob layer (`2`), which is what the scene's target mask selects.
func _check_fire_ray(world: Node3D, actor, abilities) -> void:
	actor.rig.apply_loadout(State.build_loadout("staff_fire", "", ARMOR))
	actor.rig.set_ability_loadout(["fire_ray"])
	actor.rig.starter_ability = ""
	actor.ability.cancel()
	actor.ability.cooldowns.fill(0.0)
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true
	# The world adopts a body against the wood's mobs (layer 2); a squadmate on
	# layer 4 is deliberately not in the mask.
	actor.combat.target_mask = 2
	check(str(AbilityRules.definition_for(actor.rig, 0).get("id", "")) == "fire_ray",
		"a staff draws Fire Ray on its key")
	var effect: Dictionary = AbilityRules.by_id("fire_ray").get("effect", {})
	check(str(effect.get("kind", "")) == "beam",
		"Fire Ray is the beam effect (%s)" % str(effect.get("kind", "")))
	check(is_equal_approx(float(effect.get("damage_scale", 0.0)), 1.0),
		"its damage share is a per-second figure (%s)"
			% str(effect.get("damage_scale")))

	var near := fighter(world, 7, Vector3(0.0, 0.0, -4.0))
	var far := fighter(world, 8, Vector3(0.0, 0.0, -8.0))
	var side := fighter(world, 9, Vector3(3.0, 0.0, -4.0))
	for victim in [near, far, side]:
		# A mob's layer, not a warband body's: the scene's target mask is 1 | 2
		# and a squadmate (layer 4) is deliberately not in it.
		victim.collision_layer = 2
		victim.health = 300.0
		victim.max_health = 300.0
	actor.combat.aim_point = Vector3(0.0, 1.2, -8.0)
	actor.combat.update_aim()
	await physics_frame

	abilities._beams.clear()
	abilities._missiles.clear()
	var started: Dictionary = actor.try_ability(0)
	check(bool(started.get("ok", false)), "Fire Ray starts: %s"
		% str(started.get("message", "")))
	var rays: Array = abilities.beams()
	check(rays.size() == 1, "the beam cue stands one ray (%d)" % rays.size())
	if rays.is_empty():
		actor.ability.cancel()
		_clear_fire_ray_probes([near, far, side], null)
		return
	var ray = rays[0]
	ray.set_physics_process(false)
	# Five ticks of a 50 dps ray at 0.2 s: fifty points off each body in the line.
	for _tick in 5:
		ray._physics_process(0.2)
	check(ray.beam_length > 7.0,
		"the ray reaches down the line (%.2f m)" % float(ray.beam_length))
	check(absf((300.0 - near.health) - 50.0) < 3.0,
		"the near body takes five ticks (%.2f)" % (300.0 - near.health))
	check(absf((300.0 - far.health) - 50.0) < 3.0,
		"so does the far body in the same line (%.2f)" % (300.0 - far.health))
	check(is_equal_approx(side.health, 300.0),
		"a body off the line is not in the beam (%.2f)" % side.health)
	# The sixth tick ends the cast's 1.2 s clock and the node with it.
	ray._physics_process(0.2)
	check(ray.is_queued_for_deletion(), "the ray frees itself at the end of the cast")
	actor.ability.cancel()
	await process_frame
	abilities._beams.clear()

	# A wall stops the ray: the near body is still burnt, the far one is not.
	var wall := StaticBody3D.new()
	wall.name = "FireRayWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 4.0, 0.4)
	var collider := CollisionShape3D.new()
	collider.shape = box
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = Vector3(0.0, 2.0, -6.0)
	near.health = 300.0
	far.health = 300.0
	side.health = 300.0
	actor.ability.cooldowns.fill(0.0)
	actor.stamina = actor.max_stamina
	actor.combat.grounded = true
	actor.combat.aim_point = Vector3(0.0, 1.2, -8.0)
	await physics_frame
	var capped: Dictionary = actor.try_ability(0)
	check(bool(capped.get("ok", false)), "Fire Ray starts again at the wall: %s"
		% str(capped.get("message", "")))
	var second: Array = abilities.beams()
	check(second.size() == 1, "one fresh ray at the wall (%d)" % second.size())
	if not second.is_empty():
		var wall_ray = second[0]
		wall_ray.set_physics_process(false)
		for _tick in 5:
			wall_ray._physics_process(0.2)
		check(wall_ray.beam_length < 6.0,
			"the wall caps the ray (%.2f m)" % float(wall_ray.beam_length))
		check(absf((300.0 - near.health) - 50.0) < 3.0,
			"the body before the wall still burns (%.2f)" % (300.0 - near.health))
		check(is_equal_approx(far.health, 300.0),
			"the body behind the wall does not (%.2f)" % far.health)
		wall_ray._physics_process(0.2)
		check(wall_ray.is_queued_for_deletion(),
			"the wall's ray frees itself too")
	actor.ability.cancel()
	_clear_fire_ray_probes([near, far, side], wall)


func _clear_fire_ray_probes(victims: Array, extra: Node) -> void:
	for victim in victims:
		if is_instance_valid(victim):
			victim.queue_free()
	if is_instance_valid(extra):
		extra.queue_free()
