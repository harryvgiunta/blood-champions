extends SceneTree
## The guard is a stance of the arm, not of the feet.
##
## A raised blade is held while the body walks, runs and slides, it survives a
## leap, and one can be raised in the air - where it still stops a front blow and
## still reads as a guard on the skeleton rather than a planted stance floating
## with the body. What still refuses it is a committed roll (a flip has no arms
## to set), a stagger, and hands busy with a swing, a draw, a throw or a skill.
##
## This is the contract `Combat.start_block` and `Combat.stop_for_airborne` keep,
## driven through a real body on real ground with a live input stream.

const Actor = preload("res://scripts/warband/warband_body.gd")
const Combat = preload("res://scripts/combat.gd")
const Stamina = preload("res://scripts/stamina.gd")

const STEP := 1.0 / 60.0
const FORWARD := Vector2(0.0, 1.0)
const WALK_SPEED := 5.5
const SPRINT_SPEED := 8.5

var checks := 0
var failures := 0
var world: Node3D
var actor

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("GUARD_STATES_FAIL  ", message)

func tick(count: int, direction: Vector2 = Vector2.ZERO, running: bool = false) -> void:
	for index in count:
		actor.rig.advance_animation(STEP)
		actor.update_input(direction,running)
		actor.step(STEP,[actor])

func speed() -> float:
	return Vector2(actor._last_motion.x,actor._last_motion.z).length()

## The blade's own placement, measured off the skeleton: a hilt out in front of
## the chest with the tip over the head is a guard, whatever clip is playing.
func guard_reach() -> Dictionary:
	var flat: Vector3 = -actor.rig.global_basis.z
	flat.y = 0.0
	flat = flat.normalized()
	var base: Vector3 = actor.rig.get_blade_base("right")
	var tip: Vector3 = actor.rig.get_blade_tip("right")
	return {"hilt": (base-actor.global_position).dot(flat),
		"tip": tip.y-actor.global_position.y,
		"flat": (tip-base).normalized().y}

func build_world() -> void:
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80,1,80)
	shape.shape = box
	shape.position = Vector3(0,-0.5,0)
	ground.add_child(shape)
	world.add_child(ground)
	actor = Actor.new()
	actor.slot = 0
	actor.authoritative = true
	world.add_child(actor)
	actor.configure(1,"Guard",Vector3.ZERO)
	actor.set_physics_process(false)
	actor.rig.set_physics_process(false)
	actor.rig.set_sword(1)
	actor.rig.set_weapon("sword")

func run() -> void:
	build_world()
	await physics_frame
	tick(40)
	check(actor.is_on_floor(),"The body stands on the ground for the whole rule")

	# --- the feet on the ground ------------------------------------------------
	actor.stamina = Stamina.MAX
	tick(10,FORWARD)
	check(actor.combat.start_block(Vector3.FORWARD),"A guard goes up on the move")
	tick(30,FORWARD)
	check(actor.combat.blocking and speed() > WALK_SPEED-0.2,
		"A walk carries the raised guard (%.2f m/s)" % speed())
	actor.stamina = Stamina.MAX
	tick(30,FORWARD,true)
	check(actor.combat.blocking and speed() > SPRINT_SPEED-0.2,
		"A sprint carries it too (%.2f m/s)" % speed())

	# --- the leap -------------------------------------------------------------
	actor.press_jump(false)
	tick(8,FORWARD,true)
	check(not actor.is_on_floor(),"The body is off the floor")
	check(actor.combat.blocking and actor.rig.is_blocking(),
		"A leap keeps the guard the body already had up")
	check(actor.rig._display_clip.begins_with("Jump"),
		"and its legs are the air's, not a planted guard stance (%s)" % actor.rig._display_clip)
	var airborne: Dictionary = guard_reach()
	check(float(airborne["hilt"]) > 0.25 and float(airborne["tip"]) > 1.0,
		"The blade is held out in front with its tip over the head in the air (%.2f/%.2f)"
			% [float(airborne["hilt"]),float(airborne["tip"])])
	# The guard is a defence in the air, not a pose that only plays: the same
	# front blow a standing guard stops is stopped here.
	var stopped: int = actor.receive_melee(12.0,99,actor.global_position-Vector3(0,0,1.2))
	check(stopped == Combat.DEFENSE_BLOCK,"An airborne guard stops a front melee blow")
	check(actor.combat.blocking,"and a stopped blow leaves it up, on the ground or not")

	# --- the way down ---------------------------------------------------------
	tick(60)
	check(actor.is_on_floor(),"The body lands")
	actor.stamina = Stamina.MAX
	check(actor.combat.start_block(Vector3.FORWARD),"The guard goes up again on landing")
	tick(20)
	check(actor.combat.blocking,"and holds on the ground")

	# --- raised in the air ----------------------------------------------------
	actor.combat.stop_block()
	actor.press_jump(false)
	tick(8,FORWARD,true)
	check(not actor.is_on_floor(),"A second leap is under way")
	actor.stamina = Stamina.MAX
	check(actor.combat.start_block(Vector3.FORWARD),"A guard goes up in the air")
	tick(6,FORWARD,true)
	check(actor.combat.blocking and actor.rig.is_blocking(),
		"and is held there for the rest of the fall")

	# --- the sprint slide -----------------------------------------------------
	tick(60)
	actor.stamina = Stamina.MAX
	tick(40,FORWARD,true)
	actor.set_crouch(true)
	tick(2,FORWARD,true)
	check(actor.slide.active,"The sprint crouch starts a slide")
	check(actor.combat.start_block(Vector3.FORWARD),"A guard goes up in the slide")
	tick(10,FORWARD,true)
	check(actor.slide.active and actor.combat.blocking,
		"and the slide carries it")
	check(actor.rig._display_clip.begins_with("Sword_Block"),
		"with the guard's own upper body (%s)" % actor.rig._display_clip)

	# --- a press that lands in another action ---------------------------------
	actor.set_crouch(false)
	tick(60)
	actor.stamina = Stamina.MAX
	check(actor.combat.begin_melee("right","diagonal_right"),"A cut starts")
	tick(4,FORWARD)
	check(actor.rig.is_melee(),"and is still playing when the guard is pressed")
	actor.set_block(true,Vector3.FORWARD)
	check(actor.combat.blocking and actor.rig.is_blocking(),
		"A guard pressed during a cut goes up at once")
	check(not actor.rig.is_melee(),"and the cut it interrupted is over")
	actor.set_block(false,Vector3.ZERO)
	tick(10)
	# The roll is the one thing a guard cannot interrupt, so the press waits for it
	# instead of being swallowed.
	actor.stamina = Stamina.MAX
	actor.press_jump(true)
	tick(3)
	check(actor.roll.active,"A committed roll is under way")
	check(not actor.combat.start_block(Vector3.FORWARD),
		"A committed roll still refuses a guard: a flip has no arms to set")
	actor.stamina = Stamina.MAX
	actor.set_block(true,Vector3.FORWARD)
	check(not actor.combat.blocking,"and the roll is still owed its frames")
	for step in 50:
		tick(1,FORWARD)
		if actor.combat.blocking:
			break
	check(actor.combat.blocking,"A press made during the roll is honoured the frame it ends")
	actor.set_block(false,Vector3.ZERO)
	check(not actor.combat.blocking,"releasing it drops the guard again")

	world.queue_free()
	await process_frame
	print("GUARD_STATES_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
