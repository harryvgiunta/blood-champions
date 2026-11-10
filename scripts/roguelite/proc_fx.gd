extends RefCounted
## The arena's proc visuals that are not a projectile: the blood arc's lightning,
## a nova's ring, and the small flash a kill leaves.
##
## Host and guest both run these: the host draws the consequence it rolled, and a
## guest draws the same one from the event the host broadcast. They are purely
## presentational - no damage, no collision, no gameplay state - so a peer that
## misses one loses only a flash.

const Geo = preload("res://scripts/geo.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")
const Aura = preload("res://scripts/roguelite/proc_aura.gd")
const Vfx = preload("res://scripts/vfx_library.gd")

const BLOOD := Color(0.95, 0.22, 0.16)
const SPARK := Color(1.0, 0.72, 0.36)
## The two hues the run's own housekeeping reads in: a heal is a slow green-gold
## lift, a payout is coin light. Kept here beside BLOOD so every proc effect in the
## arena draws from one palette rather than painting its own.
const HEAL := Color(0.56, 0.94, 0.62)
const GOLD := Color(1.0, 0.84, 0.40)


## A jagged arc between two points: the Blood Arc's zap, and the same shape a
## future chain effect can reuse.
static func lightning(parent: Node3D, from: Vector3, to: Vector3,
		colour: Color = BLOOD) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var node := Node3D.new()
	node.name = "ProcLightning"
	parent.add_child(node)
	# World-space vertices, world-space node: an island dressing node with its own
	# transform must not bend the arc into its local frame.
	node.top_level = true
	var points := _jagged(from, to, 9)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 4.0
	material.vertex_color_use_as_albedo = false
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(instance)
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 2.4
	light.omni_range = 5.0
	light.position = to
	node.add_child(light)
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(instance, "transparency", 1.0, 0.18)
	tween.tween_property(light, "light_energy", 0.0, 0.18)
	tween.chain().tween_callback(node.queue_free)


## A ring on the ground: the nova, the bomb's burst, a chest's opening.
static func ring(parent: Node3D, at: Vector3, colour: Color = BLOOD,
		size: float = 2.0, hold: float = 0.26) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var node := Node3D.new()
	node.name = "ProcRing"
	parent.add_child(node)
	node.top_level = true
	node.global_position = at
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(colour.r, colour.g, colour.b, 0.55)
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.55, size * 0.9)
	torus.outer_radius = maxf(0.62, size)
	torus.rings = 24
	torus.ring_segments = 8
	var instance := MeshInstance3D.new()
	instance.mesh = torus
	instance.material_override = material
	instance.rotation.x = PI * 0.5
	instance.position = Vector3(0.0, 0.08, 0.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(instance)
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(instance, "scale", Vector3.ONE * 2.6, hold)
	tween.tween_property(material, "albedo_color", Color(colour.r, colour.g, colour.b, 0.0), hold)
	tween.chain().tween_callback(node.queue_free)


## A short, bright flare at a point: a splinter's birth, an absorbed charge.
static func flare(parent: Node3D, at: Vector3, colour: Color = SPARK,
		size: float = 0.5) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var node := Node3D.new()
	node.name = "ProcFlare"
	parent.add_child(node)
	node.top_level = true
	node.global_position = at
	var material := Geo.material(colour, 0.0, 0.4)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sphere := Geo.sphere(node, size, Vector3.ZERO, material)
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sphere, "scale", Vector3.ONE * 0.1, 0.2)
	tween.tween_property(sphere, "transparency", 1.0, 0.2)
	tween.chain().tween_callback(node.queue_free)


## A chest's payout leaving the lid: the piece rises on a short arc, hangs with
## its name over it for a beat, then flies into the body that owns it. The host
## draws it when it rolls the piece and every guest draws it from the same small
## event, so the presentation is not a second table on the wire.
static func loot_pop(parent: Node3D, from: Vector3, hover: Vector3, to: Vector3,
		title: String, detail: String, colour: Color) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var node := Node3D.new()
	node.name = "LootPop"
	parent.add_child(node)
	node.top_level = true
	node.global_position = from
	var shell := Geo.box(node, Vector3(0.36, 0.40, 0.06), Vector3.ZERO,
		Geo.material(colour, 0.4, 0.3))
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rim := Geo.box(node, Vector3(0.42, 0.46, 0.03), Vector3(0.0, 0.0, -0.04),
		Geo.material(Color(0.06, 0.06, 0.07), 0.2, 0.5))
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 1.4
	light.omni_range = 4.0
	node.add_child(light)
	_billboard(node, title, Vector3(0.0, 0.66, 0.0), colour, 32)
	_billboard(node, detail, Vector3(0.0, 0.40, 0.0), Color(0.94, 0.90, 0.80), 24)
	# The piece turns on its own clock while the pop hangs; the labels do not
	# turn with it, because a name read upside down is not a name.
	var spin := shell.create_tween()
	spin.tween_property(shell, "rotation:y", TAU, 1.3)
	var tween := node.create_tween()
	tween.tween_property(node, "global_position", hover, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.6)
	tween.tween_property(node, "global_position", to, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(node, "scale", Vector3.ONE * 0.3, 0.34)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.34)
	tween.tween_callback(node.queue_free)


static func _billboard(parent: Node3D, text: String, at: Vector3, colour: Color,
		size: int = 28) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.004
	label.modulate = colour
	label.outline_modulate = Color(0.03, 0.03, 0.04, 0.92)
	label.outline_size = 10
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	return label


static func _jagged(from: Vector3, to: Vector3, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(from.x * 17.0) + absf(to.z * 31.0) + 7.0)
	var axis := (to - from)
	var length := axis.length()
	if length <= 0.001:
		return PackedVector3Array([from, to])
	var direction := axis / length
	var side := direction.cross(Vector3.UP)
	if side.length_squared() <= 0.001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	for index in steps + 1:
		var t := float(index) / float(steps)
		var point := from.lerp(to, t)
		if index > 0 and index < steps:
			var jitter := side * rng.randf_range(-0.22, 0.22) + Vector3.UP * rng.randf_range(-0.18, 0.18)
			point += jitter * (length * 0.12 + 0.15)
		out.append(point)
	return out


# --- Proc effect kit -------------------------------------------------------
# The rest of the arena's proc readings. Every entry below draws one proc's
# consequence and nothing else: no damage, no collision, no tick, no lookup of a
# body - the host fires it from the roll it made and a guest fires it from the
# event it heard, with the same arguments, so the two peers draw the same flash.
#
# Arms and scatter come from the arguments and from `_seed_at`, a hash of the
# quantised point, never from `randf()`: a repro that differs between peers is
# a bug report about a visual, and there is no reason to have one.
#
# Budgets: twelve nodes and 120 particles per one-shot. Where a caller passes a
# count (a nova's splinters, a chain's hops) it is clamped to that budget, and
# the mesh carries the read instead of the count.

## The thrown blade of a bodiless arc: the shard makes the trip, turning about
## its own flight line, and four dashes stutter out behind it. `from` is the
## body, `to` the point it was thrown at, and neither has to still exist - the
## arc is a line between two recorded points, not a homing shot.
static func arc_blade(parent: Node3D, from: Vector3, to: Vector3,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var axis := to - from
	if axis.length_squared() < 0.0001:
		return
	var root := _root(parent, "ProcArcBlade", from)
	var flight := clampf(axis.length() / 24.0, 0.14, 0.30)
	var path := axis.normalized()
	var up := Vector3.UP
	if absf(path.dot(up)) > 0.98:
		up = Vector3.BACK
	root.global_basis = Basis.looking_at(path, up)
	var blade_material := Geo.material(colour, 0.5, 0.3)
	blade_material.emission_enabled = true
	blade_material.emission = colour
	blade_material.emission_energy_multiplier = 1.6
	# Long across the flight line and thin through it, so spinning about the
	# local Z is the blade turning edge-on and back, not a drill.
	var blade := Geo.box(root, Vector3(0.95, 0.04, 0.30), Vector3.ZERO,
		blade_material)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for index in 4:
		var dash := _streak(root, 0.62 - 0.06 * index, 0.10, colour, Vector3.BACK)
		dash.position = Vector3(0.0, 0.05 * float(index % 2), 0.55 + 0.46 * index)
		var dash_material := AbilityFx.sprite_tint(dash)
		dash_material.albedo_color = Color(colour.r, colour.g, colour.b, 0.0)
		var beat := dash.create_tween()
		beat.tween_interval(0.03 * float(index))
		beat.tween_property(dash_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.62), 0.04)
		beat.tween_property(dash_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.0), 0.15 + 0.02 * index)
	flare(root, from, colour, 0.34)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(root, "global_position", to, flight) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(blade, "rotation:z", TAU * 3.0, flight)
	tween.set_parallel(false)
	tween.tween_interval(0.14)
	tween.tween_callback(root.queue_free)


## A nova's floor ring plus its splinters: flat shards driven outward and a
## little up, so the burst reads as a disc rather than a sphere. The count is
## clamped to nine - thirty splinters would cost three node budgets and the ring
## is what is legible at 26 px anyway.
static func nova_ring(parent: Node3D, at: Vector3, colour: Color,
		count: int) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcNovaRing", at)
	var ring := _flare_ring(root, colour, 0.62, 0.09)
	ring.position = Vector3.UP * 0.06
	ring.scale = Vector3(0.2, 1.0, 0.2)
	var ring_material := ring.material_override as StandardMaterial3D
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_at(at, 5)
	var shards := clampi(count, 4, 9)
	for index in shards:
		var angle := TAU * float(index) / float(shards) + rng.randf_range(-0.18, 0.18)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var splinter := _streak(root, rng.randf_range(0.5, 0.8), 0.11, colour,
			direction)
		splinter.position = direction * 0.3 + Vector3.UP * 0.08
		var material := AbilityFx.sprite_tint(splinter)
		material.albedo_color = Color(colour.r, colour.g, colour.b, 0.0)
		var reach := rng.randf_range(1.4, 2.4)
		var lift := rng.randf_range(0.12, 0.38)
		var move := splinter.create_tween()
		move.tween_property(splinter, "position",
			direction * reach + Vector3.UP * lift, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var fade := splinter.create_tween()
		fade.tween_property(material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.9), 0.05)
		fade.tween_property(material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.0), 0.26)
	var light := AbilityFx.flash_light(colour, 3.0, 3.4)
	root.add_child(light)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(2.7, 1.0, 2.7), 0.30) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.34)
	tween.tween_property(light, "light_energy", 0.0, 0.30)
	tween.set_parallel(false)
	tween.tween_interval(0.06)
	tween.tween_callback(root.queue_free)


## A chain's hops: from the body to every point in turn, each leg a jagged arc,
## each node a halo. All the legs live in one mesh - a chain of six is six
## surfaces, not six nodes - and only the halos are separate, because each one
## blooms on its own beat. The tail point's halo is the big one: it is the node
## the chain ended on.
static func chain_web(parent: Node3D, from: Vector3, points: Array,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcChainWeb", from)
	var vertices := PackedVector3Array()
	var nodes: Array[Vector3] = []
	var cursor := from
	for entry in points:
		if nodes.size() >= 8:
			break
		if not (entry is Vector3):
			continue
		var point: Vector3 = entry
		if point.distance_squared_to(cursor) < 0.0001:
			continue
		var arc := _jagged(cursor, point, 7)
		for index in arc.size() - 1:
			vertices.append(arc[index] - from)
			vertices.append(arc[index + 1] - from)
		nodes.append(point - from)
		cursor = point
	if nodes.is_empty():
		root.queue_free()
		return
	# Each leg is drawn as a run of stretched soft sprites rather than as
	# `PRIMITIVE_LINES`: a line primitive is one pixel wide whatever the camera
	# does, and a one-pixel lightning bolt is invisible in a fight. The sprites
	# keep the same jagged polyline, joined end to end.
	var bolt_materials: Array[StandardMaterial3D] = []
	for index in range(0, vertices.size() - 1, 2):
		var from_point := vertices[index]
		var to_point := vertices[index + 1]
		var span := to_point - from_point
		var length := span.length()
		if length < 0.001:
			continue
		var dir := span / length
		var right := dir.cross(Vector3.UP)
		if right.length_squared() < 0.000001:
			right = Vector3.RIGHT
		right = right.normalized()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.055, length * 1.08)
		var bolt_material := AbilityFx.sprite_material(
			AbilityFx.soft_dot_texture(), true, colour)
		quad.material = bolt_material
		bolt_materials.append(bolt_material)
		var bolt := MeshInstance3D.new()
		bolt.mesh = quad
		bolt.basis = Basis(right, dir, right.cross(dir))
		bolt.position = from_point + span * 0.5
		bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bolt)
	for index in nodes.size():
		var last := index == nodes.size() - 1
		var halo := _soft_sprite(root, Vector2.ONE * (1.0 if last else 0.55), colour,
			nodes[index])
		var halo_material := AbilityFx.sprite_tint(halo)
		halo.scale = Vector3.ONE * 0.4
		var beat := halo.create_tween()
		beat.tween_interval(0.04 * float(index))
		beat.tween_property(halo, "scale", Vector3.ONE * (2.0 if last else 1.5),
			0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		beat.parallel().tween_property(halo_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.0), 0.24)
	var light := AbilityFx.flash_light(colour, 2.6, 4.0)
	light.position = nodes[nodes.size() - 1]
	root.add_child(light)
	var tween := root.create_tween()
	tween.set_parallel(true)
	for bolt_material in bolt_materials:
		tween.tween_property(bolt_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.0), 0.26)
	tween.tween_property(light, "light_energy", 0.0, 0.24)
	tween.set_parallel(false)
	tween.tween_interval(0.04)
	tween.tween_callback(root.queue_free)


## A planted charge. It pulses on the ground with a ring of studs holding it
## down, and the pulse shortens as the fuse runs out - the accelerating beat is
## the warning, so it has to be the same on both peers and is built from `delay`,
## never from a timer. Detonation is one flash, one shell and a cone of sparks.
## The studs free themselves, the flare is scheduled behind an interval: nothing
## here is a callback that could land on a different frame than the beat it
## belongs to, and freeing the collar at the fuse is also what keeps the effect
## inside its node budget.
static func bomb_charge(parent: Node3D, at: Vector3, radius: float,
		delay: float, colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcBombCharge", at)
	var reach := clampf(radius, 0.8, 6.0)
	var fuse := maxf(delay, 0.12)
	var orb_material := AbilityFx.glow_material(colour, 2.2, 0.95)
	var orb := Geo.sphere(root, clampf(reach * 0.17, 0.16, 0.44), Vector3.UP * 0.30,
		orb_material)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var stud_material := Geo.material(Color(colour.r * 0.28, colour.g * 0.28,
		colour.b * 0.28), 0.35, 0.45)
	stud_material.emission_enabled = true
	stud_material.emission = colour
	stud_material.emission_energy_multiplier = 1.1
	stud_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var studs := MeshInstance3D.new()
	studs.mesh = _stud_ring_mesh(clampf(reach * 0.5, 0.35, 1.4), 8)
	studs.material_override = stud_material
	studs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(studs)
	# The collar frees itself on its own clock: when the fuse ends there is
	# nothing holding the ground down, and no callback has to remember that.
	var burn := studs.create_tween()
	burn.tween_interval(fuse)
	burn.tween_callback(studs.queue_free)
	var fuse_spark := _soft_sprite(root, Vector2.ONE * 0.24, Color(1.0, 0.92, 0.66),
		Vector3.UP * 0.44)
	var fuse_material := AbilityFx.sprite_tint(fuse_spark)
	fuse_spark.scale = Vector3.ONE * 0.7
	var shell_material := AbilityFx.glow_material(colour, 2.6, 0.42)
	var shell := Geo.sphere(root, reach * 0.44, Vector3.UP * 0.42, shell_material)
	shell.scale = Vector3.ONE * 0.01
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core := _soft_sprite(root, Vector2.ONE * reach * 0.9,
		Color(1.0, 0.98, 0.9, 0.0), Vector3.UP * 0.42)
	var core_material := AbilityFx.sprite_tint(core)
	core.scale = Vector3.ONE * 0.3
	# The cone of sparks is five streaked quads held invisible until the fuse
	# ends, each on its own interval. Quads rather than a particle system
	# because the cone has to leave on the fuse's beat: a CPU emitter can only
	# be switched on, and switching it on is exactly the callback this effect
	# cannot have.
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_at(at, 13)
	for index in 5:
		var angle := TAU * float(index) / 5.0 + rng.randf_range(-0.20, 0.20)
		var direction := Vector3(cos(angle), rng.randf_range(1.1, 2.1),
			sin(angle)).normalized()
		var spark := _streak(root, rng.randf_range(0.55, 0.85), 0.09, colour,
			direction)
		spark.position = Vector3.UP * 0.4
		spark.scale = Vector3(0.3, 0.6, 0.6)
		var spark_material := AbilityFx.sprite_tint(spark)
		spark_material.albedo_color = Color(colour.r, colour.g, colour.b, 0.0)
		var fly := spark.create_tween()
		fly.tween_interval(fuse)
		fly.tween_property(spark_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.95), 0.04)
		fly.parallel().tween_property(spark, "scale", Vector3.ONE, 0.10)
		fly.parallel().tween_property(spark, "position",
			Vector3.UP * 0.4 + direction * reach * 0.8, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fly.tween_property(spark_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.0), 0.26)
	var light := AbilityFx.flash_light(colour, 1.8, 4.0)
	light.position = Vector3.UP * 0.5
	root.add_child(light)
	var tween := root.create_tween()
	var spent := 0.0
	var beat := minf(0.30, fuse * 0.45)
	var pulses := 0
	while spent + beat < fuse and pulses < 40:
		tween.tween_property(orb, "scale", Vector3.ONE * 1.3, beat * 0.4)
		tween.parallel().tween_property(orb_material, "emission_energy_multiplier",
			6.5, beat * 0.4)
		tween.parallel().tween_property(fuse_spark, "scale", Vector3.ONE * 1.6,
			beat * 0.4)
		tween.tween_property(orb, "scale", Vector3.ONE, beat * 0.6)
		tween.parallel().tween_property(orb_material, "emission_energy_multiplier",
			2.0, beat * 0.6)
		tween.parallel().tween_property(fuse_spark, "scale", Vector3.ONE * 0.7,
			beat * 0.6)
		spent += beat
		beat = maxf(0.05, beat * 0.74)
		pulses += 1
	tween.tween_interval(maxf(fuse - spent, 0.0))
	tween.set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE, 0.26) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.32)
	tween.tween_property(orb, "scale", Vector3.ONE * 0.2, 0.2)
	tween.tween_property(orb_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.2)
	tween.tween_property(fuse_material, "albedo_color",
		Color(1.0, 0.92, 0.66, 0.0), 0.08)
	tween.set_parallel(false)
	tween.tween_interval(0.55)
	tween.tween_callback(root.queue_free)
	# The flash and its light run on their own clocks, each held behind an
	# interval the length of the fuse: the detonation is a scheduled beat, so no
	# callback can arrive a frame late and drag the whole chain with it.
	var flash := core.create_tween()
	flash.tween_interval(fuse)
	flash.tween_property(core_material, "albedo_color",
		Color(1.0, 0.98, 0.9, 0.95), 0.03)
	flash.parallel().tween_property(core, "scale", Vector3.ONE, 0.10) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	flash.tween_property(core_material, "albedo_color",
		Color(1.0, 0.98, 0.9, 0.0), 0.28)
	var flare := light.create_tween()
	flare.tween_interval(fuse)
	flare.tween_property(light, "light_energy", 7.5, 0.02)
	flare.tween_property(light, "light_energy", 0.0, 0.34)


## A pressure front, not a ring: the torus is the leading edge, the flattened
## sphere is the air behind it, and six flat spikes give the front a direction.
## Everything is sized from `radius` so the read and the damage agree.
static func blast_front(parent: Node3D, at: Vector3, radius: float,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcBlastFront", at)
	var reach := maxf(radius, 0.6)
	var ring := _flare_ring(root, colour, 0.85, 0.05)
	ring.position = Vector3.UP * 0.06
	ring.scale = Vector3(0.3, 1.0, 0.3)
	var ring_material := ring.material_override as StandardMaterial3D
	var dome_material := AbilityFx.glow_material(colour, 1.7, 0.34)
	var dome := Geo.sphere(root, reach * 0.55, Vector3.UP * 0.02, dome_material)
	dome.scale = Vector3(0.2, 0.15, 0.2)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_at(at, 17)
	for index in 6:
		var angle := TAU * float(index) / 6.0 + rng.randf_range(-0.10, 0.10)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var spike := _streak(root, reach * 1.05, 0.12, colour, direction)
		spike.position = direction * reach * 0.3 + Vector3.UP * 0.05
		spike.scale = Vector3(0.3, 1.0, 1.0)
		var material := AbilityFx.sprite_tint(spike)
		material.albedo_color = Color(colour.r, colour.g, colour.b, 0.8)
		var beat := spike.create_tween()
		beat.tween_property(spike, "position",
			direction * reach * 0.62 + Vector3.UP * 0.05, 0.20) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		beat.parallel().tween_property(spike, "scale", Vector3.ONE, 0.20)
		beat.parallel().tween_property(material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.0), 0.24)
	var light := AbilityFx.flash_light(colour, 3.2, reach * 3.0)
	root.add_child(light)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(reach, 1.0, reach), 0.26) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.30)
	tween.tween_property(dome, "scale", Vector3(1.0, 0.32, 1.0), 0.24) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(dome_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.28)
	tween.tween_property(light, "light_energy", 0.0, 0.30)
	tween.set_parallel(false)
	tween.tween_interval(0.06)
	tween.tween_callback(root.queue_free)


## A gout of liquid thrown off a hit: three short ballistic arcs on three
## headings, plus the wet mark spreading underneath. The droplets are soft
## additive quads on a cone-shaped emission - gravity bends the cone into an arc,
## which a straight-line burst cannot fake.
static func splash_gout(parent: Node3D, at: Vector3, radius: float,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcSplashGout", at)
	var reach := maxf(radius, 0.5)
	var wet := _flare_ring(root, colour.darkened(0.55), 0.45, 0.16, false)
	wet.position = Vector3.UP * 0.04
	wet.scale = Vector3(0.25, 1.0, 0.25)
	var wet_material := wet.material_override as StandardMaterial3D
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_at(at, 23)
	for index in 3:
		var angle := TAU * float(index) / 3.0 + rng.randf_range(-0.45, 0.45)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var drops := AbilityFx.soft_spark_particles(colour, 12, 1.6, 3.6, 0.55, 0.05)
		drops.direction = (direction + Vector3.UP * 0.42).normalized()
		drops.spread = 8.0
		drops.emission_sphere_radius = 0.16
		drops.gravity = Vector3(0.0, -9.4, 0.0)
		drops.damping_min = 0.1
		drops.damping_max = 0.3
		drops.position = Vector3.UP * 0.22
		root.add_child(drops)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(wet, "scale", Vector3(reach, 1.0, reach), 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(wet_material, "albedo_color",
		Color(colour.r * 0.35, colour.g * 0.35, colour.b * 0.35, 0.0), 0.60)
	tween.set_parallel(false)
	tween.tween_interval(0.35)
	tween.tween_callback(root.queue_free)


## Thorns punching up out of the floor in a ring. The rise is staggered by
## 0.04 s per spike: a simultaneous ring reads as a decal, and the stagger is
## what makes it a set of separate things breaking the ground. Each spike grows
## from the floor up rather than from its own centre, so the root never floats.
## The dust is one puff spread over the whole ring instead of one per root - the
## stagger is shorter than a puff's own life, so six of them would read as this.
static func spike_ring(parent: Node3D, at: Vector3, radius: float,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcSpikeRing", at)
	var reach := clampf(radius, 0.7, 5.0)
	var ring := _flare_ring(root, colour, 0.5, 0.08)
	ring.position = Vector3.UP * 0.05
	ring.scale = Vector3(reach, 1.0, reach)
	var ring_material := ring.material_override as StandardMaterial3D
	var spike_material := Geo.material(colour.lightened(0.35), 0.2, 0.35)
	spike_material.emission_enabled = true
	spike_material.emission = colour
	spike_material.emission_energy_multiplier = 0.9
	spike_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dust := AbilityFx.spark_particles(Color("c9b18a"), 26, 1.2, 2.6, 0.7, 0.05)
	dust.emission_sphere_radius = reach * 0.8
	dust.flatness = 0.92
	dust.spread = 34.0
	dust.gravity = Vector3(0.0, 1.4, 0.0)
	dust.position = Vector3.UP * 0.08
	root.add_child(dust)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_at(at, 31)
	for index in 6:
		var angle := TAU * float(index) / 6.0 + rng.randf_range(-0.12, 0.12)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var height := rng.randf_range(0.9, 1.35)
		var foot := direction * reach * 0.82
		var spike := Geo.cylinder(root, 0.12, 0.0, height, Vector3.ZERO,
			spike_material, 5)
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spike.position = foot + Vector3.UP * 0.005
		spike.rotation = Vector3(0.0, angle, rng.randf_range(-0.12, 0.12))
		spike.scale = Vector3(1.0, 0.02, 1.0)
		var beat := spike.create_tween()
		beat.tween_interval(0.04 * float(index))
		beat.tween_property(spike, "scale", Vector3.ONE, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		beat.parallel().tween_property(spike, "position",
			foot + Vector3.UP * (height * 0.5), 0.12)
	var light := AbilityFx.flash_light(colour, 1.6, 3.0)
	light.position = Vector3.UP * 0.8
	root.add_child(light)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(reach * 1.15, 1.0, reach * 1.15),
		0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.34)
	tween.tween_property(light, "light_energy", 0.0, 0.34)
	tween.set_parallel(false)
	tween.tween_interval(0.55)
	tween.tween_callback(root.queue_free)


## A crescent wall of force thrown forward: an upright swept ribbon, a flatter
## band of the same arc along the floor, and the dust both drag with them. It
## opens to the forward heading and reaches about six metres, which is why it is
## not `ring` - a ring says "everything around me", this says "this way".
static func shockwave_arc(parent: Node3D, origin: Vector3, forward: Vector3,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.000001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var root := _root(parent, "ProcShockwaveArc", origin)
	var facing := Basis.looking_at(flat, Vector3.UP)
	var arc_mesh := AbilityFx.arc_ribbon_mesh(120.0, 26, 0.58, true)
	var wall_material := AbilityFx.ribbon_material(colour)
	# The wall stands on end: the ribbon's own plane is local XZ, so local X is the
	# swing's side, local -Z is world up and local Y faces down the line. Laid flat
	# (a yaw-only basis) it would be a band on the floor and nothing would read as
	# force moving forward.
	var side := flat.cross(Vector3.UP).normalized()
	var wall := MeshInstance3D.new()
	wall.mesh = arc_mesh
	wall.material_override = wall_material
	wall.basis = Basis(side, -flat, -Vector3.UP)
	wall.position = Vector3.UP * 0.8
	wall.scale = Vector3(0.4, 1.0, 0.4)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wall)
	var band_material := AbilityFx.ribbon_material(colour)
	var band := MeshInstance3D.new()
	band.mesh = arc_mesh
	band.material_override = band_material
	band.basis = facing
	band.position = Vector3.UP * 0.08
	band.scale = Vector3(0.5, 1.0, 0.5)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(band)
	var dust := AbilityFx.spark_particles(Color("c9b18a"), 24, 2.4, 5.2, 0.6, 0.05)
	dust.direction = flat
	dust.spread = 52.0
	dust.emission_sphere_radius = 0.4
	dust.gravity = Vector3(0.0, -1.6, 0.0)
	dust.position = flat * 0.8 + Vector3.UP * 0.12
	root.add_child(dust)
	var light := AbilityFx.flash_light(colour, 2.8, 6.0)
	light.position = flat * 2.0 + Vector3.UP * 0.9
	root.add_child(light)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(wall, "scale", Vector3(6.0, 1.0, 6.0), 0.34) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(band, "scale", Vector3(5.2, 1.0, 5.2), 0.30) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(wall_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.38)
	tween.tween_property(band_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.34)
	tween.tween_property(light, "light_energy", 0.0, 0.36)
	tween.set_parallel(false)
	tween.tween_interval(0.30)
	tween.tween_callback(root.queue_free)


## A whirl: two spiral sheets turning against each other and opening outward,
## over a low ring. The sheets are built as meshes rather than assembled from
## crescent ribbons because a ribbon of crescents reads as a pinwheel, and a
## pinwheel is a different idea from a vortex.
static func whirl_vortex(parent: Node3D, at: Vector3, radius: float,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcWhirlVortex", at)
	var reach := clampf(radius, 0.8, 6.0)
	var ring := _flare_ring(root, colour, 0.38, 0.07)
	ring.position = Vector3.UP * 0.05
	ring.scale = Vector3(reach, 1.0, reach)
	var ring_material := ring.material_override as StandardMaterial3D
	var lift := reach * 0.8
	var forward_material := AbilityFx.ribbon_material(colour)
	var back_material := AbilityFx.ribbon_material(colour.lightened(0.22))
	var sheet_a := MeshInstance3D.new()
	sheet_a.mesh = _spiral_mesh(1.0, 1.35, lift, 44)
	sheet_a.material_override = forward_material
	sheet_a.scale = Vector3(0.25, 0.35, 0.25)
	sheet_a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sheet_a)
	var sheet_b := MeshInstance3D.new()
	sheet_b.mesh = _spiral_mesh(-1.0, 1.35, lift, 44)
	sheet_b.material_override = back_material
	sheet_b.scale = Vector3(0.25, 0.35, 0.25)
	sheet_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sheet_b)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sheet_a, "scale", Vector3(reach, 1.0, reach), 0.50) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sheet_b, "scale", Vector3(reach, 1.0, reach), 0.50) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sheet_a, "rotation:y", TAU * 0.8, 0.55)
	tween.tween_property(sheet_b, "rotation:y", -TAU * 0.8, 0.55)
	tween.tween_property(forward_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.55)
	tween.tween_property(back_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.55)
	tween.tween_property(ring, "scale", Vector3(reach * 1.2, 1.0, reach * 1.2), 0.50)
	tween.tween_property(ring_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.55)
	tween.set_parallel(false)
	tween.tween_interval(0.05)
	tween.tween_callback(root.queue_free)


## A standing field. One node, not a sparkle every frame: `proc_aura.gd` owns the
## disc, the rune ring and the pulse on its own clock and frees itself when
## `seconds` run out. Nothing here checks whether the field is on anyone - the
## arena decides that, and it decides it the same way on both peers.
static func zone_field(parent: Node3D, at: Vector3, radius: float,
		seconds: float, colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var field := Aura.new()
	field.configure(colour, radius, seconds)
	parent.add_child(field)
	field.top_level = true
	field.global_position = at


## Healing motes: specks drawn in from a short radius and climbing into the
## chest, over a soft flash and a warm light. A plain CPU particle system has no
## attraction, so the pull is a *negative* radial acceleration with a light
## upward gravity - together they read as gathering instead of spraying.
## `power` (0..3) is the amount, not the radius: a bigger heal is more motes,
## not a bigger body.
static func heal_motes(parent: Node3D, at: Vector3, colour: Color,
		power: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcHealMotes", at)
	var strength := clampf(power, 0.0, 3.0)
	var chest := Vector3.UP * 1.05
	var motes := AbilityFx.soft_spark_particles(colour,
		clampi(int(10 + strength * 10.0), 10, 40), 0.6, 1.8, 0.9, 0.045)
	motes.emission_sphere_radius = maxf(0.45, 0.5 + 0.28 * strength)
	motes.direction = Vector3.UP
	motes.spread = 34.0
	motes.gravity = Vector3(0.0, 0.6, 0.0)
	motes.radial_accel_min = -3.2
	motes.radial_accel_max = -1.6
	motes.damping_min = 0.2
	motes.damping_max = 0.6
	motes.position = chest
	root.add_child(motes)
	var flash := _soft_sprite(root, Vector2.ONE * (0.9 + 0.35 * strength), colour,
		chest)
	var flash_material := AbilityFx.sprite_tint(flash)
	flash.scale = Vector3.ONE * 0.4
	var light := AbilityFx.flash_light(colour.lightened(0.18),
		1.6 + 0.5 * strength, 3.2)
	light.position = chest
	root.add_child(light)
	var pulse := flash.create_tween()
	pulse.tween_property(flash, "scale", Vector3.ONE * 1.5, 0.16) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	pulse.parallel().tween_property(flash_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.55), 0.16)
	pulse.tween_property(flash_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.42)
	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.45)
	tween.tween_interval(0.50)
	tween.tween_callback(root.queue_free)


## Coin glints: thin gold chips that pop up, turn over and fall back. They are
## one particle system, not twenty nodes - a glint is a shard of light, and the
## only thing an individual node would buy is a lighter budget. `power` (0..3)
## sets how many, from eight to twenty.
static func gold_glints(parent: Node3D, at: Vector3, colour: Color,
		power: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcGoldGlints", at)
	var strength := clampf(power, 0.0, 3.0)
	var glints := CPUParticles3D.new()
	glints.amount = clampi(int(8 + strength * 4.0), 8, 20)
	glints.lifetime = 0.62
	glints.one_shot = true
	glints.explosiveness = 1.0
	glints.local_coords = false
	glints.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	glints.emission_sphere_radius = 0.18
	glints.flatness = 0.45
	glints.direction = Vector3.UP
	glints.spread = 52.0
	glints.gravity = Vector3(0.0, -14.0, 0.0)
	glints.initial_velocity_min = 2.4
	glints.initial_velocity_max = 4.6
	glints.scale_amount_min = 0.7
	glints.scale_amount_max = 1.3
	glints.angle_min = 0.0
	glints.angle_max = 360.0
	glints.angular_velocity_min = -520.0
	glints.angular_velocity_max = 520.0
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.66, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.99, 0.9, 1.0),
		Color(colour.r, colour.g, colour.b, 1.0),
		Color(colour.r * 0.7, colour.g * 0.5, colour.b * 0.2, 0.8),
		Color(colour.r * 0.4, colour.g * 0.28, colour.b * 0.1, 0.0),
	])
	glints.color_ramp = gradient
	var quad := QuadMesh.new()
	quad.size = Vector2(0.10, 0.026) * (0.85 + 0.15 * strength)
	var shard_material := StandardMaterial3D.new()
	shard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shard_material.vertex_color_use_as_albedo = true
	shard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shard_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shard_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shard_material.disable_receive_shadows = true
	quad.material = shard_material
	glints.mesh = quad
	glints.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glints.position = Vector3.UP * 0.75
	root.add_child(glints)
	var light := AbilityFx.flash_light(colour, 1.4 + 0.7 * strength, 2.8)
	light.position = Vector3.UP * 0.7
	root.add_child(light)
	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.34)
	tween.tween_interval(0.32)
	tween.tween_callback(root.queue_free)


## A bleeding marker: a pool that keeps spreading under a wound that keeps
## dripping. The pool grows slower than the bleed lasts, so the last drops land
## on a pool that has already started to set. `at` is the floor point the marker
## belongs to; the drops fall from just above it, which is where a body's wound
## would be.
static func bleed_drip(parent: Node3D, at: Vector3, seconds: float,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcBleedDrip", at)
	var life := clampf(seconds, 0.4, 8.0)
	var tail := minf(0.4, life * 0.35)
	var pool := _pool(root, colour.darkened(0.5), 0.55)
	pool.scale = Vector3(0.3, 1.0, 0.3)
	var pool_material := pool.material_override as StandardMaterial3D
	var drops := CPUParticles3D.new()
	# Three droplets a cycle, one cycle every lifetime: a dribble, not a spray.
	drops.amount = 3
	drops.lifetime = 0.35
	drops.one_shot = false
	drops.explosiveness = 1.0
	drops.local_coords = false
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	drops.emission_sphere_radius = 0.07
	drops.direction = Vector3.DOWN
	drops.spread = 14.0
	drops.gravity = Vector3(0.0, -11.0, 0.0)
	drops.initial_velocity_min = 0.15
	drops.initial_velocity_max = 0.5
	drops.damping_min = 0.05
	drops.damping_max = 0.15
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.075
	quad.material = AbilityFx.particle_sprite_material(
		AbilityFx.soft_dot_texture(), colour, true)
	drops.mesh = quad
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.position = Vector3.UP * 0.92
	root.add_child(drops)
	var grow := pool.create_tween()
	grow.tween_property(pool, "scale", Vector3(0.58, 1.0, 0.58),
		maxf(life - tail, 0.1))
	grow.tween_property(pool_material, "albedo_color",
		Color(colour.r * 0.2, colour.g * 0.12, colour.b * 0.12, 0.0), tail)
	var tween := root.create_tween()
	tween.tween_interval(maxf(life - 0.02, 0.05))
	tween.tween_callback(root.queue_free)


## A searing internal wound: a small cross of light that flares and dies twice,
## with six embers climbing off it. The double beat is the whole point - a single
## flare is any other hit, two is something burning inside the body.
static func wound_sear(parent: Node3D, at: Vector3, colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcWoundSear", at + Vector3.UP * 1.05)
	var core := _soft_sprite(root, Vector2.ONE * 0.8, Color(1.0, 0.97, 0.86, 0.0))
	var core_material := AbilityFx.sprite_tint(core)
	core.scale = Vector3.ONE * 0.35
	var bar_a := _streak(root, 0.85, 0.07,
		Color(colour.r, colour.g, colour.b, 0.0), Vector3.RIGHT)
	var bar_b := _streak(root, 0.85, 0.07,
		Color(colour.r, colour.g, colour.b, 0.0), Vector3.UP)
	var bar_a_material := AbilityFx.sprite_tint(bar_a)
	var bar_b_material := AbilityFx.sprite_tint(bar_b)
	bar_a.scale = Vector3.ONE * 0.4
	bar_b.scale = Vector3.ONE * 0.4
	var embers := AbilityFx.soft_spark_particles(colour, 6, 0.4, 1.3, 0.6, 0.04)
	embers.gravity = Vector3(0.0, 0.9, 0.0)
	embers.spread = 30.0
	root.add_child(embers)
	var light := AbilityFx.flash_light(colour, 2.2, 2.6)
	root.add_child(light)
	var pulse := root.create_tween()
	for beat in 2:
		var peak := 1.0 if beat == 0 else 0.7
		pulse.tween_property(core, "scale", Vector3.ONE * (1.0 + 0.4 * peak), 0.06)
		pulse.parallel().tween_property(core_material, "albedo_color",
			Color(1.0, 0.97, 0.86, 0.9 * peak), 0.06)
		pulse.parallel().tween_property(bar_a_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.85 * peak), 0.06)
		pulse.parallel().tween_property(bar_b_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.85 * peak), 0.06)
		pulse.parallel().tween_property(light, "light_energy", 2.2 * peak, 0.06)
		pulse.tween_property(core, "scale", Vector3.ONE * 0.3, 0.11)
		pulse.parallel().tween_property(core_material, "albedo_color",
			Color(1.0, 0.97, 0.86, 0.0), 0.11)
		pulse.parallel().tween_property(bar_a_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.0), 0.11)
		pulse.parallel().tween_property(bar_b_material, "albedo_color",
			Color(colour.r, colour.g, colour.b, 0.0), 0.11)
		pulse.parallel().tween_property(light, "light_energy", 0.0, 0.11)
	pulse.tween_interval(0.40)
	pulse.tween_callback(root.queue_free)


## A level gained: a column of light punched straight up six metres with glyphs
## climbing inside it. The column is a cylinder with no shadow and additive
## faces, so it brightens what is behind it instead of blocking it - a light
## shaft that occludes is a wall. The glyphs read as writing without being
## letters, which is deliberate: the same effect has to serve every discipline.
static func level_pillar(parent: Node3D, at: Vector3, colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcLevelPillar", at)
	var ring := _flare_ring(root, colour, 0.45, 0.09)
	ring.position = Vector3.UP * 0.05
	ring.scale = Vector3(0.4, 1.0, 0.4)
	var ring_material := ring.material_override as StandardMaterial3D
	var column_material := AbilityFx.glow_material(colour, 3.0, 0.38)
	var column := Geo.cylinder(root, 0.32, 0.62, 6.0, Vector3.UP * 3.0,
		column_material, 10)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A cylinder's origin is its centre, so the shaft rises by lifting the centre
	# while the height grows: scaling alone would stretch it out of the floor and
	# into the sky at the same time.
	column.scale = Vector3(0.6, 0.02, 0.6)
	column.position = Vector3.UP * 0.06
	var light := AbilityFx.flash_light(colour, 4.0, 5.0)
	light.position = Vector3.UP * 1.6
	root.add_child(light)
	for index in 5:
		var angle := TAU * float(index) / 5.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var glyph := _shard(root, Vector2(0.26, 0.26),
			Color(1.0, 0.98, 0.9, 0.0), direction * 0.22 + Vector3.UP * 0.5)
		var glyph_material := AbilityFx.sprite_tint(glyph)
		glyph.basis = Basis.looking_at(direction, Vector3.UP)
		glyph.scale = Vector3.ONE * 0.5
		var beat := glyph.create_tween()
		beat.tween_interval(0.10 + 0.13 * float(index))
		beat.tween_property(glyph_material, "albedo_color",
			Color(1.0, 0.98, 0.9, 0.9), 0.08)
		beat.tween_property(glyph, "position", direction * 0.3 + Vector3.UP * 5.2,
			0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		beat.parallel().tween_property(glyph_material, "albedo_color",
			Color(1.0, 0.98, 0.9, 0.0), 0.75)
	var tail := column.create_tween()
	tail.tween_interval(0.45)
	tail.tween_property(column, "scale", Vector3(0.35, 0.001, 0.35), 0.55)
	tail.parallel().tween_property(column, "position", Vector3.UP * 0.06, 0.55)
	tail.parallel().tween_property(column_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.55)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(column, "scale", Vector3.ONE, 0.16) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(column, "position", Vector3.UP * 3.0, 0.16) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "scale", Vector3(1.7, 1.0, 1.7), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.50)
	tween.tween_property(light, "light_energy", 0.0, 0.55)
	tween.set_parallel(false)
	tween.tween_interval(0.55)
	tween.tween_callback(root.queue_free)


## Two impact flashes on the same point, 0.08 s apart, the second the bigger.
## The gap is short enough to read as one hit with an echo rather than two hits,
## which is why both draw from the same point and neither moves.
static func double_flash(parent: Node3D, at: Vector3, colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcDoubleFlash", at)
	var first := _soft_sprite(root, Vector2.ONE * 0.7,
		Color(colour.r, colour.g, colour.b, 0.0))
	var first_material := AbilityFx.sprite_tint(first)
	var second := _soft_sprite(root, Vector2.ONE * 1.15,
		Color(1.0, 0.98, 0.92, 0.0))
	var second_material := AbilityFx.sprite_tint(second)
	var ring := _flare_ring(root, colour, 0.6, 0.12)
	ring.position = Vector3.UP * 0.05
	ring.scale = Vector3(0.3, 1.0, 0.3)
	var ring_material := ring.material_override as StandardMaterial3D
	var light := AbilityFx.flash_light(colour, 3.4, 3.2)
	root.add_child(light)
	first.scale = Vector3.ONE * 0.5
	second.scale = Vector3.ONE * 0.4
	var strike := first.create_tween()
	strike.tween_property(first, "scale", Vector3.ONE * 1.35, 0.05) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	strike.parallel().tween_property(first_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.85), 0.05)
	strike.tween_property(first, "scale", Vector3.ONE * 1.6, 0.12)
	strike.parallel().tween_property(first_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.12)
	var echo := second.create_tween()
	echo.tween_interval(0.08)
	echo.tween_property(second, "scale", Vector3.ONE * 1.7, 0.06) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	echo.parallel().tween_property(second_material, "albedo_color",
		Color(1.0, 0.98, 0.92, 0.95), 0.06)
	echo.tween_property(second, "scale", Vector3.ONE * 2.0, 0.16)
	echo.parallel().tween_property(second_material, "albedo_color",
		Color(1.0, 0.98, 0.92, 0.0), 0.16)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(0.95, 1.0, 0.95), 0.22) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.26)
	tween.tween_property(light, "light_energy", 0.0, 0.30)
	tween.set_parallel(false)
	tween.tween_interval(0.02)
	tween.tween_callback(root.queue_free)


## A critical hit: six rays thrown out and pulled back around a white-hot core.
## The rays sit on a cone rather than a flat star so the burst has depth from any
## camera angle - a screen-aligned star disappears the moment the view turns.
static func crit_star(parent: Node3D, at: Vector3, colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcCritStar", at)
	var core := _soft_sprite(root, Vector2.ONE * 1.05,
		Color(1.0, 0.99, 0.94, 0.95))
	var core_material := AbilityFx.sprite_tint(core)
	core.scale = Vector3.ONE * 0.4
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_at(at, 47)
	for index in 6:
		var angle := TAU * float(index) / 6.0 + rng.randf_range(-0.08, 0.08)
		var direction := Vector3(cos(angle),
			0.55 + rng.randf_range(-0.12, 0.12), sin(angle)).normalized()
		var ray := _streak(root, rng.randf_range(1.1, 1.6), 0.075, colour, direction)
		ray.position = direction * 0.45
		ray.scale = Vector3(0.4, 1.0, 1.0)
		var ray_material := AbilityFx.sprite_tint(ray)
		ray_material.albedo_color = Color(colour.r, colour.g, colour.b, 0.0)
		var out := ray.create_tween()
		out.tween_property(ray, "scale", Vector3.ONE * 1.1, 0.07) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		out.parallel().tween_property(ray_material, "albedo_color",
			Color(1.0, 0.98, 0.94, 0.9), 0.07)
		out.tween_property(ray, "position", direction * 1.0, 0.16)
		out.parallel().tween_property(ray, "scale", Vector3(0.25, 0.4, 0.4), 0.16)
		out.parallel().tween_property(ray_material, "albedo_color",
			Color(1.0, 0.98, 0.94, 0.0), 0.16)
	var pulse := core.create_tween()
	pulse.tween_property(core, "scale", Vector3.ONE * 1.2, 0.06) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	pulse.parallel().tween_property(core_material, "albedo_color",
		Color(1.0, 0.99, 0.94, 1.0), 0.06)
	pulse.tween_property(core, "scale", Vector3.ONE * 0.6, 0.20)
	pulse.parallel().tween_property(core_material, "albedo_color",
		Color(1.0, 0.99, 0.94, 0.0), 0.20)
	var light := AbilityFx.flash_light(colour, 3.0, 3.0)
	light.position = Vector3.UP * 0.4
	root.add_child(light)
	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.26)
	tween.tween_interval(0.08)
	tween.tween_callback(root.queue_free)


## A body dying. Not an explosion: the flash is dark red and mixed rather than
## added, the ring stays low and the ashes go up, so the read is "something went
## out" instead of "something hit". `power` scales the whole thing, not the
## duration: a bigger kill is bigger, not longer.
static func kill_pop(parent: Node3D, at: Vector3, colour: Color,
		power: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := _root(parent, "ProcKillPop", at)
	var size := 1.0 + clampf(power, 0.0, 3.0) * 0.30
	var flash := _soft_sprite(root, Vector2.ONE * 1.15 * size,
		Color(clampf(colour.r * 0.40, 0.05, 1.0), 0.05, 0.05, 0.8),
		Vector3.UP * 0.9, false)
	var flash_material := AbilityFx.sprite_tint(flash)
	flash.scale = Vector3.ONE * 0.5
	var ring := _flare_ring(root, colour.darkened(0.35), 0.22, 0.1)
	ring.position = Vector3.UP * 0.06
	ring.scale = Vector3(0.25, 1.0, 0.25)
	var ring_material := ring.material_override as StandardMaterial3D
	var ashes := AbilityFx.soft_spark_particles(Color(0.45, 0.34, 0.30), 10,
		0.5, 1.5, 1.0, 0.05)
	ashes.gravity = Vector3(0.0, 0.5, 0.0)
	ashes.spread = 46.0
	ashes.position = Vector3.UP * 0.45
	root.add_child(ashes)
	var light := AbilityFx.flash_light(Color(0.70, 0.12, 0.08), 1.6 * size,
		2.6 * size)
	light.position = Vector3.UP * 0.8
	root.add_child(light)
	var flash_beat := flash.create_tween()
	flash_beat.tween_property(flash, "scale", Vector3.ONE * size, 0.12) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	flash_beat.parallel().tween_property(flash_material, "albedo_color",
		Color(clampf(colour.r * 0.40, 0.05, 1.0), 0.05, 0.05, 0.0), 0.26)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(2.0 * size, 1.0, 2.0 * size),
		0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.44)
	tween.tween_property(light, "light_energy", 0.0, 0.34)
	tween.set_parallel(false)
	tween.tween_interval(0.60)
	tween.tween_callback(root.queue_free)


# --- Shared building blocks ------------------------------------------------
# Everything above is assembled from these. They exist so that a new proc only
# has to say what it looks like: the node discipline (world anchored, shadow
# off, freed by a tween) lives here once instead of in eighteen places.

## One world-anchored root per effect. `top_level` keeps the flash where the
## thing happened even when the body it came off keeps walking, and the root is
## the only node a tween has to free - every child goes with it.
static func _root(parent: Node3D, node_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	parent.add_child(node)
	node.top_level = true
	node.global_position = at
	return node


## A flat ring of unit radius lying on the floor: one mesh, so a tween on `scale`
## is the expansion and a tween on the material is the fade. `additive` off is
## for the wet marks and blood, which have to darken the floor rather than add
## light to it.
static func _flare_ring(parent: Node3D, colour: Color, alpha: float,
		thickness: float = 0.08, additive: bool = true) -> MeshInstance3D:
	# A painted ring decal rather than a torus: the texture carries the wobble and
	# the hot inner edge that a smooth primitive cannot, and one quad is cheaper
	# than forty-eight torus segments. `thickness` is kept for the call sites that
	# sized the old band; the paint owns the band width now.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_texture = Vfx.texture(Vfx.RING)
	material.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive \
		else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.disable_receive_shadows = true
	if additive:
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.rotation.x = -PI * 0.5
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## A flat, very shallow cylinder: the pool under a bleed. A torus with a tiny
## hole would read as a fat donut, so this is a disc with a real surface.
static func _pool(parent: Node3D, colour: Color, alpha: float) -> MeshInstance3D:
	# A splat, not a cylinder: a bleeding body leaves an irregular mark with
	# satellite drops, and the painted sheet has that shape in it already.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_texture = Vfx.texture(Vfx.SPLAT)
	material.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.disable_receive_shadows = true
	quad.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.rotation.x = -PI * 0.5
	instance.position = Vector3.UP * 0.02
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## A thin additive quad with the tint in emission. Its material rides on the
## QuadMesh, not on `material_override`, so `AbilityFx.sprite_tint` can reach it
## and a fade is one property tween.
static func _shard(parent: Node3D, size: Vector2, tint: Color,
		at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 2.2
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	quad.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## The same quad, but its long axis laid along `direction`: splinters, rays and
## spikes. Built from an explicit basis rather than a billboard, because a
## camera-facing quad flattens the ray back onto screen space and a ray that
## always reads horizontal is not a ray.
static func _streak(parent: Node3D, length: float, thickness: float,
		tint: Color, direction: Vector3) -> MeshInstance3D:
	var instance := _shard(parent, Vector2(maxf(length, 0.02), thickness), tint)
	var axis := Vector3.FORWARD
	if direction.length_squared() > 0.0001:
		axis = direction.normalized()
	var up := Vector3.UP
	if absf(axis.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var side := axis.cross(up).normalized()
	var plane := side.cross(axis).normalized()
	instance.basis = Basis(axis, plane, side)
	return instance


## A camera-facing soft dot: the repo's standard flash core and halo. `additive`
## off is the dark flash a kill leaves, which must darken instead of add.
static func _soft_sprite(parent: Node3D, size: Vector2, tint: Color,
		at: Vector3 = Vector3.ZERO, additive: bool = true) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = AbilityFx.sprite_material(AbilityFx.soft_dot_texture(),
		additive, tint)
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## Seed from the quantised point plus a per-effect salt: two peers derive the
## same scatter for the same impact, and two impacts near each other do not
## repeat each other's pattern.
static func _seed_at(at: Vector3, salt: int) -> int:
	var hashed := absf(at.x * 13.0) * 977.0 + absf(at.z * 7.0) * 613.0 \
		+ absf(at.y * 5.0) * 379.0 + float(salt) * 101.0
	return int(hashed)


## The charge's collar: eight low faceted studs on one surface. One draw instead
## of eight nodes, which is what leaves the budget for the shell it detonates
## into.
static func _stud_ring_mesh(ring_radius: float, count: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for index in count:
		var angle := TAU * float(index) / float(count)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var foot := direction * ring_radius
		var half := side * 0.075
		var out := direction * 0.075
		var base := vertices.size()
		vertices.append(foot - half - out)
		vertices.append(foot + half - out)
		vertices.append(foot + half + out)
		vertices.append(foot - half + out)
		vertices.append(foot + direction * 0.02 + Vector3.UP * 0.24)
		for _corner in 5:
			normals.append(direction)
		for corner in 4:
			indices.append_array([base + corner, base + (corner + 1) % 4, base + 4])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One spiral sheet for the vortex: a band that climbs as it widens, its vertex
## alpha fading toward the rim. `hand` flips the winding, so two of these turned
## against each other read as a spiral and its reflection rather than as the same
## sheet twice.
static func _spiral_mesh(hand: float, turns: float, lift: float,
		segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for index in segments + 1:
		var t := float(index) / float(segments)
		var angle := TAU * turns * t * hand
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var radius := 0.18 + 0.82 * t
		var fade := pow(clampf(1.0 - t, 0.0, 1.0), 0.7)
		var base_y := 0.06 + lift * t
		var top_y := base_y + lift * 0.55 * (1.0 - t * 0.5)
		vertices.append(direction * radius + Vector3.UP * base_y)
		colors.append(Color(1.0, 1.0, 1.0, fade * 0.10))
		vertices.append(direction * radius + Vector3.UP * top_y)
		colors.append(Color(1.0, 1.0, 1.0, fade * 0.85))
	for index in segments:
		var base := index * 2
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
