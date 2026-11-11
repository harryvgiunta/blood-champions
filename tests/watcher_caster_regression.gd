extends SceneTree
## The Hollow's caster: a watcher that carries one rolled fire rite from level 5.
##
## What this owns: the one-spell kit and its pool (Fire Ray included); the level
## gate that keeps it out of waves 1-4 and lets it into wave 5; the rite being
## rolled into the spec every peer reads; the windup resolving into the shared
## `fire_ray.gd` beam; and that beam burning every party body in its line, not
## just the quarry, while leaving a body off the line untouched.

const CasterScript = preload("res://scripts/warband/watcher_caster.gd")
const DirectorScript = preload("res://scripts/roguelite/run_director.gd")
const DemonFireScript = preload("res://scripts/warband/demon_fire.gd")

const SAFE_OFFSET := Vector3(5000.0, 0.0, 5000.0)

var checks := 0
var failures := 0


## The director reads the party off `world.bodies`; a bare Node3D is enough for
## the caster build path, which never asks the world for terrain or props.
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
		print("CASTER_FAIL  ", message)


func run() -> void:
	_check_pool()
	_check_level_gate()
	_check_spawn()
	await _check_cast()
	print("WATCHER_CASTER_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## The pool is the caster's whole identity; Fire Ray must be one of its entries.
func _check_pool() -> void:
	check(CasterScript.SPELL_POOL.size() == 4,
		"the caster rolls one of four rites (%d)" % CasterScript.SPELL_POOL.size())
	check(CasterScript.SPELL_POOL.has("fire_ray"),
		"Fire Ray is one of the caster's rites (%s)" % str(CasterScript.SPELL_POOL))
	var seen := {}
	for index in CasterScript.SPELL_POOL.size():
		var id := str(CasterScript.SPELL_POOL[index])
		check(not seen.has(id), "%s is listed once" % id)
		seen[id] = true
		check(not DemonFireScript.spell(id).is_empty(),
			"%s resolves through the fire table" % id)
	var at := Vector3(12.0, 0.0, -7.0)
	var picked := str(CasterScript.SPELL_POOL[
		CasterScript.spell_index_for(at, "hollow_warden")])
	check(not picked.is_empty(), "a hand-placed caster still gets a rite (%s)" % picked)
	check(picked == str(CasterScript.SPELL_POOL[
		CasterScript.spell_index_for(at, "hollow_warden")]),
		"the fallback pick is deterministic on the same ground")


## The level gate is data on the pool row, and the picker honours it: no caster
## in waves one through four, casters from five, each carrying a pool rite.
func _check_level_gate() -> void:
	var director = DirectorScript.new()
	director.biome_id = "wilderness"
	director._rng.seed = 4242
	director._rite_rng.seed = 4242
	director.level = 4
	var early := 0
	for _roll in 300:
		if str(director._pick_spec(false).get("kind", "")) == "caster":
			early += 1
	check(early == 0, "no caster is picked below level five (%d)" % early)
	director.level = 5
	var late := 0
	var rites := {}
	for _roll in 400:
		var spec: Dictionary = director._pick_spec(false)
		if str(spec.get("kind", "")) != "caster":
			continue
		late += 1
		rites[str(spec.get("spell", ""))] = true
	check(late > 0, "the caster walks from level five (%d)" % late)
	check(rites.has("fire_ray"),
		"Fire Ray is rolled into a wave's caster spec (%s)" % str(rites.keys()))
	for id in rites:
		check(CasterScript.SPELL_POOL.has(str(id)),
			"%s is a rite from the caster's own pool" % str(id))
	director.free()


## The director's own build path takes the caster kind and the spec's rite, and
## files the body under the run's watcher naming. A plain `CharacterBody3D` is the
## party standing there; the caster only needs a quarry to engage.
func _check_spawn() -> void:
	var director = DirectorScript.new()
	var world := FakeWorld.new()
	world.name = "CasterSpawnWorld"
	root.add_child(world)
	var quarry := CharacterBody3D.new()
	quarry.position = Vector3(0.0, 0.0, -4.0)
	world.add_child(quarry)
	world.bodies.append(quarry)
	director.world = world
	director._spawn_spec({"kind": "caster", "species": "hollow_warden",
		"cost": 4.5, "min_level": 5, "spell": "fire_ray"}, Vector3.ZERO)
	check(director._mobs.size() == 1, "the director files the caster (%d)" % director._mobs.size())
	if not director._mobs.is_empty():
		var caster = director._mobs[0]
		check(caster.has_method("caster_spell"), "the body built is a caster")
		check(str(caster.caster_spell()) == "fire_ray",
			"the spec's rite is the body's (%s)" % str(caster.caster_spell()))
		var spells: Array = caster.fire_spells()
		check(spells.size() == 1 and str(spells[0]) == "fire_ray",
			"and it is the one spell on the caster's clock (%s)" % str(spells))
		check(str(caster.name).begins_with("RogueC_"),
			"the run names its casters apart from its watchers (%s)" % str(caster.name))
	director.free()
	world.queue_free()


## The windup resolves into the shared beam; the beam burns the body in the line
## and not the one beside it, and books its damage to the camp's family.
func _check_cast() -> void:
	var world := Node3D.new()
	world.name = "CasterTestWorld"
	root.add_child(world)
	var caster = CasterScript.new()
	caster.name = "CasterProbe"
	caster.mob_id = "hollow_warden"
	caster.position = Vector3.ZERO
	world.add_child(caster)
	caster.global_position = Vector3.ZERO
	caster.safe_center = SAFE_OFFSET
	caster.set_physics_process(false)
	caster.set_caster_spell("fire_ray")
	check(caster.caster_spell() == "fire_ray",
		"the wave's rite reaches the body (%s)" % caster.caster_spell())
	check(caster.fire_spells() == ["fire_ray"],
		"and it is the one spell the body carries (%s)" % str(caster.fire_spells()))

	var hit := Target.new()
	hit.position = Vector3(0.0, 0.0, -6.0)
	world.add_child(hit)
	hit.global_position = Vector3(0.0, 0.0, -6.0)
	var aside := Target.new()
	aside.position = Vector3(4.0, 0.0, -6.0)
	world.add_child(aside)
	aside.global_position = Vector3(4.0, 0.0, -6.0)
	caster.player = hit
	caster.targets.clear()
	caster.targets.append(hit)
	caster.targets.append(aside)
	caster._target = hit
	await physics_frame

	var row: Dictionary = DemonFireScript.spell("fire_ray")
	caster._begin_cast("fire_ray", row, Vector3(0.0, 0.0, -1.0))
	check(caster.casting(), "the caster winds the ray up")
	caster._advance_cast(float(row.get("windup", 0.85)) + 0.05)
	var beam: Node3D = caster.cast_beam()
	check(beam != null and is_instance_valid(beam),
		"the windup resolves into a standing ray")
	if beam == null:
		caster.queue_free()
		hit.queue_free()
		aside.queue_free()
		world.queue_free()
		return
	beam.set_physics_process(false)
	# The node may take one tick on the frame it entered the tree; the whole cast
	# is still 6 × 5 damage, so run its clock out and measure the total.
	for _tick in 8:
		beam._physics_process(0.2)
	check(absf(hit.total() - 30.0) < 0.01,
		"the 1.2 s cast burns 30 through the body in the line (%.2f)" % hit.total())
	check(is_equal_approx(aside.total(), 0.0),
		"the body beside the line is untouched (%.2f)" % aside.total())
	check(hit.sources.all(func(source: int) -> bool: return source == 90),
		"the ray books the camp's family, not the demons (%s)" % str(hit.sources))
	check(beam.is_queued_for_deletion(), "the ray frees itself at the end of its clock")
	caster.queue_free()
	hit.queue_free()
	aside.queue_free()
	world.queue_free()
