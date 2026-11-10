class_name WarbandAbilities
extends Node
## The scene half of the item skills: turns one body's ability cues into
## arrows, spells, blinks and blade beats.
##
## `AbilityRunner` owns *when* a skill fires; the scene owns *what a beat does*.
## The warband therefore has exactly one of these for the whole possession
## campaign, playing the part `main.gd` plays for the frontier: `setup()` keeps
## the world it spawns into, `bind_body()` wires one spawned `ArenaActor` once,
## and every cue is resolved from that body's own active definition, so a looted
## weapon changes the effect without a second ability table.
##
## Only the authoritative, standing body acts. A replica learns its ability from
## the wire and must never spawn a second arrow for the same beat.

const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")
const AbilitySignatures = preload("res://scripts/ability_signatures.gd")
const Archer = preload("res://scripts/archer.gd")
const Arrow = preload("res://scripts/arrow.gd")
const SpellProjectile = preload("res://scripts/spell_projectile.gd")
const FireRay = preload("res://scripts/fire_ray.gd")
const BackstabAbility = preload("res://scripts/backstab_ability.gd")

## World plus bodies: a shot stops on terrain and on the wood's mobs, the same
## pair the possession camera's crosshair ray aims through.
const TARGET_MASK := 1 | 2
## A backstab needs a live body under the crosshair, at the frontier's reach,
## before its blink means anything.
const BACKSTAB_RANGE := 8.0
## Missiles are real damage nodes owned by the authority. The cap is a leak
## guard, not a gameplay limit: the oldest shot goes before the tree grows.
const MAX_MISSILES := 32
## Held beams are counted separately: one cast may stand two (Echo Cast), and a
## beam outlives the cue that made it for the length of the cast.
const MAX_BEAMS := 8
## Cold steel, one shade brighter than a plain cut: the necklace's waves and the
## glow they leave on both blades.
const WAVE_TINT := Color("eef5ff")
## The skill poison's tick: a quarter-second, the cadence the run's own bleeds,
## wounds and zones use, so a 5 dps dose reads as five points a second instead of
## a hundred tiny numbers.
const POISON_TICK := 0.25
## The bloom a poisoned body gives off - the altar's poison row uses the same
## green, so the two doses read as one mechanic.
const POISON_TINT := Color("7ee06a")

var _world: Node3D
var _controller
var _bodies: Array = []
var _missiles: Array = []
## Standing rays, `fire_ray.gd`: their own clock and the caster's ability state
## end them, so this list is only what the scene and its regression can see.
var _beams: Array = []
## Laid doses: `{target, dps, left, clock, source, run}`. One per body, refreshed
## rather than stacked, and ticked by this node so a dose outlives the
## activation that laid it.
var _venoms: Array = []


## Wire the node to the world it spawns into. The controller is kept because a
## cue resolves its aim from the body the soul is actually inside.
func setup(world: Node3D, controller) -> void:
	_world = world
	_controller = controller


## The possession bridge this node was set up with. Exposed so a scene does not
## have to keep a second reference to it.
func controller():
	return _controller


## Wire one spawned body. Idempotent: the world may bind the same body again
## after a re-seat, and a second connection would fire every beat twice.
func bind_body(actor) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	_prune_bodies()
	if _bodies.has(actor):
		return
	var runner = actor.get("ability")
	if runner == null or not is_instance_valid(runner):
		return
	runner.cue.connect(_on_cue.bind(actor))
	# The backstab has to know which body it will land behind *before* its first
	# cue, exactly as the frontier preflights it: the blink and the stab must
	# agree on one body even if the crosshair has moved by the second beat.
	runner.activated.connect(_on_activated.bind(actor))
	_bodies.append(actor)


## Bodies with live cue wiring, for tests and for a scene that wants to rescan.
func bound_bodies() -> Array:
	_prune_bodies()
	return _bodies.duplicate()


## The shots and spells still flying, for tests and for a scene's cleanup.
func missiles() -> Array:
	_prune_missiles()
	return _missiles.duplicate()


## The held rays still burning, for tests and for a scene's cleanup.
func beams() -> Array:
	_prune_beams()
	return _beams.duplicate()


# --- cues ------------------------------------------------------------------

## One performed beat. The definition is re-read from the runner every cue so a
## weapon swapped mid-skill can never leave the wrong effect behind.
func _on_cue(id: String, cue: String, index: int, actor) -> void:
	if not _can_act(actor):
		return
	var runner = actor.ability
	if runner == null or not is_instance_valid(runner) or not runner.active:
		return
	if str(runner.active_id) != id:
		return
	var definition: Dictionary = runner.active_definition
	if definition.is_empty():
		return
	var rig = actor.rig
	if rig == null or not is_instance_valid(rig):
		return
	var effect: Dictionary = definition.get("effect", {})
	var damage: float = AbilityRules.damage_for(definition, rig)
	# The beat's own art first, from the shared signature table: every skill draws
	# its own shape on the line the scene has already solved, before the damage
	# branch below spends the hit. A skill with no signature is reported by
	# `AbilitySignatures.missing_signatures()`, never silently skipped.
	var aim: Vector3 = runner.combat.aim_point if is_instance_valid(runner.combat) \
		else rig.global_position - rig.global_basis.z
	var forward: Vector3 = aim - rig.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	AbilitySignatures.cue(_fx_parent(), rig, definition, cue, index,
		forward.normalized(), aim)
	match str(effect.get("kind", "")):
		"barrage", "volley", "piercing_shot":
			_fire_arrows(actor, runner, definition, index, damage)
		"projectile":
			_launch_spell(actor, runner, definition, damage)
		"beam":
			_open_beam(actor, runner, definition, damage)
		"backstab":
			_backstab(actor, runner, cue, damage)
		"melee_arc", "melee_ring":
			_melee(actor, runner, definition, cue, index, damage)
		"melee_wave":
			_melee_wave(actor, runner, definition, cue, index, damage)
	# A travelling skill's lane is swept by `ArenaActor._sweep_ability_path`;
	# a ward is a body state the runner has already started. Neither needs a
	# beat here, and neither may be applied twice.


## The preflight for the one skill that moves the body: resolve the body behind
## which the dagger will land and keep it on the actor. An empty crosshair drops
## any target from a previous activation instead of blinking behind a corpse.
func _on_activated(_id: String, definition: Dictionary, actor) -> void:
	if not _can_act(actor):
		return
	if actor.has_meta("backstab_target"):
		actor.remove_meta("backstab_target")
	var effect: Dictionary = definition.get("effect", {})
	var kind := str(effect.get("kind", ""))
	# The three-strike necklace lights both weapons before the first wave: the
	# glow is the tell, and it is the rig's hands that are lit, not the world.
	if kind == "melee_wave":
		_weapon_glow(actor, float(effect.get("glow_seconds", 0.8)))
		return
	if kind != "backstab":
		return
	var target := _backstab_target(actor)
	if target != null:
		actor.set_meta("backstab_target", target)


## Only a body that owns its own simulation and is still standing may put a
## hit into the world.
func _can_act(actor) -> bool:
	return actor != null and is_instance_valid(actor) \
		and bool(actor.get("authoritative")) and bool(actor.get("alive")) \
		and not bool(actor.get("downed"))


# --- ranged ----------------------------------------------------------------

## Barrage / fan volley / piercing shot: one arrow per beat (a volley spawns its
## fan from a single cue), aimed down the live crosshair with the authored
## spread. The arrow's own `pierce` budget carries the piercing shot through
## three bodies.
func _fire_arrows(actor, runner, definition: Dictionary, index: int, damage: float) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var kind := str(effect.get("kind", ""))
	var rig = actor.rig
	var aim: Vector3 = runner.combat.aim_point
	# The cue lands before this rig's own pose step, so aim and resample the bow
	# before reading the hand: the arrow leaves on the live crosshair line.
	rig.aim_at(aim)
	rig.refresh_bow_pose()
	var origin: Vector3 = rig.get_arrow_origin()
	var base := aim - origin
	if base.length_squared() < 0.0001:
		base = -rig.global_basis.z
	var profile: Dictionary = Archer.BOW_DATA[
		clampi(int(rig.bow_index), 0, Archer.BOW_DATA.size() - 1)]
	var family := AbilityRules.type_of(definition)
	var run = actor.get("roguelite")
	var base_damage := damage
	var speed := float(profile.speed) * float(effect.get("arrow_speed_scale", 1.0))
	var pierce := int(effect.get("pierce", 0))
	var shots := int(effect.get("shots", 1)) if kind == "volley" else 1
	var split := 0
	var extra := 0
	var bounces := 0
	var homing := 0.0
	var spiral := false
	var plan: Dictionary = {}
	if run != null:
		plan = run.spell_plan(base_damage, family)
		base_damage = float(plan.get("damage", base_damage))
		speed *= float(plan.get("speed", 1.0))
		pierce += int(plan.get("pierce", 0))
		bounces = int(plan.get("bounces", 0))
		homing = float(plan.get("homing", 0.0))
		split = int(run.ability_arrow_split(family)) if run.has_method("ability_arrow_split") else 0
		extra = 1 if run.has_method("ability_extra_arrow") and run.ability_extra_arrow(family) else 0
		spiral = run.has_method("ability_spiral") and run.ability_spiral(family)
	var total := shots + split + extra + (1 if runner.take_recast() else 0)
	# A skill may author a venom: the shaft is the dose, so every arrow this beat
	# looses lays it on the body it opens. The run's own on-hit chain stays behind
	# it - a poison is a second thing the hit does, never a replacement.
	var poison_dps := float(effect.get("poison_dps", 0.0))
	var poison_seconds := float(effect.get("poison_seconds", 0.0))
	var on_hit: Callable = run.hit_hook() if run != null else Callable()
	if poison_dps > 0.0 and poison_seconds > 0.0:
		on_hit = _poisoned(on_hit, run, poison_dps, poison_seconds, int(actor.slot))
	var excluded: Array[RID] = []
	if actor is CollisionObject3D:
		excluded.append(actor.get_rid())
	for shot in total:
		# A skill looses arrows like a bow does: one shaft out of the party quiver
		# each. A volley that outruns the quiver fires only what is left in it, so
		# no skill can spend the count past zero.
		if not _take_arrow():
			break
		# A barrage spreads by beat, a volley by arrow in the same beat.
		var pattern_index := index if kind == "barrage" else shot
		var offsets: Vector2 = AbilityFx.shot_offsets(definition, pattern_index)
		var direction := AbilityFx.rotate_direction(base, offsets.x, offsets.y)
		var arrow_damage := base_damage
		# Split Fletching pays 25% for the extra shafts; an extra arrow from
		# Double Nock and a recast pay in full.
		if shot >= shots and shot < shots + split:
			arrow_damage *= 0.25
		var arrow := Arrow.new()
		arrow.source_id = int(actor.slot)
		arrow.shooter = actor
		arrow.hit_mask = TARGET_MASK
		arrow.authoritative_damage = true
		# A bow skill looses the bow's shafts, so the bow's own health-on-hit
		# rides them too: one rule for every shaft the hand lets go.
		arrow.heal_on_hit = rig.bow_heal_on_hit()
		arrow.crit = bool(plan.get("crit", false))
		arrow.proc_coeff = float(plan.get("proc", 1.0))
		arrow.bounces = bounces
		arrow.bounce_scale = run.engine.hop_scale() if run != null else 0.9
		arrow.homing = homing
		arrow.spiral = 4.0 if spiral else 0.0
		arrow.on_hit = on_hit
		if run != null and run.director != null:
			arrow.bounce_provider = Callable(run.director, "bounce_target")
			arrow.homing_provider = Callable(run.director, "nearest_enemy")
		if run != null and not arrow.impacted.is_connected(run.note_shot_impact):
			arrow.impacted.connect(run.note_shot_impact)
		add_child(arrow)
		arrow.launch(origin, direction, speed, arrow_damage, excluded, origin, pierce)
		_track(arrow)

## One shaft out of the party quiver, through the world's own spend funnel so the
## co-op peers are told about it too. A node with no world behind it - a harness
## that stands this one up on its own - looses free rather than guessing at a
## quiver it was never handed.
func _take_arrow() -> bool:
	if _world == null or not _world.has_method("spend_arrow"):
		return true
	return bool(_world.call("spend_arrow"))


## Fireball / bone spear: the projectile owns its flight and presentation, and
## the owning combat resolves the blast so armour, blocks and blood behave like
## every other hit.
func _launch_spell(actor, runner, definition: Dictionary, damage: float) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var rig = actor.rig
	var origin: Vector3 = rig.cast_origin()
	var aim: Vector3 = runner.combat.aim_point
	var direction := aim - origin
	if direction.length_squared() < 0.0001:
		direction = -rig.global_basis.z
	var family := AbilityRules.type_of(definition)
	var run = actor.get("roguelite")
	var spell_damage := damage
	var speed := float(effect.get("speed", 22.0))
	var pierce := int(effect.get("pierce", 0))
	var radius := float(effect.get("radius", 0.0))
	var bounces := 0
	var plan: Dictionary = {}
	if run != null:
		plan = run.spell_plan(spell_damage, family)
		spell_damage = float(plan.get("damage", spell_damage))
		speed *= float(plan.get("speed", 1.0))
		pierce += int(plan.get("pierce", 0))
		radius += float(plan.get("radius", 0.0))
		bounces = int(plan.get("bounces", 0))
	# A recast is one more orb down the same line. Copies are spawned before the
	# loop so the runner's flag is consumed once.
	var copies := 1 + (1 if runner.take_recast() else 0)
	for _copy in copies:
		var spell := SpellProjectile.new()
		spell.kind = str(effect.get("projectile", "fireball"))
		spell.hit_mask = TARGET_MASK
		spell.shooter = actor
		spell.authoritative_damage = true
		spell.crit = bool(plan.get("crit", false))
		spell.proc_coeff = float(plan.get("proc", 1.0))
		spell.bounces = bounces
		if run != null:
			spell.bounce_scale = run.engine.hop_scale()
			spell.on_hit = run.hit_hook()
			if run.director != null:
				spell.bounce_provider = Callable(run.director, "bounce_target")
		add_child(spell)
		var excluded: Array[RID] = []
		if actor is CollisionObject3D:
			excluded.append(actor.get_rid())
		spell.launch(origin, direction, speed, spell_damage,
			excluded, spell.hit_mask, true, rig.global_position,
			radius, pierce)
		spell.source_rig = rig
		spell.set_meta("stagger", float(effect.get("stagger", 0.0)))
		spell.detonated.connect(_on_spell_detonated.bind(spell, actor.combat))
		_track(spell)

func _on_spell_detonated(centre: Vector3, _direction: Vector3, spell, combat_ref) -> void:
	if not is_instance_valid(spell) or not is_instance_valid(combat_ref):
		return
	if spell.blast_radius <= 0.0:
		return
	combat_ref.ability_blast(centre, spell.blast_radius, spell.damage,
		float(spell.get_meta("stagger", 0.0)))


## Fire Ray: a held beam rather than a shot. The node re-reads the staff head and
## the live crosshair every frame, stops at terrain, and pays its damage on the
## authored tick until the cast's own clock runs out. The run's spell plan is
## rolled once here - one crit decision for the whole ray instead of a fresh one
## per tick - and a recast stands a second ray down the same line.
func _open_beam(actor, runner, definition: Dictionary, damage: float) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var rig = actor.rig
	var body_combat = actor.combat
	if rig == null or not is_instance_valid(rig) or body_combat == null \
			or not is_instance_valid(body_combat):
		return
	var family := AbilityRules.type_of(definition)
	var run = actor.get("roguelite")
	var dps := damage
	var radius := float(effect.get("radius", 0.55))
	var plan: Dictionary = {}
	if run != null:
		plan = run.spell_plan(dps, family)
		dps = float(plan.get("damage", dps))
		radius += float(plan.get("radius", 0.0))
	var copies := 1 + (1 if runner.take_recast() else 0)
	var life := maxf(float(definition.get("duration", 1.2)) - runner.elapsed, 0.05)
	for _copy in copies:
		var ray := FireRay.new()
		ray.name = "FireRay"
		add_child(ray)
		ray.launch(actor, body_combat, rig, dps, life,
			float(effect.get("tick_seconds", 0.2)),
			float(effect.get("range", 16.0)), maxf(radius, 0.05),
			float(effect.get("stagger", 0.0)))
		_track_beam(ray)


# --- backstab --------------------------------------------------------------

## The blink moves the body and smokes the spot it lands on; the departure smoke
## and the flash on the wound are the signature's. The stab spends the doubled
## dagger damage on the body the caster is now behind.
func _backstab(actor, runner, cue: String, damage: float) -> void:
	var rig = actor.rig
	var target: Node3D = null
	if actor.has_meta("backstab_target"):
		var resolved = actor.get_meta("backstab_target")
		if is_instance_valid(resolved) and resolved is Node3D:
			target = resolved
	if cue == "blink":
		if target == null:
			return
		var spot: Dictionary = BackstabAbility.behind_spot(_space(), target)
		if not bool(spot.get("ok", false)):
			return
		BackstabAbility.blink(actor, spot.position, float(spot.yaw))
		_puff(rig.global_position)
		return
	if cue != "stab":
		return
	if target == null:
		target = _backstab_target(actor)
	if target != null and target.get("alive") != false:
		var run = actor.get("roguelite")
		if run != null:
			damage *= run.ability_damage_multiplier("dagger") \
				* run.engine.melee_damage_multiplier()
		BackstabAbility.strike(actor, target, damage, int(actor.slot))
		if target.get("alive") != false and runner.take_recast():
			BackstabAbility.strike(actor, target, damage * 0.8, int(actor.slot))
	if actor.has_meta("backstab_target"):
		actor.remove_meta("backstab_target")


func _backstab_target(actor) -> Node3D:
	var exclude: Array[RID] = []
	if actor is CollisionObject3D:
		exclude.append(actor.get_rid())
	return BackstabAbility.find_target(_space(), actor.global_position,
		actor.combat.aim_point, TARGET_MASK, BACKSTAB_RANGE, exclude)


# --- melee -----------------------------------------------------------------

## The blade beats. The hit itself goes through the body's own combat so blocks,
## armour, blood and damage numbers are the authored swing's; the art is
## `AbilitySignatures`, drawn on the same cue before this function spends the hit.
func _melee(actor, runner, definition: Dictionary, cue: String, _index: int,
		damage: float) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var radius := float(effect.get("radius", 1.7))
	var arc := float(effect.get("arc_degrees", 360.0))
	var ring := str(effect.get("kind", "")) == "melee_ring" or arc >= 359.0
	# The greatsword's wind-up and the lunge's takeoff are presentation only: the
	# blade gathers speed before the ring cue spends the hit, and the thrust cue,
	# not the dash, is the blow.
	if cue == "wind" or cue == "dash":
		return
	# A travelling skill already swept its lane, so the closing beat shares that
	# victim set and never hits a body the dash passed through twice.
	var victims: Dictionary = {}
	if bool(effect.get("path_damage", false)):
		victims = runner.active_victims
	var run = actor.get("roguelite")
	var family := AbilityRules.type_of(definition)
	var strike_damage := damage
	var extra := 0
	if run != null:
		strike_damage *= run.ability_damage_multiplier(family) \
			* run.engine.melee_damage_multiplier()
		extra = run.ability_cleave(family)
	runner.combat.ability_strike_cleave(radius, arc, strike_damage,
		float(effect.get("stagger", 0.0)), ring, not ring, victims, extra)
	# Echo Cast pays a second beat at the same reach, through a fresh victim set
	# so the recast is a real second cut and not a no-op against the first one.
	if runner.take_recast():
		runner.combat.ability_strike_cleave(radius, arc, strike_damage * 0.8,
			float(effect.get("stagger", 0.0)), ring, not ring, {}, extra)



# --- the three-strike wave -------------------------------------------------

## One wave of the necklace's three-strike. Every cue is its own cut with its own
## victim list, so the skill reaches across a rank instead of re-cutting one body:
## the wave stops at `victims_per_wave` (three), the three waves together stop at
## `ABILITY_MAX_VICTIMS` as every activation does. `wave_scales` is the authored
## damage per wave and `wave_sides` says which hand throws it - right, left, then
## both, which is the authored reading of the skill.
func _melee_wave(actor, runner, definition: Dictionary, cue: String, index: int,
		damage: float) -> void:
	if cue != "wave":
		return
	var effect: Dictionary = definition.get("effect", {})
	var scales: Array = effect.get("wave_scales", [])
	var share := float(scales[index]) if index < scales.size() else 1.0
	var radius := float(effect.get("radius", 2.4))
	var arc := float(effect.get("arc_degrees", 130.0))
	var per_wave := int(effect.get("victims_per_wave", 3))
	var run = actor.get("roguelite")
	var family := AbilityRules.type_of(definition)
	var strike_damage := damage * share
	var extra := 0
	if run != null:
		strike_damage *= run.ability_damage_multiplier(family) \
			* run.engine.melee_damage_multiplier()
		extra = run.ability_cleave(family)
	runner.combat.ability_strike(radius, arc, strike_damage,
		float(effect.get("stagger", 0.0)), false, true, {}, per_wave + extra)
	if index == 0 and runner.take_recast():
		runner.combat.ability_strike(radius, arc, strike_damage * 0.8,
			float(effect.get("stagger", 0.0)), false, true, {}, per_wave + extra)
	# The wave's art is `AbilitySignatures`': a crescent through the arc it just cut
	# and a ripple pair out to the same reach, turned by the hand that threw it,
	# plus a ribbon on every blade that swung.


## Both weapons lit for the length of the skill: the held steel burns cold for
## `hold`, a lamp on each hand spills that light onto the arms, and a ribbon
## follows the blade tip. The emission is an override on each drawn surface and
## is put back when the beat ends, so the altar's own inlaid marks (child meshes,
## never an override) are untouched and no material is mutated in place.
func _weapon_glow(actor, seconds: float) -> void:
	var rig = actor.rig
	if rig == null or not is_instance_valid(rig):
		return
	if not rig.has_method("get_blade_base") or not rig.has_method("swing_weapon_class"):
		return
	var parent := _fx_parent()
	if parent == null:
		return
	var hold := clampf(seconds, 0.2, 2.0)
	var lit := AbilityFx.glow_material(WAVE_TINT, 2.6, 0.9)
	for hand in ["right", "left"]:
		# A hand with nothing to swing (a bow, an empty off hand) lights nothing.
		if str(rig.swing_weapon_class(hand)).is_empty():
			continue
		# The beat that lights a blade also leaves its ribbon, so a dual pair
		# reads as two blades working for the whole skill.
		AbilityFx.blade_trail(parent, rig, hold, AbilityFx.STEEL, hand)
		var light := AbilityFx.flash_light(WAVE_TINT, 1.8, 1.6)
		rig.add_child(light)
		light.position = rig.to_local(rig.get_blade_base(hand))
		var fade := light.create_tween()
		fade.tween_property(light, "light_energy", 0.0, hold)
		fade.tween_callback(light.queue_free)
	if rig.has_method("held_weapon_nodes"):
		for node in rig.held_weapon_nodes():
			for child in (node as Node).find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				var previous: Material = mesh.material_override
				mesh.material_override = lit
				var put_back := mesh.create_tween()
				put_back.tween_interval(hold)
				put_back.tween_callback(func() -> void:
					if is_instance_valid(mesh):
						mesh.material_override = previous)


# --- the venom -------------------------------------------------------------

## The poison's own clock. One quarter-second beat, on the only node every skill's
## cue passes through, so a dose keeps working after its skill has finished and
## the arena and the run tick it the same way. A guest never lays a dose - the
## arrow's `on_hit` is the authority's - so its list stays empty.
func _physics_process(delta: float) -> void:
	if _venoms.is_empty():
		return
	var keep: Array = []
	for entry in _venoms:
		var venom: Dictionary = entry
		var target = venom.get("target")
		if target == null or not is_instance_valid(target) \
				or target.get("alive") == false:
			continue
		var dps := float(venom.get("dps", 0.0))
		var left := float(venom.get("left", 0.0))
		var clock := float(venom.get("clock", 0.0)) + maxf(delta, 0.0)
		while clock >= POISON_TICK and left > 0.0 and dps > 0.0:
			clock -= POISON_TICK
			var step := minf(left, POISON_TICK)
			left -= step
			if target.has_method("take_damage"):
				target.take_damage(dps * step, int(venom.get("source", -1)), false)
			# A body the venom put down is credited like any other kill of the
			# run's: the dose is the blow that finished it.
			if target.get("alive") == false:
				var run = venom.get("run")
				if run != null and is_instance_valid(run) \
						and run.has_method("proc_hit"):
					run.proc_hit(target, true, dps * step)
				left = 0.0
		if left <= 0.0:
			continue
		venom["left"] = left
		venom["clock"] = clock
		keep.append(venom)
	_venoms = keep


## The shot's landing, with the skill's venom laid on the body it opens. The
## wrapped hook is the arrow's own `on_hit`, so the run's on-hit chain still
## resolves first and a poisoned starter reads as the same shot plus a dose.
func _poisoned(inner: Callable, run, dps: float, seconds: float,
		source: int) -> Callable:
	return func(target, at: Vector3, damage: float, crit: bool,
			proc: float) -> void:
		if inner.is_valid():
			inner.call(target, at, damage, crit, proc)
		_lay_poison(target, at, dps, seconds, source, run)


## One dose on one body. A second dose refreshes the clock and only ever raises
## the rate, so the figure the skill advertises is what the body loses each
## second rather than a stack of twin poisons.
func _lay_poison(target, at: Vector3, dps: float, seconds: float, source: int,
		run) -> void:
	if dps <= 0.0 or seconds <= 0.0:
		return
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage") or target.get("alive") == false:
		return
	var left := maxf(seconds, POISON_TICK)
	for entry in _venoms:
		var venom: Dictionary = entry
		if venom.get("target") != target:
			continue
		venom["dps"] = maxf(float(venom.get("dps", 0.0)), dps)
		venom["left"] = maxf(float(venom.get("left", 0.0)), left)
		venom["source"] = source
		if run != null:
			venom["run"] = run
		_poison_bloom(at, 0.55)
		return
	_venoms.append({"target": target, "dps": dps, "left": left, "clock": 0.0,
		"source": source, "run": run})
	_poison_bloom(at, 1.0)


## The green bloom at the wound. Presentation only: nothing here reads health.
func _poison_bloom(at: Vector3, scale: float) -> void:
	var parent := _fx_parent()
	if parent == null:
		return
	AbilityFx.burst(parent, at, POISON_TINT, clampf(scale, 0.4, 1.2))


# --- helpers ---------------------------------------------------------------

func _fx_parent() -> Node3D:
	if _world != null and is_instance_valid(_world):
		return _world
	return get_parent() as Node3D


func _space() -> PhysicsDirectSpaceState3D:
	var parent := _fx_parent()
	if parent == null or not parent.is_inside_tree():
		return null
	var world: World3D = parent.get_world_3d()
	if world == null:
		return null
	return world.direct_space_state


## The blink's arrival smoke. The departure burst and every other beat belong to
## `AbilitySignatures`; a missing world (a bare test harness) skips the show.
func _puff(at: Vector3) -> void:
	AbilityFx.smoke_puff(_fx_parent(), at, 1.0, true)


## Keep the missile list valid and bounded: a shot that freed itself (an impact,
## a timeout) is dropped, and the oldest still-listed shot pays for a new one.
func _track(missile: Node) -> void:
	_prune_missiles()
	_missiles.append(missile)
	while _missiles.size() > MAX_MISSILES:
		var oldest = _missiles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _prune_missiles() -> void:
	for index in range(_missiles.size() - 1, -1, -1):
		if not is_instance_valid(_missiles[index]):
			_missiles.remove_at(index)


## Keep the beam list valid and bounded the same way the missile list is: a ray
## that spent its cast (or its caster) has already freed itself.
func _track_beam(ray: Node) -> void:
	_prune_beams()
	_beams.append(ray)
	while _beams.size() > MAX_BEAMS:
		var oldest = _beams.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _prune_beams() -> void:
	for index in range(_beams.size() - 1, -1, -1):
		if not is_instance_valid(_beams[index]):
			_beams.remove_at(index)


func _prune_bodies() -> void:
	for index in range(_bodies.size() - 1, -1, -1):
		if not is_instance_valid(_bodies[index]):
			_bodies.remove_at(index)
