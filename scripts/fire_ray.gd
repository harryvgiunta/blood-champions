extends Node3D
## The Ember Staff's held ray: a beam of fire down the live crosshair that burns
## every body its line crosses for as long as the cast holds.
##
## `WarbandAbilities` spawns one on the `beam` cue and this node owns the rest:
## the line is re-read from the staff head and the crosshair every frame (the
## body turns while the ray is held), the beam stops at terrain, and the damage
## is paid on a fixed tick so a body in the line loses the authored DPS rather
## than one number whose size depends on the frame rate.
##
## Only the authority spawns one. A replica reads the caster's `ABILITY` pose
## from its snapshot and never lays a second ray.

const Vfx = preload("res://scripts/vfx_library.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")

const FIRE := Color("ff7a2c")
const FIRE_HOT := Color("ffd0a0")

## The body that owns the cast, the combat that resolves its blows and the rig
## the ray leaves from. All three are kept because the line is live, not baked.
var caster
var combat
var rig
## The definition this ray is the beat of. It stops the frame the runner stops
## holding it, so a stagger, a death or a weapon swap cannot leave fire running.
var ability_id := "fire_ray"
## Damage a body inside the beam loses each second. The tick pays its share.
var damage_per_second := 0.0
## The whole cast, in seconds; `tick_seconds` is the cadence the damage is paid on.
var seconds := 1.2
var tick_seconds := 0.2
## How far the ray reaches, and how far off the line a body still counts as in it.
var reach := 16.0
var radius := 0.55
var stagger := 0.0

## The line as it stands this frame, exposed for the scene and its regression.
var beam_origin := Vector3.ZERO
var beam_direction := Vector3.FORWARD
var beam_length := 0.0
var beam_hit := Vector3.ZERO

var _left := 0.0
var _dealt := 0.0
var _tick_clock := 0.0
var _age := 0.0
var _stopped := false
var _excluded: Array[RID] = []
var _ray := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.UP, 1)
## Each entry is `[MeshInstance3D, QuadMesh, roll, width]`; every layer is drawn
## twice, crossed along the beam, so the ray never disappears edge-on when the
## player looks straight down its line.
var _ribbons: Array = []
var _embers: CPUParticles3D
## Fire that sits on the line itself, short plumes apart, so the whole length
## reads as burning and a wall ends the fire with the damage.
var _plumes: Array = []
var _muzzle: MeshInstance3D
var _tip: MeshInstance3D
var _light: OmniLight3D
var _impact_at := -1.0
## A mob owns no `AbilityRunner` and no `Combat`: these two providers let a cast
## outside the player's kit drive the same ray. `hold` answers whether the ray
## may keep burning; `wound` applies one tick. A player's ray leaves both empty
## and reads its runner and its combat instead.
var _hold_source := Callable()
var _wound_source := Callable()
## A cast frozen on the line it was loosed down. The player's ray follows the
## crosshair; a mob's is a spell in the world, and stepping out of it is the
## answer - so its origin and direction no longer move with the caster.
var _locked := false
var _locked_origin := Vector3.ZERO
var _locked_direction := Vector3.FORWARD


func _ready() -> void:
	_build()


## Hand the ray its body and its numbers. Called once, after `add_child`, so
## `_ready` has already built the art.
func launch(owner_actor, owner_combat, owner_rig, dps: float, life: float,
		tick: float, beam_reach: float, beam_radius: float,
		beam_stagger: float = 0.0) -> void:
	caster = owner_actor
	combat = owner_combat
	rig = owner_rig
	damage_per_second = maxf(dps, 0.0)
	seconds = maxf(life, 0.05)
	tick_seconds = maxf(tick, 0.05)
	reach = maxf(beam_reach, 0.5)
	radius = maxf(beam_radius, 0.05)
	stagger = maxf(beam_stagger, 0.0)
	# The first tick is paid on the first frame: a beam that waits a fifth of a
	# second to hurt reads as a wind-up it does not have.
	_tick_clock = tick_seconds
	_left = seconds
	_excluded.clear()
	if is_instance_valid(caster) and caster is CollisionObject3D:
		_excluded.append(caster.get_rid())


## Hand a non-player caster its two answers. Both are optional: the player's
## path is the runner and `Combat.ability_beam`, below.
func set_hold_source(source: Callable) -> void:
	_hold_source = source


## `wound(origin, direction, length, radius, damage)` applies one tick's share.
func set_wound_source(source: Callable) -> void:
	_wound_source = source


## Freeze the ray's line where it was loosed, so a mob that keeps walking or
## turning leaves the fire exactly where the player learned to step out of it.
func lock_line(origin: Vector3, direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	_locked = true
	_locked_origin = origin
	_locked_direction = direction.normalized()


func _physics_process(delta: float) -> void:
	if _stopped:
		return
	if not _held():
		_stop()
		return
	_age += maxf(delta, 0.0)
	_solve_line()
	_draw()
	_left = maxf(0.0, _left - maxf(delta, 0.0))
	_tick_clock += maxf(delta, 0.0)
	while _tick_clock >= tick_seconds:
		_tick_clock -= tick_seconds
		var step := minf(tick_seconds, seconds - _dealt)
		if step <= 0.0001:
			break
		_dealt += step
		if _wound_source.is_valid():
			_wound_source.call(beam_origin, beam_direction, beam_length, radius,
				damage_per_second * step)
		elif combat != null and is_instance_valid(combat) \
				and combat.has_method("ability_beam"):
			combat.ability_beam(beam_origin, beam_direction, beam_length,
				radius, damage_per_second * step, stagger)
	if _left <= 0.0:
		_stop()


## The cast is still the live one: a staggered, dead or swapped body has already
## dropped it, and so has the runner at the end of its clock.
func _held() -> bool:
	if caster == null or not is_instance_valid(caster):
		return false
	if _hold_source.is_valid():
		return bool(_hold_source.call())
	if rig == null or not is_instance_valid(rig):
		return false
	if combat == null or not is_instance_valid(combat):
		return false
	if caster.get("alive") == false:
		return false
	var runner = caster.get("ability")
	if runner == null or not is_instance_valid(runner):
		return false
	return bool(runner.active) and str(runner.active_id) == ability_id


## Where the ray starts, where it points, and how far it runs before the world
## stops it. The aim is read live: a beam follows the crosshair the way the
## staff head does, and a wall is a wall on every tick rather than at the press.
func _solve_line() -> void:
	var origin := Vector3.ZERO
	var direction := Vector3.ZERO
	if _locked:
		origin = _locked_origin
		direction = _locked_direction
	else:
		if is_instance_valid(rig) and rig.has_method("cast_origin"):
			origin = rig.cast_origin()
		elif is_instance_valid(rig) and rig is Node3D:
			origin = (rig as Node3D).global_position + Vector3.UP * 1.2
		if combat != null and is_instance_valid(combat):
			direction = combat.aim_point - origin
		if direction.length_squared() < 0.0001:
			direction = -rig.global_basis.z if is_instance_valid(rig) \
				else Vector3.FORWARD
		direction = direction.normalized()
	var length := _wall_length(origin, direction)
	beam_origin = origin
	beam_direction = direction
	beam_length = length
	beam_hit = origin + direction * length


## How far the line runs before the world stops it. Both the player's live ray
## and a mob's frozen one ask this, so a wall ends either at the same place.
func _wall_length(origin: Vector3, direction: Vector3) -> float:
	var length := reach
	var world := get_world_3d()
	var space: PhysicsDirectSpaceState3D = world.direct_space_state \
		if world != null else null
	if space != null:
		_ray.from = origin
		_ray.to = origin + direction * reach
		_ray.collision_mask = 1
		_ray.exclude = _excluded
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			length = clampf(origin.distance_to(hit.position), 0.3, reach)
	return length


# --- presentation ----------------------------------------------------------

func _build() -> void:
	var soft := Vfx.dot()
	# The heat envelope, the hot body and its core. All of it adds light; the
	# fire itself is the plume particles, because a stretched flame sheet reads
	# as a rectangular slab at the shoulder camera.
	_ribbon(soft, 4.20, Color(FIRE.r, FIRE.g, FIRE.b, 0.30))
	_ribbon(soft, 2.00, Color(1.0, 0.44, 0.12, 0.80))
	_ribbon(soft, 0.80, Color(1.0, 0.62, 0.25, 0.95))
	_ribbon(soft, 0.30, Color(FIRE_HOT.r, FIRE_HOT.g, FIRE_HOT.b, 0.95))
	_ribbon(soft, 0.10, Color(1.0, 0.84, 0.58, 1.0))
	_muzzle = _sprite(0.85, Color(FIRE.r, FIRE.g, FIRE.b, 0.9))
	_tip = _sprite(0.55, Color(1.0, 0.60, 0.24, 0.85))
	# A continuous plume along the line: the fire the beam is actually made of,
	# shed forward from the mouth and dying before it outruns the ray.
	_embers = Vfx.flame_particles(FIRE, 28, 5.0, 12.0, 0.55, 0.24, false)
	_embers.name = "FireRayEmbers"
	_embers.spread = 10.0
	_embers.gravity = Vector3.ZERO
	# Parked until the first `_draw` has put it on the staff head: a live emitter
	# in the tree's origin would shed its first plumes there.
	_embers.emitting = false
	add_child(_embers)
	for entry in [[0.12, 0.12], [0.28, -0.10], [0.46, 0.14], [0.64, -0.10], [0.80, 0.08]]:
		var plume := Vfx.flame_particles(FIRE, 10, 2.5, 5.5, 0.32, 0.18, false)
		plume.name = "FireRayPlume"
		plume.spread = 10.0
		plume.gravity = Vector3.ZERO
		plume.emitting = false
		add_child(plume)
		_plumes.append([plume, float(entry[0]), float(entry[1])])
	var light := OmniLight3D.new()
	light.name = "FireRayLight"
	light.light_color = FIRE
	light.light_energy = 3.2
	light.omni_range = 7.0
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	add_child(light)
	_light = light


## One additive layer, drawn as a crossed pair around the beam's own axis, so
## the ray never disappears edge-on when the player looks straight down it.
func _ribbon(texture: Texture2D, width: float, tint: Color) -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, 1.0)
	var material := Vfx.quad_material(texture, tint, true, true)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	for roll in [0.0, PI * 0.5]:
		var node := MeshInstance3D.new()
		node.name = "FireRayRibbon"
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_ribbons.append([node, mesh, float(roll), width])


## A camera-facing flare: the mouth of the ray and the point it spends itself on.
func _sprite(size: float, tint: Color) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	mesh.material = Vfx.quad_material(Vfx.dot(), tint, true, false)
	var node := MeshInstance3D.new()
	node.name = "FireRayFlare"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _draw() -> void:
	var axis := _basis_y(beam_direction)
	# A few centimetres of sway: the damage line is the straight one, but fire
	# that is perfectly straight reads as a laser.
	var side := beam_direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized() * (0.03 * sin(_age * 11.0))
	var centre := beam_origin + beam_direction * (beam_length * 0.5) + side
	for entry in _ribbons:
		var node: MeshInstance3D = entry[0]
		var mesh: QuadMesh = entry[1]
		var phase := float(entry[2]) * 3.0
		var width := float(entry[3]) * (1.0 + 0.06 * sin(_age * 37.0 + phase))
		mesh.size = Vector2(width, beam_length)
		node.global_basis = axis * Basis(Vector3.UP, float(entry[2]))
		node.global_position = centre
	if _embers != null:
		# The emitter's local +Y is the beam: `_flipbook` fires its particles down
		# that axis, so the plume is shed forward instead of upward.
		_embers.global_basis = axis
		_embers.global_position = beam_origin + beam_direction * 0.15
		# A short ray sheds short-lived embers: none of the fire crosses the wall
		# the damage line stopped at.
		_embers.lifetime = clampf(beam_length / 12.0, 0.18, 0.55)
		_embers.emitting = true
	for entry in _plumes:
		var plume: CPUParticles3D = entry[0]
		var point := beam_origin + beam_direction * (beam_length * float(entry[1])) \
			+ Vector3.UP * float(entry[2])
		plume.global_basis = axis
		plume.global_position = point
		# A plume that would sit on the wall is the wall's fire, not the ray's:
		# the tip flare owns that beat.
		plume.emitting = point.distance_to(beam_hit) > 1.2
	if _age - _impact_at >= 0.28 and beam_length > 0.5:
		_impact_at = _age
		AbilityFx.burst(self, beam_hit, FIRE, 0.38)
	var pulse := 1.0 + 0.12 * sin(_age * 47.0)
	if _muzzle != null:
		_muzzle.global_position = beam_origin
		_muzzle.scale = Vector3.ONE * pulse
	if _tip != null:
		_tip.global_position = beam_hit
		_tip.scale = Vector3.ONE * (0.82 + 0.20 * sin(_age * 31.0))
	if _light != null:
		_light.global_position = beam_origin + beam_direction * minf(beam_length * 0.35, 3.0)
		_light.light_energy = 3.2 + 0.5 * sin(_age * 43.0)


## A basis whose local Y points down the line, with a stable side vector even on
## a near-vertical ray.
func _basis_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	if y.length_squared() < 0.000001:
		y = Vector3.FORWARD
	var up := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.94 else Vector3.FORWARD
	var x := y.cross(up).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _stop() -> void:
	if _stopped:
		return
	_stopped = true
	set_physics_process(false)
	queue_free()
