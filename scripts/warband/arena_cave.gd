class_name ArenaCave
extends Node3D
## One chamber of the Weeping Hollow, cut out of the delve's own floor and stood
## at the arena's height: the place a warband fights in.
##
## The Hollow already authors the cave. `delve_layout.gd` names every room it is
## dug from - the watchers' den, the drowned gallery, the ossuary, the pale
## garden, the black mere, the bone chapel, the rooted hall, the old workings,
## the demons' ring and Gorehorn's lair - and the rooms are drawn by the floor
## surface (`delve_floor.gd`), the rock skin (`delve_rock.gd`) and the dressing
## (`delve_dressing.gd`). This node builds **one** of them, exactly as the delve
## builds it, and nothing else: the room's own ground, the rock nearest it on
## every side, the vaulted roof over it, the dripstone and breakdown grown in it,
## the lights the plan hangs and the props it stands. It is the same cave a party
## would have walked into below; the arena just uses it for a fight, drawn fresh
## every bout (`pick_room`), so no two bouts are fought in the same room.
##
## What a descent scatters across eleven areas cannot be one room, so the ways out
## of the chamber are shut: the rock of the walls is drawn straight on across every
## opening the plan cut (`Rock.skin(index, true)`), a collision of the room's own
## keeps a body from walking out through one, and the rubble that came down with it
## lies at its foot. The chamber reads as what it is - a hall whose ways on
## collapsed - and the fight has nowhere to go but into itself.
##
## The room is stood at `centre()`, far above the campaign, with its own floor's
## middle on the origin: the cave frame's own plan coordinates are offsets inside
## `_node`, so everything below (the floor, the skin, the props, a body's post) is
## authored at the plan's coordinates and never moved by hand.

const Layout = preload("res://scripts/warband/delve_layout.gd")
const Floor = preload("res://scripts/warband/delve_floor.gd")
const Rock = preload("res://scripts/warband/delve_rock.gd")
const Dressing = preload("res://scripts/warband/delve_dressing.gd")
const CaveKit = preload("res://scripts/world/cave_kit.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const NavScript = preload("res://scripts/warband/squad_nav.gd")

## How high off the campaign's ground the chamber stands: out of sight of the
## wood, and far enough that the heightfield's own crest cannot reach it. The
## roguelite's islands take their own heights above this.
const LIFT := 260.0
## The lift every body in the world is spawned clear of its ground by.
const SPAWN_LIFT := 0.12
## The smallest a room may be across either way to hold a fight: three bodies a
## side and room to circle.
const MIN_SIDE := 10.0
## How far apart the bodies of one line stand, at most; and the closest the line
## may be squeezed in a narrow room.
const SPREAD := 4.4
const TIGHT := 1.9
## How far in from the rock a body's post stands, and how close two posts may be.
const WALL_MARGIN := 2.2
const POST_GAP := 1.9
## How far a post keeps off anything already standing in the room - the dripstone
## that stops a body, a light, a prop, a way out.
const STOP_CLEARANCE := 0.9
## How thick the collision that shuts a way out stands, and how far it runs past
## the opening's jambs.
const SEAL_THICK := 1.0
const SEAL_JAMB := 1.2
## How far from the room's middle each line stands, along its long axis. The fight
## opens at a distance the room does not decide: a hall the size of the lair would
## put the two lines forty metres apart - ten seconds of walking before anybody is
## in reach - and a chamber the size of the apse would put them in each other's
## faces. So the lines stand a share of the room's length out, floored and capped
## here.
const LINE_NEAR := 6.0
const LINE_REACH := 15.0
## Every room's rock, formations, lights and props are grown from the plan and the
## room's own index (`delve_dressing.gd`); the chambers' lights and props are drawn
## from this seed, the way the delve draws them.
const SEED := 6607

## The room this chamber was built from (`Layout.ROOMS` id), or "".
var room_id := ""
## The area of the floor it belongs to (`Layout.AREAS` key).
var area := ""
## The room's index in `Layout.ROOMS`, or -1.
var index := -1
## The camera's air while the eye is in here, over the campaign's own sky.
var environment: Environment = null
## The chamber's map for the squad (`squad_nav.gd`).
var nav = null

## The room in the cave's frame: where the plan cut it.
var _rect := Rect2()
var _inner := Rect2()
## The room's middle on the floor: how far the plan's frame is from this node's.
var _offset := Vector3.ZERO
## Everything the room draws, in the plan's frame.
var _node: Node3D = null
## The rock the room is cut into: its colliders.
var _solids: StaticBody3D = null
## Every light the room owns, the shaft's included.
var _lights: Array = []
## What no post may stand on: `[point, radius]` (cave x/z) for the ways out and
## everything the plan stands in the room.
var _keep_out: Array = []
## What already stops a body in the room: `[at, radius, tall]` for every formation
## grown tall enough to stop one.
var _stops: Array = []
## The flat centre of each line, in the plan's frame.
var _party_line := Vector2.ZERO
var _foe_line := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _cave_ins := 0


# --- the plan -------------------------------------------------------------------

## The room's own centre, in the world.
static func centre() -> Vector3:
	return Vector3(0.0, LIFT, 0.0)


## Every room of the Hollow a bout can be fought in: the halls and chambers the
## plan cuts (`Layout.ROOMS`), not the ways between them - a tunnel is a passage,
## not a room to fight in - and never a room too narrow to stand three bodies a
## side in.
static func room_ids() -> Array[String]:
	var out: Array[String] = []
	for room in Layout.ROOMS:
		if bool(room.get("tunnel", false)):
			continue
		var rect: Rect2 = room["rect"]
		if minf(rect.size.x, rect.size.y) < MIN_SIDE:
			continue
		out.append(str(room["id"]))
	return out


## A chamber for this bout: one of `room_ids()`, drawn from `rng`, never the one
## the last bout was fought in while there is another to draw.
static func pick_room(rng: RandomNumberGenerator, avoid: String = "") -> String:
	var ids := room_ids()
	if ids.is_empty():
		return ""
	var pool: Array[String] = []
	for id in ids:
		if id != avoid:
			pool.append(id)
	if pool.is_empty():
		pool = ids
	return pool[rng.randi() % pool.size()]


# --- reading -----------------------------------------------------------------

## What the HUD calls the chamber: the area's own name (`THE OSSUARY`).
func room_label() -> String:
	return Layout.area_name(area)


## Whether a world point is inside the chamber: under its roof and over its floor.
func contains(point: Vector3) -> bool:
	if _node == null:
		return false
	var local := to_local(point) + _offset
	if local.y < Floor.LOW - 3.0 or local.y > Layout.TOP + 6.0:
		return false
	return _rect.has_point(Vector2(local.x, local.z))


## Every light the chamber owns.
func light_count() -> int:
	return _lights.size()


## The chamber as a box in the world: the room's own floor and the rock over it,
## read off the plan's rectangle. Anything that has to frame the room or check what
## is inside it - a camera, a regression - asks this rather than the plan.
func bounds() -> AABB:
	if _node == null:
		return AABB()
	var near := _flat_to_world(_rect.position.x, _rect.position.y)
	var far := _flat_to_world(_rect.end.x, _rect.end.y)
	var bottom := to_global(Vector3(0.0, Floor.low(index), 0.0) - _offset).y
	var top := to_global(Vector3(0.0, Rock.ceiling(index), 0.0) - _offset).y
	return AABB(Vector3(minf(near.x, far.x), bottom, minf(near.z, far.z)),
		Vector3(absf(far.x - near.x), top - bottom, absf(far.z - near.z)))


## The ways out the plan cut into this room, in the world: `{at, width}` for each
## opening, `at` the middle of it on the room's own line. Every one of them is
## filled with rock, and the fall that shut it lies inside the foot of that rock.
func doorways() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var doors := Layout.doors()
	for door_index in Layout.doors_of(index):
		var door: Dictionary = doors[door_index]
		var mid: Vector2 = door["mid"]
		out.append({"at": _flat_to_world(mid.x, mid.y), "width": float(door["width"])})
	return out


## Stand both sides for a fight of `party_count` against `foe_count`: the world
## posts of each line and the yaw each side faces. The two lines stand either side
## of the room's middle along its long axis, each spread across its short one - a
## crossing, and neither side opening the fight with its back to a wall.
func seat(party_count: int, foe_count: int) -> Dictionary:
	_party_line = _line_centre(-1.0)
	_foe_line = _line_centre(1.0)
	var taken: Array = []
	var party := _line_posts(_party_line, party_count, taken)
	var foes := _line_posts(_foe_line, foe_count, taken)
	var towards := _foe_line - _party_line
	var yaw := atan2(-towards.x, -towards.y)
	return {
		"party": _world_posts(party),
		"foes": _world_posts(foes),
		"party_yaw": yaw,
		"foe_yaw": wrapf(yaw + PI, -PI, PI),
	}


# --- the build ---------------------------------------------------------------

## Cut the chamber `id` out of the plan and stand it at `centre()`. The node is
## already in the tree: the rock, the floor and a body's post are all read in the
## cave's own frame and offset once, here.
func build(id: String, seed_value: int = SEED) -> void:
	room_id = id
	index = Layout.room_index(id)
	if index < 0:
		push_error("arena cave: the Hollow has no room '%s'" % id)
		return
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	var room: Dictionary = Layout.ROOMS[index]
	area = str(room["area"])
	_rect = room["rect"]
	_inner = _rect.grow(-WALL_MARGIN)
	var middle := _rect.get_center()
	_offset = Vector3(middle.x, Floor.height(middle.x, middle.y), middle.y)
	position = centre()
	name = "ArenaChamber_%s" % id
	_node = Node3D.new()
	_node.name = "Room"
	_node.position = -_offset
	add_child(_node)
	_keep_out = Layout.crowd_keep_out(index)
	_stops = Dressing.grown_stops(index)
	_build_shell()
	# The rock skin over the walls and roof, the dripstone and breakdown grown
	# around it, and the colliders that stand in the way of a body: the delve's own
	# room dressing, on one room, with every way out closed over.
	Dressing.dress_room(_node, index, true)
	_build_rope()
	_build_lights()
	_build_props()
	_build_air()
	_build_nav()


## The room's own floor, the roof over it and the rock nearest it, plus every way
## out shut. One merged mesh for the lot, one collider body under it - the same
## split the delve makes between what is drawn and what stops a body.
func _build_shell() -> void:
	var stone := Dressing.stone(area)
	_solids = StaticBody3D.new()
	_solids.name = "Rock"
	_solids.collision_layer = 1
	_solids.collision_mask = 0
	_node.add_child(_solids)
	var shell := VillageKit.Merged.new()
	shell.add(Floor.mesh(index), Transform3D.IDENTITY, stone["floor"])
	# The floor's own physics: the very vertices the room draws, so a foot, an
	# arrow or a thrown blade stops on the surface under it.
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(Floor.faces(index))
	var floor_holder := CollisionShape3D.new()
	floor_holder.shape = shape
	_solids.add_child(floor_holder)
	# The rock over the room's ceiling, from the rock's own top down to the room's.
	var top: float = Rock.ceiling(index)
	var ceiling := Vector3(_rect.size.x, maxf(0.05, Layout.TOP - top), _rect.size.y)
	var ceiling_at := Vector3(_rect.get_center().x, (top + Layout.TOP) * 0.5, _rect.get_center().y)
	VillageKit.add_box(shell, ceiling, ceiling_at, stone["roof"])
	_box_collider(ceiling, ceiling_at)
	# The rock the room is cut into. Every cell of it within the plan's own
	# `WALL_CELLS` of the room, whether the delve's full floor would have given it
	# to this room or to a neighbour: here there is no neighbour to draw it.
	var tall := Layout.TOP - Floor.LOW
	for block in _ring_rects():
		var wall: Rect2 = block
		var size := Vector3(wall.size.x, tall, wall.size.y)
		var at := Vector3(wall.get_center().x, (Layout.TOP + Floor.LOW) * 0.5, wall.get_center().y)
		VillageKit.add_box(shell, size, at, stone["wall"])
		_box_collider(size, at)
	_seal_the_ways()
	shell.commit(_node, "Shell", false)


## Every rock cell within `Layout.WALL_CELLS` of the room that is not some room's
## own floor, merged greedily into the fewest boxes - the same merge the delve's
## rock colliders use, read from this room's side of the plan instead of the
## floor's.
func _ring_rects() -> Array[Rect2]:
	var cells := Layout.cells_of(_rect).grow(Layout.WALL_CELLS)
	var cols := cells.size.x
	var rows := cells.size.y
	if cols <= 0 or rows <= 0:
		return []
	var open := PackedByteArray()
	open.resize(cols * rows)
	for row in rows:
		for col in cols:
			# A cell of any room's floor is a room, not this room's rock: a way out
			# is left open here and shut by `_seal_the_ways`.
			open[row * cols + col] = 0 if Layout.cell_room(cells.position.x + col,
				cells.position.y + row) < 0 else 1
	var used := PackedByteArray()
	used.resize(cols * rows)
	var out: Array[Rect2] = []
	for row in rows:
		var col := 0
		while col < cols:
			var key := row * cols + col
			if open[key] != 0 or used[key] != 0:
				col += 1
				continue
			var width := 1
			while col + width < cols and open[key + width] == 0 and used[key + width] == 0:
				width += 1
			var depth := 1
			while row + depth < rows:
				var whole := true
				var base := (row + depth) * cols + col
				for step in width:
					if open[base + step] != 0 or used[base + step] != 0:
						whole = false
						break
				if not whole:
					break
				depth += 1
			for dz in depth:
				var base := (row + dz) * cols + col
				for dx in width:
					used[base + dx] = 1
			out.append(_cell_rect(cells.position.x + col, cells.position.y + row, width, depth))
			col += width
	return out


## A run of raster cells as a rectangle in the cave's frame.
func _cell_rect(x: int, z: int, width: int, depth: int) -> Rect2:
	return Rect2(Layout.BOUNDS.position + Vector2(float(x), float(z)) * Layout.CELL,
		Vector2(float(width), float(depth)) * Layout.CELL)


## Shut every way out of the room: rock across the opening, jamb to jamb, from
## under the floor to over the roof. The rock the eye sees across that opening is
## the room's own wall, carried straight on through where the passage used to be
## (`Rock.skin(index, true)`) - so the chamber reads as a hall whose ways on
## collapsed, not as a room with a box bricked into each door. Nothing is drawn
## here at all: what a hole in a wall needs is what stops a body, which is a
## collider, and the rubble that came down with it lying inside at its foot.
func _seal_the_ways() -> void:
	var doors := Layout.doors()
	var tall := Layout.TOP - Floor.LOW
	var middle := _rect.get_center()
	for door_index in Layout.doors_of(index):
		var door: Dictionary = doors[door_index]
		var mid: Vector2 = door["mid"]
		var wide := float(door["width"]) + SEAL_JAMB * 2.0
		# A way out is cut in a wall that faces along one axis: a vertical face
		# (x held) opens along z, and the other way round.
		var on_x := absf(mid.x - _rect.position.x) < 0.05 or absf(mid.x - _rect.end.x) < 0.05
		var out := Vector2(signf(mid.x - middle.x), 0.0) if on_x \
			else Vector2(0.0, signf(mid.y - middle.y))
		var size := Vector3(SEAL_THICK, tall, wide) if on_x else Vector3(wide, tall, SEAL_THICK)
		# The rock the eye sees across the opening is the room's own wall, carried on
		# through it (`Rock.skin(index, true)`), so there is nothing to draw here: what
		# the hole needs is what stops a body, and that is a collider alone.
		var at: Vector3 = Vector3(mid.x, (Layout.TOP + Floor.LOW) * 0.5, mid.y) \
			+ Vector3(out.x, 0.0, out.y) * (SEAL_THICK * 0.5 + 0.05)
		_box_collider(size, at)
		_rubble(mid, out, float(door["width"]))


## The rubble at a sealed way's foot: the chips and slabs that came down with the
## rock, scattered along the line the way used to open on, each set on the ground it
## lies on. It is debris, not a barricade - the rock behind it is the room's own
## wall, carried on across the opening (`delve_rock.gd`), so nothing here is drawn
## to hide a box face. The pieces a body can walk into carry a collider.
func _rubble(face: Vector2, out: Vector2, wide: float) -> void:
	var material := CaveKit.formation_material(area)
	var kit := VillageKit.Merged.new()
	var along := Vector2(-out.y, out.x)
	var pieces := ["BoulderA", "BoulderB", "BoulderC", "Slab", "Talus"]
	var count := 3 + _rng.randi_range(0, 3)
	for piece_index in count:
		var flat: Vector2 = face + along * _rng.randf_range(-wide * 0.5, wide * 0.5) \
			- out * _rng.randf_range(0.35, 1.9)
		var size := _rng.randf_range(0.45, 1.05)
		var spin := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) \
			* Basis(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2))
		var ground := Vector3(flat.x, Floor.height(flat.x, flat.y), flat.y)
		kit.add(CaveKit.formation(pieces[_rng.randi() % pieces.size()]),
			Transform3D(spin.scaled_local(Vector3.ONE * size), ground), material)
		if size >= 0.85:
			VillageKit.add_post_collider(_solids, Transform3D.IDENTITY, 0.5 * size, 0.8 * size, ground)
	_cave_ins += 1
	kit.commit(_node, "CaveIn%d" % _cave_ins, false)


## The rope down the shaft of a chamber the plan opens - the room the party was
## lowered into, and the night falling down it on the fight.
func _build_rope() -> void:
	for landing in Layout.LANDINGS:
		if str(landing["room"]) != room_id:
			continue
		var rope: Vector3 = landing["rope"]
		_lights.append_array(Dressing.rope(_node, landing,
			Rock.roof_height(index, rope.x, rope.z)))


func _build_lights() -> void:
	for order in Layout.LIGHTS.size():
		var spec: Dictionary = Layout.LIGHTS[order]
		if str(spec["room"]) != room_id:
			continue
		_lights.append_array(Dressing.light(_node, spec, SEED + 11 + order * 13))


## What the plan stands in this room, into one merged prop mesh and a `Solids`
## body for whatever stops a body - the delve's own split, for one room.
func _build_props() -> void:
	var clutter := VillageKit.Merged.new()
	var solids: StaticBody3D = null
	for order in Layout.PROPS.size():
		var spec: Dictionary = Layout.PROPS[order]
		if str(spec["room"]) != room_id:
			continue
		if solids == null:
			solids = StaticBody3D.new()
			solids.name = "Solids"
			solids.collision_layer = 1
			solids.collision_mask = 0
			_node.add_child(solids)
		_lights.append_array(Dressing.prop(_node, clutter, solids, spec, SEED + 501 + order * 17))
	clutter.commit(_node, "Props", false)


## Underground: no sky, a dim ambient that keeps the rock readable between the
## lamps, and a close haze, all of it the area's own air (`CaveKit.AREAS`). The
## haze is authored at the plan's drawn size and the floor is built `SCALE` times
## it, so the density comes off the same number the delve uses.
func _build_air() -> void:
	var look: Dictionary = CaveKit.AREAS.get(area, CaveKit.AREAS["mouth"])
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.010, 0.009)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = look["ambient"]
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_light_color = look["fog"]
	environment.fog_light_energy = 0.8
	environment.fog_sky_affect = 0.0
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	# Godot 4.7 resets the density when the mode is written: the density goes last.
	environment.fog_density = float(look["haze"]) / Layout.SCALE
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.35
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.95
	environment.adjustment_contrast = 1.06
	environment.adjustment_brightness = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.1


## The squad's map of the chamber: the room's own colliders, on the room's own
## ground, so the band's allies walk round the dripstone and the falls instead of
## into them - the map the delve hands the squad below, for one room.
func _build_nav() -> void:
	nav = NavScript.new()
	var from := _flat_to_world(_rect.position.x, _rect.position.y)
	var ground := func(x: float, z: float) -> float:
		var local := to_local(Vector3(x, 0.0, z)) + _offset
		return to_global(Vector3(local.x, Floor.height(local.x, local.z), local.z)).y
	nav.build(self, Rect2(from.x, from.z, _rect.size.x, _rect.size.y), [], ground)


# --- the two lines -----------------------------------------------------------

## The middle of a line standing `side` of the room's own middle (-1 the party's,
## 1 the foes'), along the long axis, in the plan's frame.
func _line_centre(side: float) -> Vector2:
	var middle := _rect.get_center()
	var reach := clampf(maxf(_rect.size.x, _rect.size.y) * 0.3, LINE_NEAR, LINE_REACH)
	if _rect.size.x >= _rect.size.y:
		return Vector2(middle.x + reach * side, middle.y)
	return Vector2(middle.x, middle.y + reach * side)


## `count` posts on one line, spread across the room's short axis and settled off
## anything already standing there. `taken` carries the posts of both lines.
func _line_posts(centre: Vector2, count: int, taken: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var across_x := _rect.size.x < _rect.size.y
	var room := _inner.size.x if across_x else _inner.size.y
	var n := maxi(count, 1)
	var spread := clampf(room / float(maxi(1, n - 1)), TIGHT, SPREAD)
	for post_index in n:
		var offset := (float(post_index) - float(n - 1) * 0.5) * spread
		var at := centre + (Vector2(offset, 0.0) if across_x else Vector2(0.0, offset))
		var settled := _settle(at, taken)
		taken.append(settled)
		out.append(settled)
	return out


## A post as close to `at` as the room allows, clear of everything standing in it.
func _settle(at: Vector2, taken: Array) -> Vector2:
	if _clear(at, taken):
		return at
	var best := at
	var best_gap := INF
	var x := _inner.position.x
	while x <= _inner.end.x:
		var z := _inner.position.y
		while z <= _inner.end.y:
			var spot := Vector2(x, z)
			if _clear(spot, taken):
				var gap := spot.distance_to(at)
				if gap < best_gap:
					best_gap = gap
					best = spot
					if best_gap <= 2.0:
						return best
			z += 1.0
		x += 1.0
	return best


## Whether a body may stand at a plan point and start a fight there: on the room's
## floor, off the ways out and everything the plan stands in it, off the dripstone
## that stops a body, and off the posts already placed.
func _clear(at: Vector2, taken: Array) -> bool:
	if not _inner.has_point(at):
		return false
	for entry in _keep_out:
		if at.distance_to(entry[0]) < float(entry[1]):
			return false
	for stop in _stops:
		var piece: Vector3 = stop[0]
		if at.distance_to(Vector2(piece.x, piece.z)) < float(stop[1]) + STOP_CLEARANCE:
			return false
	for other in taken:
		if at.distance_to(other) < POST_GAP:
			return false
	return true


## Plan-frame posts as world posts, each on the ground under it.
func _world_posts(points: Array[Vector2]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for at in points:
		out.append(_flat_to_world(at.x, at.y) + Vector3(0.0, SPAWN_LIFT, 0.0))
	return out


## A plan point on the room's floor, in the world.
func _flat_to_world(x: float, z: float) -> Vector3:
	return to_global(Vector3(x, Floor.height(x, z), z) - _offset)


func _box_collider(size: Vector3, at: Vector3) -> void:
	VillageKit.add_collider(_solids, Transform3D.IDENTITY, size, at)
