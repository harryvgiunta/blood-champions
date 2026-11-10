extends SceneTree
## A body fights with its hands, not its feet.
##
## The bow is drawn, held and loosed while the body sprints and while it is in the
## air, a blade comes up to throw and leaves the hand in the air, and a skill
## starts at a run, in the air and survives a leap without losing the sprint.
## What is checked is the real path a player takes: `Combat`'s own gates, the
## rig's own phase machine, the ability runner's refusal list and the world's
## projectile list - so a `grounded` check coming back, a jump cancelling the
## draw, or a skill dropping the run fails here instead of in a fight.

const WORLD = "res://scenes/warband_world.tscn"
const AbilityRules = preload("res://scripts/ability_rules.gd")
const TEST_STATE := "user://mobile_fire_state.json"
const TEST_WARBAND := "user://mobile_fire_warband.json"
const ARMOR := {"head": 0, "chest": 0, "hands": 0, "legs": 0, "feet": 0}

var game
var body
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
	await _open_world()
	await _check_airborne_bow()
	await _check_running_bow()
	await _check_draw_starts_on_the_move()
	await _check_abilities_on_the_move()
	await _check_airborne_throw()
	_finish()


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
	check(game.bodies.size() >= 1, "the world stands a body up")
	if game.bodies.size() < 1:
		return
	body = game.bodies[0]
	for _frame in 6:
		await physics_frame
	check(str(body.rig.weapon) == "bow", "the body carries a bow in the square")


## A draw held when the body jumps is still a draw in the air, and the shaft it
## looses leaves from the air.
func _check_airborne_bow() -> void:
	await _wait_ready()
	body.combat.set_aim(body.global_position + Vector3(0.0, 1.3, -30.0))
	check(bool(body.combat.begin_draw()), "the bow draws on the ground")
	for _frame in 18:
		await physics_frame
	body.press_jump(false)
	check(str(body.rig.phase) in ["DRAWING", "HOLDING"],
		"the jump does not cancel the draw (%s)" % str(body.rig.phase))
	var airborne := false
	for _frame in 30:
		await physics_frame
		if not body.is_on_floor():
			airborne = true
			break
	check(airborne, "the body leaves the floor")
	if airborne:
		check(str(body.rig.phase) in ["DRAWING", "HOLDING"],
			"the string is still back in the air (%s)" % str(body.rig.phase))
		var before: int = game.projectiles.size()
		body.combat.release_draw()
		var fired := false
		for _frame in 6:
			await physics_frame
			if game.projectiles.size() > before:
				fired = true
				break
		check(fired, "the arrow leaves the bow in the air")
	for _frame in 45:
		await physics_frame


## A draw at a run: the combat is told the same motion a sprinting body reports
## every tick, and the shot must still come out.
func _check_running_bow() -> void:
	await _wait_ready()
	body.combat.set_aim(body.global_position + Vector3(0.0, 1.3, -30.0))
	check(bool(body.combat.begin_draw()), "the bow draws on the run")
	var running := false
	for _frame in 24:
		body.combat.set_motion(Vector3(0.0, 0.0, -5.5), true, true)
		if str(body.combat.movement_mode) == "RUNNING":
			running = true
		await physics_frame
	check(running, "the combat is told the body is running")
	var before: int = game.projectiles.size()
	body.combat.release_draw()
	var fired := false
	for _frame in 6:
		await physics_frame
		if game.projectiles.size() > before:
			fired = true
			break
	check(fired, "the arrow leaves the bow at a run")
	body.combat.set_motion(Vector3.ZERO, false, true)
	for _frame in 20:
		await physics_frame


## A fresh draw started while the body is already moving: at a sprint and in
## the air. Holding a draw across a leap is the previous check; this one is the
## press that starts it, which is the state the player actually complains about.
func _check_draw_starts_on_the_move() -> void:
	# The world's own driver reads the keyboard; the test holds the walk itself.
	game.controller.input_enabled = false
	await _wait_ready()
	await _wait_floor()
	body.stamina = body.max_stamina
	var sprinted := false
	for _frame in 40:
		body.update_input(Vector2(0.0, -1.0), true)
		await physics_frame
		if bool(body._last_running):
			sprinted = true
			break
	check(sprinted, "the body reaches a sprint before the draw")
	body.combat.set_aim(body.global_position + Vector3(0.0, 1.3, -30.0))
	check(bool(body.combat.begin_draw()), "the bow starts to draw at a sprint")
	var held_run := false
	for _frame in 12:
		body.update_input(Vector2(0.0, -1.0), true)
		await physics_frame
		if str(body.rig.phase) in ["DRAWING", "HOLDING"] and bool(body._last_running):
			held_run = true
	check(held_run, "the sprint and the draw hold together")
	body.combat.release_draw()
	for _frame in 20:
		await physics_frame
	# A draw started in the air: no floor to plant the feet on, no reason to
	# refuse the string.
	await _wait_ready()
	await _wait_floor()
	body.press_jump(false)
	var airborne := false
	for _frame in 30:
		await physics_frame
		if not body.is_on_floor():
			airborne = true
			break
	check(airborne, "the body leaves the floor before the draw starts")
	if airborne:
		body.combat.set_aim(body.global_position + Vector3(0.0, 1.3, -30.0))
		check(bool(body.combat.begin_draw()), "the bow starts to draw in the air")
		check(str(body.rig.phase) in ["DRAWING", "HOLDING"],
			"the fresh string is drawn in the air (%s)" % str(body.rig.phase))
		body.combat.release_draw()
	for _frame in 60:
		await physics_frame


## A skill is done with the hands: the key starts it at a sprint, in the air and
## survives a leap, and the sprint keeps running underneath it.
func _check_abilities_on_the_move() -> void:
	await _wait_ready()
	await _wait_floor()
	var state = root.get_node("PlayerState")
	body.rig.apply_loadout(state.build_loadout("bow_short", "", ARMOR))
	body.rig.set_ability_loadout(["barrage"])
	await _wait_ready()
	var slot := _ability_slot("barrage")
	check(slot >= 0, "the anointed shortbow grants the Barrage")
	if slot < 0:
		return
	# --- the key at a sprint
	body.stamina = body.max_stamina
	body.ability.cooldowns.fill(0.0)
	var sprinted := false
	for _frame in 40:
		body.update_input(Vector2(0.0, -1.0), true)
		await physics_frame
		if bool(body._last_running):
			sprinted = true
			break
	check(sprinted, "the body reaches a sprint before the skill")
	var started: Dictionary = body.try_ability(slot)
	check(bool(started.get("ok", false)),
		"a sprinting body starts the Barrage (%s)" % str(started.get("message", "")))
	var sprint_kept := false
	for _frame in 10:
		body.update_input(Vector2(0.0, -1.0), true)
		await physics_frame
		if body.ability.active and bool(body._last_running):
			sprint_kept = true
	check(sprint_kept, "the sprint keeps running under the skill")
	# --- the leap taken mid-skill
	body.press_jump(false)
	check(bool(body.jump_requested) or bool(body.roll.active),
		"a leap is taken during the skill")
	check(body.ability.active, "the leap does not cancel the skill")
	var airborne := false
	for _frame in 30:
		await physics_frame
		if not body.is_on_floor():
			airborne = true
			break
	check(airborne, "the body leaves the floor with the skill running")
	check(body.ability.active and str(body.rig.phase) == "ABILITY",
		"the skill is still performed in the air (%s)" % str(body.rig.phase))
	for _frame in 90:
		await physics_frame
	# --- the key in the air
	await _wait_ready()
	await _wait_floor()
	body.stamina = body.max_stamina
	body.ability.cooldowns.fill(0.0)
	body.press_jump(false)
	airborne = false
	for _frame in 30:
		await physics_frame
		if not body.is_on_floor():
			airborne = true
			break
	check(airborne, "the body leaves the floor before the skill starts")
	if airborne:
		var air_start: Dictionary = body.try_ability(slot)
		check(bool(air_start.get("ok", false)),
			"the Barrage starts in the air (%s)" % str(air_start.get("message", "")))
		check(body.ability.active and str(body.rig.phase) == "ABILITY",
			"the airborne skill is being performed (%s)" % str(body.rig.phase))
	for _frame in 90:
		await physics_frame


func _ability_slot(id: String) -> int:
	var grants: Array = AbilityRules.granted(body.rig)
	for index in grants.size():
		if str(grants[index].get("id", "")) == id:
			return index
	return -1


## The other hand: a blade raised to throw survives the same jump.
func _check_airborne_throw() -> void:
	await _wait_ready()
	var merc := int(game.controller.merc_of(body))
	game.roguelite._dress_weapon(body, merc, "sword_short")
	check(str(body.rig.weapon) == "sword", "the body holds a blade")
	body.combat.set_aim(body.global_position + Vector3(0.0, 1.3, -30.0))
	check(bool(body.combat.begin_throw()), "the blade comes up to throw")
	for _frame in 8:
		await physics_frame
	body.press_jump(false)
	check(str(body.rig.phase) in ["T_DRAW", "T_HOLD"],
		"the jump does not cancel the throw (%s)" % str(body.rig.phase))
	var airborne := false
	for _frame in 30:
		await physics_frame
		if not body.is_on_floor():
			airborne = true
			break
	check(airborne, "the body leaves the floor with the blade raised")
	if airborne:
		var before: int = game.projectiles.size()
		body.combat.release_throw()
		var thrown := false
		for _frame in 6:
			await physics_frame
			if game.projectiles.size() > before:
				thrown = true
				break
		check(thrown, "the blade leaves the hand in the air")


func _wait_ready() -> void:
	for _frame in 150:
		if str(body.rig.phase) == "READY":
			return
		await physics_frame


func _wait_floor() -> void:
	for _frame in 120:
		if body.is_on_floor():
			return
		await physics_frame


func _finish() -> void:
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	print("MOBILE_FIRE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
