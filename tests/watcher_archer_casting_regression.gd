extends SceneTree
## The Hollow's casting archers: every archer in a wave draws one fire rite from
## level two on, and the rite really leaves the bow body as a spell.
##
## What this owns: the level-2 gate on the archer's spec; the shared rite pool
## (Fire Ray included); the archer's own damage family (91); the windup resolving
## into the shared `fire_ray.gd` beam; and that beam burning every party body in
## its line while leaving a body beside it untouched.

const ArcherScript = preload("res://scripts/warband/watcher_archer.gd")
const CasterScript = preload("res://scripts/warband/watcher_caster.gd")
const DirectorScript = preload("res://scripts/roguelite/run_director.gd")
const DemonFireScript = preload("res://scripts/warband/demon_fire.gd")

const SAFE_OFFSET := Vector3(5000.0, 0.0, 5000.0)

var checks := 0
var failures := 0


class FakeWorld extends Node3D:
	var bodies: Array = []
	var guards: Array = []


class Target extends CharacterBody3D:
	var alive := true
	var downed := false
	var health := 100.0
	var hits: Array[float] = []
	var sources: Array[int] = []

	func take_damage(amount: float, source_id: int, _headshot: bool = false) -> void:
		hits.append(amount)
		sources.append(source_id)
		health = maxf(0.0, health - amount)

	func note_attacker(_who: Node3D) -> void:
		pass

	func get_aim_position() -> Vector3:
		return global_position + Vector3.UP * 1.2

	func total() -> float:
		var sum := 0.0
		for hit in hits:
			sum += hit
		return sum


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ARCHER_CAST_FAIL  ", message)


func run() -> void:
	_check_pool()
	_check_level_gate()
	_check_spawn()
	await _check_cast()
	print("WATCHER_ARCHER_CASTING_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## The pool is the Hollow's own: the three fire rites plus the player's Fire Ray.
func _check_pool() -> void:
	var pool: Array = DemonFireScript.RITE_POOL
	check(pool.has("fire_ray"), "Fire Ray is in the shared rite pool (%s)" % str(pool))
	check(CasterScript.SPELL_POOL == pool,
		"the caster and the archer draw from one pool")


## Wave one is a bow; from wave two every archer has drawn a rite, and only a
## row in the shared pool. The gate is the picker's, not a per-body afterthought.
func _check_level_gate() -> void:
	var director = DirectorScript.new()
	director.biome_id = "wilderness"
	director._rng.seed = 2026
	director._rite_rng.seed = 2026
	director.level = 1
	var early := 0
	for _roll in 400:
		var spec: Dictionary = director._pick_spec(false)
		if str(spec.get("kind", "")) != "archer":
			continue
		early += 1
		check(str(spec.get("spell", "")).is_empty(),
			"a level-one archer carries no rite (%s)" % str(spec.get("spell", "")))
	check(early > 0, "the level-one pool still fields archers (%d)" % early)
	director.level = 2
	var late := 0
	var rites := {}
	for _roll in 400:
		var spec: Dictionary = director._pick_spec(false)
		if str(spec.get("kind", "")) != "archer":
			continue
		late += 1
		var rite := str(spec.get("spell", ""))
		check(DemonFireScript.RITE_POOL.has(rite),
			"a level-two archer's rite is from the pool (%s)" % rite)
		var row: Dictionary = DemonFireScript.spell(rite)
		check(float(row.get("range", 0.0)) >= float(ArcherScript.HOLD_NEAR),
			"the archer's rite reaches its own near ring (%s at %.1f m)"
			% [rite, float(row.get("range", 0.0))])
		rites[rite] = true
	check(late > 0, "the level-two pool fields archers (%d)" % late)
	check(rites.has("fire_ray"),
		"Fire Ray is rolled onto an archer (%s)" % str(rites.keys()))
	check(not rites.has("hellfire_breath"),
		"the 7 m cone is never dealt to the 8-16 m archer (%s)" % str(rites.keys()))
	# The boss at the end of the block is an archer too: the same picker hands it
	# a rite (the direct boss spec does not pass through the normal pool draw).
	director.level = 10
	var boss: Dictionary = director._assign_rite({"kind": "archer"})
	check(DemonFireScript.RITE_POOL.has(str(boss.get("spell", ""))),
		"the boss archer draws a rite (%s)" % str(boss.get("spell", "")))
	director.free()


## The director's build path hands the archer the spec's rite and leaves its own
## bow damage family on the fire it casts.
func _check_spawn() -> void:
	var director = DirectorScript.new()
	var world := FakeWorld.new()
	world.name = "ArcherSpawnWorld"
	root.add_child(world)
	var quarry := CharacterBody3D.new()
	quarry.position = Vector3(0.0, 0.0, -8.0)
	world.add_child(quarry)
	world.bodies.append(quarry)
	director.world = world
	director._spawn_spec({"kind": "archer", "species": "hollow_warden",
		"cost": 4.0, "spell": "fire_ray"}, Vector3.ZERO)
	check(director._mobs.size() == 1, "the director files the archer (%d)" % director._mobs.size())
	if not director._mobs.is_empty():
		var archer = director._mobs[0]
		var spells: Array = archer.fire_spells()
		check(spells.size() == 1 and str(spells[0]) == "fire_ray",
			"the archer carries the spec's rite (%s)" % str(spells))
		check(int(archer.fire_damage_source()) == int(ArcherScript.DAMAGE_SOURCE),
			"the archer's fire books its own family (%d)"
			% int(archer.fire_damage_source()))
		check(str(archer.name).begins_with("RogueA_"),
			"the run names its archers apart from its casters (%s)" % str(archer.name))
	director.free()
	world.queue_free()


## The windup resolves into the shared beam; it burns the body in the line and
## not the one beside it, and books the archer's own 91.
func _check_cast() -> void:
	var world := Node3D.new()
	world.name = "ArcherCastWorld"
	root.add_child(world)
	var archer = ArcherScript.new()
	archer.name = "ArcherProbe"
	archer.mob_id = "hollow_warden"
	archer.position = Vector3.ZERO
	world.add_child(archer)
	archer.global_position = Vector3.ZERO
	archer.safe_center = SAFE_OFFSET
	archer.set_physics_process(false)
	archer.stand_watch()
	archer.set_fire_spell("fire_ray")
	var hit := Target.new()
	hit.position = Vector3(0.0, 0.0, -6.0)
	world.add_child(hit)
	hit.global_position = Vector3(0.0, 0.0, -6.0)
	var aside := Target.new()
	aside.position = Vector3(4.0, 0.0, -6.0)
	world.add_child(aside)
	aside.global_position = Vector3(4.0, 0.0, -6.0)
	archer.player = hit
	archer.targets.clear()
	archer.targets.append(hit)
	archer.targets.append(aside)
	archer._target = hit
	await physics_frame
	var row: Dictionary = DemonFireScript.spell("fire_ray")
	archer._begin_cast("fire_ray", row, Vector3(0.0, 0.0, -1.0))
	check(archer.casting(), "the archer winds the rite up")
	archer._advance_cast(float(row.get("windup", 0.85)) + 0.05)
	var beam: Node3D = archer.cast_beam()
	check(beam != null and is_instance_valid(beam),
		"the archer's windup resolves into a standing ray")
	if beam != null:
		beam.set_physics_process(false)
		for _tick in 8:
			beam._physics_process(0.2)
		check(absf(hit.total() - 30.0) < 0.01,
			"the archer's ray burns 30 through the body in line (%.2f)" % hit.total())
		check(is_equal_approx(aside.total(), 0.0),
			"the body beside the archer's line is untouched (%.2f)" % aside.total())
		check(hit.sources.all(func(source: int) -> bool:
			return source == int(ArcherScript.DAMAGE_SOURCE)),
			"the archer's ray books the archer's family (%s)" % str(hit.sources))
		check(beam.is_queued_for_deletion(), "the archer's ray frees itself")
	archer.queue_free()
	hit.queue_free()
	aside.queue_free()
	world.queue_free()
