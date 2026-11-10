class_name CaveRoom
extends Node3D
## One chamber of the Weeping Hollow: the room the Hollow Beneath is fought in.
##
## The Hollow authors the cave. `cave_plan.gd` names every room it is dug from -
## the watchers' den, the drowned gallery, the ossuary, the pale garden, the black
## mere, the bone chapel, the rooted hall, the old workings, the demons' ring and
## Gorehorn's lair - and the rooms are drawn by the floor surface
## (`cave_floor.gd`), the rock skin (`cave_rock.gd`) and the dressing
## (`cave_dressing.gd`). This node builds **one** of them, exactly as the floor
## plan lays it, and nothing else: the room's own ground, the rock nearest it on
## every side, the vaulted roof over it, the dripstone and breakdown grown in it,
## the lights the plan hangs and the props it stands. It is the same cave the
## Hollow's floor would have been; the island just uses it for a fight.
##
## The run walks one room, not eleven areas, so the ways out of the chamber are
## shut: the rock of the walls is drawn straight on across every opening the plan
## cut (`Rock.skin(index, true)`), a collision of the room's own keeps a body from
## walking out through one, and the rubble that came down with it lies at its foot.
## The chamber reads as what it is - a hall whose ways on collapsed - and the fight
## has nowhere to go but into itself.
##
## The room stands at its parent's origin, with its own floor's middle on it: the
## plan's coordinates are offsets inside `_node`, so the floor, the skin, the props
## and a body's post are authored at the plan's coordinates and never moved by
## hand. The stage asks this node for every point it needs (`party_posts`,
## `random_local`, `reward_local`, `gate_local`), so the run never has to know the
## plan.

const Layout = preload("res://scripts/world/cave_plan.gd")
const Floor = preload("res://scripts/world/cave_floor.gd")
const Rock = preload("res://scripts/world/cave_rock.gd")
const Dressing = preload("res://scripts/world/cave_dressing.gd")
const CaveKit = preload("res://scripts/world/cave_kit.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")

## The lift every body in the world is spawned clear of its ground by.
const SPAWN_LIFT := 0.12
## How far apart the bodies of one line stand, at most; and the closest the line
## may be squeezed in a narrow room.
const SPREAD := 4.4
const TIGHT := 1.9
## How far in from the rock a body's post stands, and how close two posts may be.
const WALL_MARGIN := 2.2
const POST_GAP := 1.9
## The floor a body wants past the end of its own line to circle round it.
const CIRCLE := 2.4
## The smallest a room may be across either way to hold a fight: the party's own
## line (three bodies at `SPREAD`), the wall margin at both ends of it, and a
## stride of floor past each end to circle round. Narrower than this and the
## room is a passage the plan cut as an apse or a niche - the apses are six
## metres across - and a party landing in one has its line against the rock with
## the gates on top of its own posts.
const MIN_SIDE := SPREAD * 2.0 + WALL_MARGIN * 2.0 + CIRCLE * 2.0
## How far a post keeps off anything already standing in the room - the dripstone
## that stops a body, a light, a prop, a way out.
const STOP_CLEARANCE := 0.9
## The gap a reward prop keeps from another prop and from the room's own stone,
## and the gap a gate keeps, in metres.
const PROP_GAP := 2.8
const GATE_GAP := 3.8
## How far behind the party's own line a gate stands and how far off it the two
## flanking gates stand, before the room's own width narrows them.
const GATE_BACK := 3.0
const GATE_FLANK := 4.0
## How thick the collision that shuts a way out stands, and how far it runs past
## the opening's jambs.
const SEAL_THICK := 1.0
const SEAL_JAMB := 1.2
## How far from the room's middle a line stands, along its long axis. The fight
## opens at a distance the room does not decide: a hall the size of the lair would
## put the two lines forty metres apart - ten seconds of walking before anybody is
## in reach - and a chamber the size of the apse would put them in each other's
## faces. So a line stands a share of the room's length out, floored and capped
## here.
const LINE_NEAR := 6.0
const LINE_REACH := 15.0
## Every room's rock, formations, lights and props are grown from the plan and the
## room's own index (`cave_dressing.gd`); the chamber's lights and props are drawn
## from this seed, the way the plan draws them.
const SEED := 6607

## The room this chamber was built from (`Layout.ROOMS` id), or "".
var room_id := ""
## The area of the floor it belongs to (`Layout.AREAS` key).
var area := ""
## The room's index in `Layout.ROOMS`, or -1.
var index := -1
## The camera's air while the eye is in here, over the world's own sky.
var environment: Environment = null

## The room in the cave's frame: where the plan cut it.
var _rect := Rect2()
var _inner := Rect2()
## The room's middle on the floor: how far the plan's frame is from this node's.
var _offset := Vector3.ZERO
## Everything the room draws, in the plan's frame.
var _node: Node3D = null
## The rock the room is cut into: its colliders.
var _solids: StaticBody3D = null
## What no post may stand on: `[point, radius]` (cave x/z) for the ways out and
## everything the plan stands in the room.
var _keep_out: Array = []
## What already stops a body in the room: `[at, radius, tall]` for every formation
## grown tall enough to stop one.
var _stops: Array = []
## The party's line in the plan's frame, and the two axes of the room's own
## crossing: `_inward` runs from that line to the middle, `_across` picks the
## other side of it.
var _party_line := Vector2.ZERO
var _inward := Vector2(0.0, 1.0)
var _across := Vector2(1.0, 0.0)
var _rng := RandomNumberGenerator.new()
var _cave_ins := 0


# --- the plan -------------------------------------------------------------------

## Every room of the Hollow a bout can be fought in: the halls and chambers the
## plan cuts (`Layout.ROOMS`), not the ways between them - a tunnel is a passage,
## not a room to fight in - and never a room too narrow for the party's own line
## (`MIN_SIDE`): the apses, the niches and the glades the plan cuts as add-ons are
## rooms to walk through, not rooms to stand three bodies a side in a fight.
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


## A chamber for this island: one of `room_ids()`, drawn from `rng`.
static func pick_room(rng: RandomNumberGenerator) -> String:
	var ids := room_ids()
	if ids.is_empty():
		return ""
	return ids[rng.randi() % ids.size()]


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


## The world post of each body of a party of `count` on the party's own line, each
## on the ground under it. The stage drops the party here when the island opens.
func party_posts(count: int) -> Array[Vector3]:
	return _world_posts(_line_posts(_party_line, count, []))


## The yaw the party faces when it lands: toward the room's middle.
func entry_yaw() -> float:
	return _yaw_towards(_inward)


## The yaw of the gate at `slot`: toward the room's middle.
func gate_yaw(slot: int) -> float:
	return _yaw_towards(_rect.get_center() - _gate_plan(slot))


## A body's post somewhere in the chamber, `margin` metres in from its own walls,
## clear of everything the plan stands and grows: a wave's arrival.
func random_local(rng: RandomNumberGenerator, margin: float = 4.0) -> Vector2:
	var inset := minf(margin, minf(_inner.size.x, _inner.size.y) * 0.25)
	var box := _inner.grow(-inset)
	for _attempt in 40:
		var at := Vector2(rng.randf_range(box.position.x, box.end.x),
			rng.randf_range(box.position.y, box.end.y))
		if _clear(at, []):
			return _local(at)
	return _local(_party_line)


## Where a reward prop stands: `slot` of `of` round an anchor on the party's half
## of the room, `reach` metres out. `taken` carries the points already handed out
## this level, so nothing lands on anything else; a point too close to the room's
## own stone is settled to the nearest clear spot.
func reward_local(slot: int, of: int, reach: float, taken: Array) -> Vector2:
	var anchor := _party_line.lerp(_rect.get_center(), 0.45)
	var angle := PI * 0.5 + TAU * float(slot) / float(maxi(1, of))
	var at := anchor + (_across * cos(angle) + _inward * sin(angle)) * reach
	at = _settle_prop(at, taken, PROP_GAP)
	taken.append(at)
	return _local(at)


## Where the gate at `slot` stands: one behind the party's line and two flanking
## it, all inside the room's own walls. `taken` carries the level's props and the
## gates already placed, so a gate never stands in a chest.
func gate_local(slot: int, taken: Array) -> Vector2:
	var at := _settle_prop(_gate_plan(slot), taken, GATE_GAP)
	taken.append(at)
	return _local(at)


## A point on the room's party half for a fixture that asks for the island's rim:
## spread across the entry end, `inset` metres in from the rock.
func rim_local(index: int, count: int, inset: float) -> Vector2:
	var along := (float(index) + 0.5) / float(maxi(1, count))
	var across_reach := minf(_inner.size.x, _inner.size.y)
	var at := _party_line - _inward * minf(inset, 3.0) \
		+ _across * (along - 0.5) * across_reach * 0.6
	return _local(_settle_prop(at, [], PROP_GAP))


## The floor's own height at a point of the room, in the room's frame: what a
## prop, a post or a body's feet stand on.
func height_at(x: float, z: float) -> float:
	var plan := _plan(Vector2(x, z))
	return Floor.height(plan.x, plan.y) - _offset.y


## The chamber's reach, for anything that wants one number: the shortest way from
## the middle of its inner rectangle to a wall.
func play_radius() -> float:
	return minf(_inner.size.x, _inner.size.y) * 0.5


# --- the build ---------------------------------------------------------------

## Cut the chamber `id` out of the plan. The node is already in the tree at the
## stage's origin: the rock, the floor and a body's post are all read in the cave's
## own frame and offset once, here.
func build(id: String, seed_value: int = SEED) -> void:
	room_id = id
	index = Layout.room_index(id)
	if index < 0:
		push_error("cave room: the Hollow has no room '%s'" % id)
		return
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	var room: Dictionary = Layout.ROOMS[index]
	area = str(room["area"])
	_rect = room["rect"]
	_inner = _rect.grow(-WALL_MARGIN)
	var middle := _rect.get_center()
	_offset = Vector3(middle.x, Floor.height(middle.x, middle.y), middle.y)
	_node = Node3D.new()
	_node.name = "Room"
	_node.position = -_offset
	add_child(_node)
	_party_line = _line_centre(-1.0)
	_inward = (middle - _party_line).normalized()
	_across = Vector2(-_inward.y, _inward.x)
	_keep_out = Layout.crowd_keep_out(index)
	_stops = Dressing.grown_stops(index)
	_build_shell()
	# The rock skin over the walls and roof, the dripstone and breakdown grown
	# around it, and the colliders that stand in the way of a body: the plan's own
	# room dressing, on one room, with every way out closed over.
	Dressing.dress_room(_node, index, true)
	_build_rope()
	_build_lights()
	_build_props()
	_build_air()


## The room's own floor, the roof over it and the rock nearest it, plus every way
## out shut. One merged mesh for the lot, one collider body under it - the same
## split the plan makes between what is drawn and what stops a body.
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
	# `WALL_CELLS` of the room, whether the plan's full floor would have given it
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
## own floor, merged greedily into the fewest boxes - the same merge the plan's
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
## wall, carried on across the opening (`cave_rock.gd`), so nothing here is drawn
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
		Dressing.rope(_node, landing, Rock.roof_height(index, rope.x, rope.z))


func _build_lights() -> void:
	for order in Layout.LIGHTS.size():
		var spec: Dictionary = Layout.LIGHTS[order]
		if str(spec["room"]) != room_id:
			continue
		Dressing.light(_node, spec, SEED + 11 + order * 13)


## What the plan stands in this room, into one merged prop mesh and a `Solids`
## body for whatever stops a body - the plan's own split, for one room.
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
		Dressing.prop(_node, clutter, solids, spec, SEED + 501 + order * 17)
	clutter.commit(_node, "Props", false)


## Underground: no sky, a dim ambient that keeps the rock readable between the
## lamps, and a close haze, all of it the area's own air (`CaveKit.AREAS`). The
## haze is authored at the plan's drawn size and the floor is built `SCALE` times
## it, so the density comes off the same number the plan uses.
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
	return _clear_gap(at, taken, POST_GAP)


## The same, for anything that keeps a wider gap: a chest, a stall, a gate.
func _clear_gap(at: Vector2, taken: Array, gap: float) -> bool:
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
		if at.distance_to(other) < gap:
			return false
	return true


## A prop's point as close to `at` as the room allows, `gap` metres clear of
## everything else standing in it.
func _settle_prop(at: Vector2, taken: Array, gap: float) -> Vector2:
	if _clear_gap(at, taken, gap):
		return at
	var best := at
	var best_gap := INF
	var x := _inner.position.x
	while x <= _inner.end.x:
		var z := _inner.position.y
		while z <= _inner.end.y:
			var spot := Vector2(x, z)
			if _clear_gap(spot, taken, gap):
				var reach := spot.distance_to(at)
				if reach < best_gap:
					best_gap = reach
					best = spot
					if best_gap <= 1.0:
						return best
			z += 1.0
		x += 1.0
	return best


## The plan point a gate at `slot` would stand on before the room settles it: one
## behind the party's line and two flanking it, as far out as the room allows.
func _gate_plan(slot: int) -> Vector2:
	var flank := clampf(minf(_inner.size.x, _inner.size.y) * 0.5 - 0.9, 1.8, GATE_FLANK)
	return _party_line - _inward * GATE_BACK + _across * (float(slot) - 1.0) * flank


## The yaw that points a body's own forward (-Z) along `towards`.
func _yaw_towards(towards: Vector2) -> float:
	return atan2(-towards.x, -towards.y)


## A plan point in the room's frame, whose middle is the origin.
func _local(plan: Vector2) -> Vector2:
	return plan - _rect.get_center()


## A room-frame point back in the plan's frame.
func _plan(local: Vector2) -> Vector2:
	return local + _rect.get_center()


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
