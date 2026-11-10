class_name RogueliteStage
extends Node3D
## One bounded island: the ground a run is fought on.
##
## The three biomes are the campaign's own art, recycled: the wood's trees out of
## `TreeKit` and `WorldStyle`, the cave floor's dripstone and glow out of
## `CaveKit`, the ring's dressed stone out of `RockKit` and primitives. Nothing
## here is a new asset pipeline, and nothing here touches the terrain heightfield:
## the island stands off the field at its own height (`LIFT`), exactly the way the
## arena ring and the delve already stand away from it.
##
## What makes it an island rather than a scene is its bound. The fight ring is
## `radius`; past it the ground runs on for `OUTER_DEPTH` as a darker band with a
## treeline planted in it, and the fog is three veils deep, so the edge reads as
## the edge of the world before a body ever reaches it. Walking out is allowed -
## the run warns, then puts the body back in the middle of the map at a price
## (`RunDirector._tick_bounds`) - and the solid wall stands at the far side of the
## band, inside the fog, only so that nothing walks off into the sky. It has no
## gate: the run's own portals are the way on.

const Geo = preload("res://scripts/geo.gd")
const RockKit = preload("res://scripts/world/rock_kit.gd")
const CaveKit = preload("res://scripts/world/cave_kit.gd")
const TreeKit = preload("res://scripts/world/tree_kit.gd")
const CampKit = preload("res://scripts/world/camp_kit.gd")
const FireFx = preload("res://scripts/world/fire_fx.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const WorldScatter = preload("res://scripts/world/scatter.gd")
const CampDressing = preload("res://scripts/warband/camp_dressing.gd")
const WorldStyleScript = preload("res://scripts/world/world_style.gd")

## Out of sight above the campaign and clear of the arena's chamber (260) and the
## delve (1100 in z). Each stage takes its own height so the corpse and prop of
## the last island can never be found on the next.
const LIFT := 620.0
const STAGE_SPACING := 210.0
## How far the island's ground runs past its own turf. The fight ring is `radius`;
## the band outside it is walkable, and a body that stands in it is out of bounds:
## the run warns it, and pulls it back into the middle of the map at a price
## (`RunDirector`). The hard wall is out at `radius + OUTER_DEPTH`, inside the fog,
## where nothing stands by accident.
const OUTER_DEPTH := 12.0
## How fine the island's turf is cut: nine rings of ninety-six spokes is 1,632
## triangles, and every ring is a little over three metres wide, so the wear the
## shader reads reads as patches instead of as a smear.
const FLOOR_RINGS := 9
const FLOOR_SPOKES := 96

const BIOMES := [
	{
		"id": "wilderness", "name": "THE BRIARWOOD", "subtitle": "WILDERNESS  ·  WATCHERS",
		"radius": 34.0, "wall_height": 7.0,
		"earth": Color(0.19, 0.21, 0.13), "sky": Color(0.11, 0.15, 0.17),
		"fog": Color(0.16, 0.22, 0.18, 0.30), "light": Color(0.72, 0.86, 0.72),
		"faction": "watchers",
		"grass": 0.34, "ferns": 0.05,
	},
	{
		"id": "caves", "name": "THE HOLLOW BENEATH", "subtitle": "CAVES  ·  DEMONS",
		"radius": 30.0, "wall_height": 8.0,
		"earth": Color(0.17, 0.14, 0.12), "sky": Color(0.05, 0.05, 0.06),
		"fog": Color(0.22, 0.13, 0.09, 0.34), "light": Color(1.0, 0.55, 0.30),
		"faction": "demons",
		"grass": 0.05, "ferns": 0.02,
	},
	{
		"id": "arena", "name": "THE BLOOD PIT", "subtitle": "ARENA  ·  BLOOD CLONES",
		"radius": 31.0, "wall_height": 7.5,
		"earth": Color(0.27, 0.22, 0.17), "sky": Color(0.14, 0.09, 0.08),
		"fog": Color(0.30, 0.12, 0.09, 0.28), "light": Color(1.0, 0.62, 0.42),
		"faction": "clones",
		"grass": 0.06, "ferns": 0.0,
	},
]

var biome_id := "wilderness"
var radius := 34.0
var seed_value := 0
var stage_index := 0
var _rng := RandomNumberGenerator.new()
var _props: Node3D
var _dressing: Node3D
## The turf's own phases: three offsets that make the wear field of this island
## and no other, rolled once in `build` and shared by every vertex of the mesh.
var _floor_phase := Vector3.ZERO
## The ground grade of each biome, cached per stage: `TextureLibrary` keys a
## terrain material on its style's id, so the three islands share three materials.
var _floor_styles: Dictionary = {}


static func biome(biome_key: String) -> Dictionary:
	for row in BIOMES:
		if str(row.id) == biome_key:
			return row
	return BIOMES[0]


static func centre_for(index: int) -> Vector3:
	return Vector3(0.0, LIFT + float(absi(index)) * STAGE_SPACING, 0.0)


## Build (or rebuild) the island. The node is expected to have been positioned
## at `centre_for(stage_index)` by the caller before `build`.
func build(biome_key: String, run_seed: int, index: int) -> void:
	biome_id = biome_key
	stage_index = maxi(0, index)
	seed_value = run_seed
	var data := biome(biome_key)
	radius = float(data.radius)
	_rng.seed = int(run_seed) + stage_index * 7919 + str(biome_key).hash()
	_floor_phase = Vector3(_rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU),
		_rng.randf_range(0.0, TAU))
	_position_on_lift()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_dressing = Node3D.new()
	_dressing.name = "Dressing"
	add_child(_dressing)
	_build_floor(data)
	_build_boundary(data)
	_build_light(data)
	match biome_key:
		"caves":
			_build_cave(data)
		"arena":
			_build_pit(data)
		_:
			_build_wood(data)
	_build_litter(data)
	_scatter_ground_cover(data)


## A body is placed on an island by this, never by the heightfield: the island's
## own floor is the only ground under it.
func _position_on_lift() -> void:
	var wanted := centre_for(stage_index)
	if global_position.distance_squared_to(wanted) > 0.001:
		global_position = wanted


func floor_point(local: Vector2) -> Vector3:
	return global_position + Vector3(local.x, 0.05, local.y)


## The ring a run's bodies are meant to fight in. Past it the ground still runs
## (`OUTER_DEPTH` of band and a treeline), which is exactly the state the run's
## out-of-bounds guard watches for.
func play_radius() -> float:
	return radius


## The middle of the island: where a body that strayed is put back.
func middle() -> Vector3:
	return floor_point(Vector2.ZERO)


func random_point(rng: RandomNumberGenerator, margin: float = 4.0) -> Vector3:
	var reach := maxf(1.0, radius - margin)
	for _attempt in 24:
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * reach
		return floor_point(Vector2(cos(angle) * distance, sin(angle) * distance))
	return floor_point(Vector2.ZERO)


## Where a wave comes in: the rim, spread around the circle. The angle is jittered
## so two waves of the same count never stand in the same ring.
func spawn_points(count: int, rng: RandomNumberGenerator = null) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var die := rng if rng != null else _rng
	for index in count:
		var angle := TAU * (float(index) / float(maxi(1, count))) + die.randf_range(-0.18, 0.18)
		var distance := radius * die.randf_range(0.62, 0.84)
		out.append(floor_point(Vector2(cos(angle) * distance, sin(angle) * distance)))
	return out


## Where the party stands when the portal drops them on a fresh island.
func entry_posts(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for index in count:
		var spread := (float(index) - float(maxi(1, count) - 1) * 0.5) * 2.0
		out.append(floor_point(Vector2(spread, radius * 0.62)))
	return out


## The ring a cleared level's rewards stand on. Its anchor sits on the island's
## party side, a walk in from the entry line, and its slots are evenly spaced so
## a level's chest, the pedestal it is a step from and the portal the pair unseals
## are one cluster a party can clear in a few paces - instead of three props
## spread across the whole rim. `reach` widens the ring for a fixture that needs
## room of its own (the shop's stall); the slot order is the caller's.
func reward_point(slot: int, of: int = 3, reach: float = 2.5) -> Vector3:
	var anchor := floor_point(Vector2(0.0, radius * 0.34))
	var angle := PI * 0.5 + TAU * float(slot) / float(maxi(1, of))
	return anchor + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)


## The island's rim, for portals, chests and the shop: evenly spaced around the
## back half so nothing lands on the party's own entry line.
func rim_point(index: int, count: int, inset: float = 3.2) -> Vector3:
	var angle := PI * (0.15 + 0.7 * (float(index) + 0.5) / float(maxi(1, count)))
	var distance := maxf(1.0, radius - inset)
	return floor_point(Vector2(cos(angle) * distance, sin(angle) * distance))


# --- ground ----------------------------------------------------------------

func _build_floor(data: Dictionary) -> void:
	# The island's floor is the wood's own ground, not a painted disc: the same
	# four-layer terrain material the campaign's field and its road use, on a mesh
	# that carries the wear in its vertex alpha. See `_floor_mesh` and
	# `_floor_style` for what each biome asks that material for.
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "IslandFloor"
	floor_mesh.mesh = _floor_mesh(data)
	floor_mesh.material_override = TextureLibrary.terrain_material(_floor_style(data))
	add_child(floor_mesh)
	var earth := Geo.material(data.earth, 0.0, 0.94)
	var solid := StaticBody3D.new()
	solid.name = "IslandGround"
	add_child(solid)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# The ground runs out past the turf on every side. The band outside the fight
	# is walkable ground the run warns about, not a fall into the sky, and the hard
	# wall stands at the far edge of it.
	box.size = Vector3((radius + OUTER_DEPTH) * 2.0, 0.7, (radius + OUTER_DEPTH) * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.35, 0.0)
	solid.add_child(shape)
	# The band itself: the same earth, darker, starting exactly where the turf stops
	# and sharing its polygon, so the two planes meet without a seam or a fight for
	# the depth buffer. It is the ground a body is standing on when the run tells it
	# to go back, so it has to *be* ground and not a lip.
	var band := MeshInstance3D.new()
	band.name = "OuterBand"
	band.mesh = _band_mesh(radius + OUTER_DEPTH)
	# The ground is read from above and from the low camera behind a body, so the
	# annulus is double-sided like the turf's own shader rather than wound for one.
	var band_material := Geo.material(data.earth.darkened(0.34), 0.0, 0.97)
	band_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	band.material_override = band_material
	add_child(band)
	# The lip: one unlit stone drum under the turf, out of sight except at the
	# edge, so the island reads as a broken-off piece of the world rather than a
	# disc in the sky.
	var drum := Geo.cylinder(self, radius, radius * 0.97, 1.5,
		Vector3(0.0, -0.81, 0.0), earth, 48)
	drum.name = "IslandBase"
	# A rim of rock under the lip so the island reads as a broken-off piece of
	# the world rather than a disc in the sky.
	var rock := RockKit.mesh("outcrop", seed_value + 31)
	if rock != null:
		var underneath := Node3D.new()
		underneath.name = "Underside"
		add_child(underneath)
		var stone := Geo.material(data.earth.darkened(0.35), 0.0, 0.98)
		for index in 9:
			var angle := TAU * float(index) / 9.0
			var mesh := MeshInstance3D.new()
			mesh.mesh = rock
			mesh.material_override = stone
			mesh.position = Vector3(cos(angle) * radius * 0.86, -1.4,
				sin(angle) * radius * 0.86)
			mesh.scale = Vector3(4.0, 3.4, 4.0)
			mesh.rotation.y = _rng.randf_range(0.0, TAU)
			underneath.add_child(mesh)


## The island's turf: a flat fan of rings, one vertex colour per vertex. The
## colour's rgb is a broad value tint the terrain shader multiplies in; its alpha
## is the *wear* - how trodden the ground is at that point - and `terrain.gdshader`
## reads it as bare earth against the grass and the leaf litter. A mesh without a
## colour array hands the shader a white vertex, which would paint the whole island
## as dirt, so the wear lives here rather than in the material.
func _floor_mesh(data: Dictionary) -> ArrayMesh:
	var rings := FLOOR_RINGS
	var spokes := FLOOR_SPOKES
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var count := 1 + rings * spokes
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	vertices[0] = Vector3.ZERO
	normals[0] = Vector3.UP
	colors[0] = _floor_colour(data, 0.0, 0.0)
	var index := 1
	for ring in range(1, rings + 1):
		var reach := radius * float(ring) / float(rings)
		for spoke in spokes:
			var angle := TAU * float(spoke) / float(spokes)
			var x := cos(angle) * reach
			var z := sin(angle) * reach
			vertices[index] = Vector3(x, 0.0, z)
			normals[index] = Vector3.UP
			colors[index] = _floor_colour(data, x, z)
			index += 1
	# The centre fan, then a quad per cell. The winding is `terrain.gd`'s own:
	# the outer corner is the second vertex and the turned one the third, which is
	# the order the world's own field is wound in.
	for spoke in spokes:
		indices.append(0)
		indices.append(1 + spoke)
		indices.append(1 + (spoke + 1) % spokes)
	for ring in range(1, rings):
		var inner := 1 + (ring - 1) * spokes
		var outer := 1 + ring * spokes
		for spoke in spokes:
			var next := (spoke + 1) % spokes
			var a := inner + spoke
			var b := outer + spoke
			var c := inner + next
			var d := outer + next
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(b)
			indices.append(d)
			indices.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _floor_colour(data: Dictionary, x: float, z: float) -> Color:
	# A broad value tint, so the field is never one flat green from any angle.
	var value := 0.95 + 0.09 * _floor_noise(x * 2.7 + 13.0, z * 2.7 - 9.0, 0.9)
	return Color(value, value, value * 0.98, _floor_wear(data, x, z))


## The out-of-bounds band: a flat annulus from the turf's own edge to `outer`,
## cut on the same spokes as the turf so the two meet on one seam.
func _band_mesh(outer: float) -> ArrayMesh:
	var spokes := FLOOR_SPOKES
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in 2:
		var reach := radius if ring == 0 else outer
		for spoke in spokes:
			var angle := TAU * float(spoke) / float(spokes)
			vertices.append(Vector3(cos(angle) * reach, 0.0, sin(angle) * reach))
			normals.append(Vector3.UP)
	for spoke in spokes:
		var next := (spoke + 1) % spokes
		var a := spoke
		var b := spokes + spoke
		var c := next
		var d := spokes + next
		indices.append(a)
		indices.append(b)
		indices.append(c)
		indices.append(b)
		indices.append(d)
		indices.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## How worn the ground is where feet have been. The wood keeps its litter and is
## trodden bare around the middle, where every wave lands; the cave's silt is
## churned and the pit is packed sand over stone. Everything between is the
## shader's own noise, so the wear reads as patches and not as a gradient.
func _floor_wear(data: Dictionary, x: float, z: float) -> float:
	var coarse := _floor_noise(x, z, 0.045)
	var fine := _floor_noise(x * 1.7 + 31.0, z * 1.7 - 17.0, 0.11)
	match str(data.get("id", "wilderness")):
		"caves":
			# Churned silt: the hollow's floor is earth and broken stone with the
			# moss that survives underground only where nothing walks, so the
			# ground here is mostly worn and the green is the exception.
			return clampf(0.58 + 0.30 * coarse + 0.08 * fine, 0.0, 1.0)
		"arena":
			return clampf(0.54 + 0.32 * coarse + 0.12 * fine, 0.0, 1.0)
	# The wood keeps its litter: the leaves and the grass are the floor, and the
	# earth only shows where feet have worn it - a broad patch here, a trodden
	# ring where the waves land, never a field of mud.
	var middle := 1.0 - smoothstep(4.0, 13.0, Vector2(x, z).length())
	return clampf(0.03 + 0.15 * coarse + 0.10 * fine + 0.20 * middle, 0.0, 1.0)


## A smooth deterministic 0..1 field, seeded once per island. Three offset sines
## are cheaper than a noise texture read per vertex and cannot tile visibly.
func _floor_noise(x: float, z: float, scale: float) -> float:
	var a := sin(x * scale + _floor_phase.x) * 0.5 + 0.5
	var b := sin(z * scale * 1.31 + _floor_phase.y) * 0.5 + 0.5
	var c := sin((x + z) * scale * 0.77 + _floor_phase.z) * 0.5 + 0.5
	return a * 0.45 + b * 0.35 + c * 0.20


## The ground grade for one island. The wood's own night style is the forest floor
## the campaign walks on - the same `terrain_grass` / `terrain_litter` /
## `terrain_dirt` / `terrain_rock` set, the same tints - and each biome asks it for
## a different share of litter and earth. The style gets its own id because
## `TextureLibrary` caches a terrain material per style id, and the pit's sand is
## not the road's turf.
func _floor_style(data: Dictionary) -> WorldStyle:
	var key := "island_" + str(data.get("id", "wilderness"))
	var cached: WorldStyle = _floor_styles.get(key)
	if cached != null:
		return cached
	var style: WorldStyle = WorldStyleScript.night()
	style.id = key
	var ground: Dictionary = style.ground.duplicate()
	match str(data.get("id", "wilderness")):
		"caves":
			# Churned silt and wet stone: the cave's floor is mostly earth, with
			# the moss that survives underground as its grass.
			ground["grass_tint"] = Color(0.31, 0.36, 0.28)
			ground["grass_dry_tint"] = Color(0.36, 0.35, 0.27)
			ground["litter_tint"] = Color(0.42, 0.36, 0.30)
			ground["dirt_tint"] = Color(0.44, 0.38, 0.31)
			ground["rock_tint"] = Color(0.40, 0.38, 0.35)
			ground["litter_cover"] = 0.18
			ground["dry_cover"] = 0.42
			ground["tile"] = 3.2
			ground["dirt_tile"] = 3.4
			ground["detail_strength"] = 0.8
		"arena":
			# The pit is packed sand and straw over broken stone.
			ground["grass_tint"] = Color(0.66, 0.57, 0.40)
			ground["grass_dry_tint"] = Color(0.74, 0.64, 0.44)
			ground["litter_tint"] = Color(0.64, 0.54, 0.39)
			ground["dirt_tint"] = Color(0.76, 0.64, 0.45)
			ground["rock_tint"] = Color(0.58, 0.54, 0.47)
			ground["litter_cover"] = 0.20
			ground["dry_cover"] = 0.62
			ground["tile"] = 3.0
			ground["dirt_tile"] = 4.2
			ground["detail_strength"] = 0.9
		_:
			# A forest floor: the wood's litter is the point of it, so the leaves
			# cover more than the road's verge and the tile is smaller, which is
			# what makes a leaf read as a leaf underfoot.
			ground["litter_cover"] = 0.48
			ground["dry_cover"] = 0.34
			ground["tile"] = 3.6
			ground["litter_tile"] = 2.8
			ground["detail_strength"] = 0.75
	style.ground = ground
	_floor_styles[key] = style
	return style


## Grass, ferns and the rustle of them: the campaign's own ground cover, batched
## into the island's dressing. Counts come from the biome row, so the wood is
## thick with tufts and the pit has a few straws between the stones.
func _scatter_ground_cover(data: Dictionary) -> void:
	if _dressing == null:
		return
	var style: WorldStyle = _floor_style(data)
	var area := PI * radius * radius
	var cover := WorldStyle.new()
	cover.id = style.id
	cover.grass = style.grass.duplicate()
	cover.grass["count"] = roundi(area * float(data.get("grass", 0.3)))
	cover.grass["range"] = 64.0
	# A clump's height window is the campaign's field, and this island stands six
	# hundred metres up in the sky: without its own window every candidate is
	# rejected as "out of range" and the floor comes back bare.
	cover.grass["height_range"] = Vector2(global_position.y - 60.0,
		global_position.y + 60.0)
	cover.ground_cover = {}
	for key in style.ground_cover:
		var cfg: Dictionary = (style.ground_cover[key] as Dictionary).duplicate()
		cfg["count"] = roundi(area * float(data.get("ferns", 0.04))) \
			if str(key) == "ferns" else 0
		cfg["range"] = 64.0
		cfg["height_range"] = cover.grass["height_range"]
		cover.ground_cover[key] = cfg
	var centre := global_position
	var inside := func(point: Vector2) -> Vector3:
		return Vector3(point.x, centre.y, point.y)
	var outside := func(point: Vector2) -> bool:
		return Vector2(point.x - centre.x, point.y - centre.z).length() > radius - 2.0
	GrassField.build(_dressing, cover, inside, outside, seed_value + 977)


## The edge of the island, and the reason a body can see it coming.
##
## The fight ring is `radius`. Planted on the band outside it is a treeline (or,
## under ground, a broken rock line) standing up into the weather, and the fog is
## three veils deep: a haze at the turf's edge, a wall of it behind the trees, and
## a thicker one at the far wall. A body may walk between the trees and out into
## the band - the run does not put an invisible wall at the edge of the fight - and
## `RunDirector` is what answers for it: a warning, then the middle of the map and
## a share of the body's life.
func _build_boundary(data: Dictionary) -> void:
	_plant_bounds(data)
	var solid := StaticBody3D.new()
	solid.name = "IslandWall"
	add_child(solid)
	var outer := radius + OUTER_DEPTH
	var segments := 28
	var step := TAU / float(segments)
	var chord := 2.0 * (outer + 0.7) * sin(step * 0.5) + 0.6
	for index in segments:
		var angle := step * float(index)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(chord, float(data.wall_height), 0.6)
		shape.shape = box
		shape.position = Vector3(cos(angle) * (outer + 0.9),
			float(data.wall_height) * 0.5, sin(angle) * (outer + 0.9))
		shape.rotation.y = -angle
		solid.add_child(shape)
	_fog_veil(radius + 0.5, data, 0.40)
	_fog_veil(radius + 3.4, data, 0.55)
	_fog_veil(outer + 1.1, data, 0.72)


## One sheet of the island's own weather at `at_radius`. Unshaded and double-sided,
## so the ring reads as fog from either side of it, and thick enough at the far one
## that the wall behind it is a suggestion.
func _fog_veil(at_radius: float, data: Dictionary, strength: float) -> void:
	var fog_mesh := CylinderMesh.new()
	fog_mesh.top_radius = at_radius
	fog_mesh.bottom_radius = at_radius
	fog_mesh.height = float(data.wall_height)
	fog_mesh.radial_segments = 40
	fog_mesh.rings = 2
	fog_mesh.cap_top = false
	fog_mesh.cap_bottom = false
	var fog := MeshInstance3D.new()
	fog.name = "BoundaryFog"
	fog.mesh = fog_mesh
	var fog_material := StandardMaterial3D.new()
	fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tint: Color = data.fog
	tint.a = strength
	fog_material.albedo_color = tint
	fog_material.disable_receive_shadows = true
	fog.material_override = fog_material
	fog.position = Vector3(0.0, float(data.wall_height) * 0.5, 0.0)
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fog)


## The island's bound, planted. Trees in the wood and around the pit, broken rock
## below it: either way a line of solid shapes standing in the band past the turf,
## with gaps wide enough to walk out through - which is the point, because what
## happens out there is the run's business and not an invisible wall's.
func _plant_bounds(data: Dictionary) -> void:
	var solid := StaticBody3D.new()
	solid.name = "BoundsSolids"
	solid.collision_layer = 1
	solid.collision_mask = 0
	add_child(solid)
	if str(data.get("id", "wilderness")) == "caves":
		_plant_bounds_stone(solid)
	else:
		_plant_bounds_wood(solid)


## The wood's line: dead snags and briar pines, the two species that read as a
## treeline at night instead of a forest, two rows deep in the fog.
func _plant_bounds_wood(solid: StaticBody3D) -> void:
	var style: WorldStyle = WorldStyleScript.night()
	var planted := 0
	for species_id in ["hollow_snag", "briar_pine", "ironoak"]:
		var species: Dictionary = style.species_by_id(str(species_id))
		if species.is_empty():
			continue
		var variants := TreeKit.build_variants(species, seed_value + 617 + planted * 41)
		# Two builds of each species and a dozen of each: enough trees to read as a
		# treeline from inside the ring, spaced far enough apart to walk out between.
		for variant in variants.slice(0, 2):
			var trunks: Array[Dictionary] = []
			var leaves: Array[Dictionary] = []
			for _copy in 7:
				var angle := _rng.randf_range(0.0, TAU)
				var distance := radius + _rng.randf_range(1.0, OUTER_DEPTH - 2.0)
				var at := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
				var scale_at := _rng.randf_range(0.95, 1.5)
				var xform := Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
					.scaled(Vector3.ONE * scale_at), at)
				trunks.append({"transform": xform,
					"color": _pick(species.get("bark_tints", []), Color.WHITE, _rng)})
				if variant.get("leaves") != null:
					leaves.append({"transform": xform,
						"color": _pick(species.get("tints", []), Color.WHITE, _rng)})
				TreeKit.add_trunk_solids(solid, at, variant, scale_at)
			WorldScatter.batch(_dressing, "Bounds_Trunk_%s_%d" % [species_id, planted],
				variant["trunk"], TextureLibrary.bark_material(String(variant["bark"])),
				trunks, 26.0)
			if variant.get("leaves") != null and not leaves.is_empty():
				WorldScatter.batch(_dressing, "Bounds_Leaves_%s_%d" % [species_id, planted],
					variant["leaves"],
					TextureLibrary.foliage_material_tuned(String(variant["leaves_texture"]),
						variant.get("wind", Vector2(0.08, 1.0))),
					leaves, 26.0)
			planted += 1


## The hollow's line: the same stalagmites and columns the floor already uses,
## stood shoulder to shoulder out in the fog.
func _plant_bounds_stone(solid: StaticBody3D) -> void:
	var material := CaveKit.formation_material("gallery")
	for piece in ["StalagmiteTall", "Column", "StalagmiteSquat"]:
		var mesh: Mesh = CaveKit.formation(str(piece))
		if mesh == null:
			continue
		var instances: Array[Dictionary] = []
		for _index in 16:
			var angle := _rng.randf_range(0.0, TAU)
			var distance := radius + _rng.randf_range(1.0, OUTER_DEPTH - 2.0)
			var scale_at := _rng.randf_range(1.0, 1.8)
			var at := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
			instances.append({"transform": Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_at), at)})
			# A column of rock is a column of collision; the line is something a
			# body walks around, not a line it walks through.
			var shape := CylinderShape3D.new()
			shape.radius = 0.55 * scale_at
			shape.height = 3.2 * scale_at
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.position = at + Vector3(0.0, shape.height * 0.5 - 0.2, 0.0)
			solid.add_child(collision)
		WorldScatter.batch(_dressing, "Bounds_%s" % piece, mesh, material, instances, 20.0)


func _build_light(data: Dictionary) -> void:
	var sun := OmniLight3D.new()
	sun.name = "IslandLight"
	sun.light_color = data.light
	sun.light_energy = 2.2 if biome_id == "caves" else 1.5
	sun.omni_range = radius * 2.4
	sun.position = Vector3(0.0, float(data.wall_height) - 1.0, 0.0)
	sun.shadow_enabled = false
	add_child(sun)
	if biome_id == "caves":
		# A floor glow under the island so the rim is not a black hole.
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.42, 0.18)
		glow.light_energy = 0.9
		glow.omni_range = radius * 1.4
		glow.position = Vector3(0.0, 0.6, 0.0)
		add_child(glow)




# --- the three biomes ------------------------------------------------------

func _build_wood(_data: Dictionary) -> void:
	var style: WorldStyle = WorldStyleScript.night()
	var species_ids := ["ironoak", "briar_pine", "hollow_snag"]
	# The bark a body meets hangs off a real body: a collision shape parented to a
	# plain node is not in the physics world at all, which is why the wood's trees
	# could be walked straight through.
	var solid := StaticBody3D.new()
	solid.name = "WoodSolids"
	solid.collision_layer = 1
	solid.collision_mask = 0
	add_child(solid)
	var planted := 0
	for species_id in species_ids:
		var species: Dictionary = style.species_by_id(str(species_id))
		if species.is_empty():
			continue
		var variants := TreeKit.build_variants(species, seed_value + planted * 31 + 11)
		for variant in variants:
			var trunks: Array[Dictionary] = []
			var leaves: Array[Dictionary] = []
			var copies := 3 + _rng.randi_range(0, 2)
			for _copy in copies:
				var angle := _rng.randf_range(0.0, TAU)
				var distance := sqrt(_rng.randf()) * (radius - 5.0)
				var at := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
				if absf(at.x) < 4.0 and at.z > radius * 0.35:
					continue
				var scale_at := _rng.randf_range(0.85, 1.25)
				var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) .scaled(Vector3.ONE * scale_at)
				var xform := Transform3D(basis, at)
				trunks.append({"transform": xform,
					"color": _pick(species.get("bark_tints", []), Color.WHITE, _rng)})
				if variant.get("leaves") != null:
					leaves.append({"transform": xform,
						"color": _pick(species.get("tints", []), Color.WHITE, _rng)})
				# The trunk's collider stands where the trunk stands: the tree
				# itself is a multimesh cell, its bark is this one body.
				TreeKit.add_trunk_solids(solid, at, variant, scale_at)
			WorldScatter.batch(_dressing, "Trunk_%s_%d" % [species_id, planted],
				variant["trunk"], TextureLibrary.bark_material(String(variant["bark"])),
				trunks, 24.0)
			if variant.get("leaves") != null and not leaves.is_empty():
				WorldScatter.batch(_dressing, "Leaves_%s_%d" % [species_id, planted],
					variant["leaves"],
					TextureLibrary.foliage_material_tuned(String(variant["leaves_texture"]),
						variant.get("wind", Vector2(0.08, 1.0))),
					leaves, 24.0)
			planted += 1
	_scatter_rocks("boulder", 10, 0.8, 1.7)


func _build_cave(_data: Dictionary) -> void:
	_build_shell(Color(0.16, 0.13, 0.11), 11.0, true)
	var formation_material := CaveKit.formation_material("strata")
	var glow_material := CaveKit.glow_material(Color(1.0, 0.42, 0.22))
	# Floor pieces: stalagmites and columns, batched where the kit has them.
	for piece in ["StalagmiteTall", "StalagmiteSquat", "Column", "BoulderA"]:
		var mesh: Mesh = CaveKit.formation(str(piece))
		if mesh == null:
			continue
		var instances: Array[Dictionary] = []
		var copies := 5 if piece != "Column" else 3
		for _index in copies:
			var angle := _rng.randf_range(0.0, TAU)
			var distance := _rng.randf_range(radius * 0.45, radius - 4.0)
			var scale_at := _rng.randf_range(0.8, 1.6)
			instances.append({"transform": Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) .scaled(Vector3.ONE * scale_at),
				Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))})
		WorldScatter.batch(_dressing, "Cave_%s" % piece, mesh, formation_material,
			instances, 20.0)
	# Roof pieces hang from the fog's top: the island is a room with a lid.
	for piece in ["StalactiteCarrot", "StalactiteRibbed"]:
		var mesh: Mesh = CaveKit.formation(str(piece))
		if mesh == null:
			continue
		var instances: Array[Dictionary] = []
		for _index in 7:
			var angle := _rng.randf_range(0.0, TAU)
			var distance := _rng.randf_range(radius * 0.25, radius - 3.0)
			instances.append({"transform": Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)),
				Vector3(cos(angle) * distance, 9.0, sin(angle) * distance))})
		WorldScatter.batch(_dressing, "Roof_%s" % piece, mesh, formation_material,
			instances, 20.0)
	# Glow caps: the hollow's own light, four clumps of fungus and crystal.
	for _index in 6:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(radius * 0.35, radius - 5.0)
		var cap: Mesh = CaveKit.flora("CapCluster")
		if cap == null:
			cap = CaveKit.flora("CapGiant")
		if cap == null:
			continue
		var node := MeshInstance3D.new()
		node.mesh = cap
		node.material_override = glow_material
		node.position = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		node.scale = Vector3.ONE * _rng.randf_range(0.7, 1.2)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dressing.add_child(node)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.45, 0.24)
		glow.light_energy = 1.4
		glow.omni_range = 7.0
		glow.position = Vector3(cos(angle) * distance, 1.1, sin(angle) * distance)
		_dressing.add_child(glow)
	_scatter_rocks("spire", 6, 1.2, 2.2)


func _build_pit(_data: Dictionary) -> void:
	# A low stone rim before the fog. It used to be a chamber wall as tall as a
	# house, which hid the treeline standing behind it: the pit's horizon is the
	# bound of the island, and the bound is trees.
	_build_shell(Color(0.20, 0.18, 0.16), 1.9, false)
	var stone := Geo.material(Color(0.33, 0.31, 0.28), 0.0, 0.9)
	var iron := Geo.material(Color(0.22, 0.21, 0.20), 0.55, 0.5)
	# The ring of dressed stone the pit is fought in: a colonnade, then braziers
	# between the columns. This is the arena's own architecture, recycled.
	var solid := StaticBody3D.new()
	solid.name = "PitPillars"
	add_child(solid)
	var columns := 16
	for index in columns:
		var angle := TAU * float(index) / float(columns)
		var at := Vector3(cos(angle) * (radius - 3.0), 0.0, sin(angle) * (radius - 3.0))
		Geo.cylinder(_props, 0.62, 0.48, 4.6, at + Vector3(0.0, 2.3, 0.0), stone, 10)
		Geo.box(_props, Vector3(1.5, 0.42, 1.5), at + Vector3(0.0, 4.75, 0.0), stone)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 4.8, 1.2)
		shape.shape = box
		shape.position = at + Vector3(0.0, 2.4, 0.0)
		solid.add_child(shape)
		if index % 4 == 0:
			var brazier := Node3D.new()
			brazier.position = Vector3(cos(angle + 0.14) * (radius - 5.4), 0.0,
				sin(angle + 0.14) * (radius - 5.4))
			_props.add_child(brazier)
			Geo.cylinder(brazier, 0.34, 0.26, 1.5, Vector3(0.0, 0.75, 0.0), iron, 8)
			var flame := Geo.sphere(brazier, 0.34, Vector3(0.0, 1.72, 0.0), iron,
				Vector3(1.0, 1.5, 1.0))
			flame.material_override = CaveKit.glow_material(Color(1.0, 0.55, 0.2))
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.58, 0.24)
			light.light_energy = 2.0
			light.omni_range = 12.0
			light.position = Vector3(0.0, 1.9, 0.0)
			brazier.add_child(light)
	# Broken stones scattered across the floor: cover, not decoration.
	_scatter_rocks("cobble", 9, 0.7, 1.4)
	_dress_pit()


## The pit's own furniture, all of it the woodland's own art carried up here: this
## is a place things are done to people, not a coliseum. Gibbets stand between the
## columns with their cages swinging over the sand, clootie trees and charm webs
## hang the wardens' business off the rim, and the floor is littered with the
## offerings and the blood of whoever lost the last fight.
##
## Everything merges into one mesh per prop (`CampKit`), the colliders are the ones
## a body could lean on, and nothing hangs lower than a standing head: the ring is
## a fight, and a doodad must never fold a fighter into a crouch on its way past.
func _dress_pit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5501
	var mats := CampKit.materials()
	var solid := StaticBody3D.new()
	solid.name = "PitDressing"
	solid.collision_layer = 1
	solid.collision_mask = 0
	add_child(solid)
	var iron := {"iron": mats["char"], "steel": mats["stone"]}
	# Gibbets between the columns: two forked posts, a crossbar, and the cage under
	# it. They stand at the rim, clear of the fighting ground in the middle.
	for index in 3:
		var angle := TAU * (float(index) + 0.5) / 3.0 + 0.35
		var at := Vector3(cos(angle) * (radius - 4.4), 0.0, sin(angle) * (radius - 4.4))
		_gibbet(_prop_host(at, rng), mats, iron, solid, rng)
	# Every other column carries a cage off its capital, on a chain, above the
	# shoulders: the colonnade is where the pit keeps what is left of the last
	# bodies it took.
	for index in range(0, 16, 4):
		var angle := TAU * float(index) / 16.0 + 0.16
		var host := _prop_host(Vector3(cos(angle) * (radius - 3.0), 0.0,
			sin(angle) * (radius - 3.0)), rng)
		var hung := CampKit.Merged.new()
		CampKit.add_beam(hung, Vector3(0.0, 4.86, 0.0), Vector3(0.0, 4.42, 0.0), 0.026,
			mats["rag"], 4)
		_cage(hung, mats, iron, Vector3(0.0, 4.42, 0.0), rng)
		hung.commit(host, "ColumnCage")
	# The wardens' string-work and their trees, along the rim either side of them.
	for index in 3:
		var angle := TAU * (float(index) + 0.5) / 3.0 - 0.45
		var at := Vector3(cos(angle) * (radius - 4.8), 0.0, sin(angle) * (radius - 4.8))
		CampKit.rag_tree(_prop_host(at, rng), mats, solid, 761 + index * 53)
	for index in 2:
		var angle := -PI * 0.5 + (0.85 if index == 0 else -0.85)
		var at := Vector3(cos(angle) * (radius - 5.6), 0.0, sin(angle) * (radius - 5.6))
		CampKit.wicker_effigy(_prop_host(at, rng), mats, solid, 811 + index * 29)
	var web_angle := PI * 0.5 + 0.32
	CampKit.charm_web(_prop_host(Vector3(cos(web_angle) * (radius - 5.2), 0.0,
		sin(web_angle) * (radius - 5.2)), rng), mats, solid, 3.4, 2.0, 877)
	# The small work: one merged batch, so a floor covered in bones, pots, masks and
	# stakes is a single mesh and not thirty.
	var clutter := CampKit.Merged.new()
	for index in 7:
		var angle := TAU * (float(index) + 0.25) / 7.0
		var distance := radius - rng.randf_range(6.0, 8.5)
		var at := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var yaw := rng.randf_range(0.0, TAU)
		match index % 4:
			0:
				CampKit.bone_heap(clutter, mats, at, yaw, 913 + index)
			1:
				CampKit.pot_stack(clutter, mats, at, yaw, 947 + index)
			2:
				CampKit.mask_stake(clutter, mats, at, yaw, 971 + index)
			_:
				CampKit.skull_stakes(clutter, mats, at, yaw, 3, 0.7, 1009 + index)
	clutter.commit(self, "PitClutter", false)
	# The offering stone and its skull ring, on the entry side where a party walks
	# in and can see what kind of host the pit is.
	var offering_angle := PI * 0.5 + 0.9
	var offering_at := Vector3(cos(offering_angle) * (radius - 7.2), 0.0,
		sin(offering_angle) * (radius - 7.2))
	var offering := CampKit.Merged.new()
	CampKit.offering_stone(offering, mats, offering_at, rng.randf_range(0.0, TAU), 1031)
	CampKit.skull_ring(offering, mats, offering_at + Vector3(1.1, 0.0, 0.4), 1.5, 7, 1039)
	CampKit.add_collider(solid, Transform3D.IDENTITY, Vector3(1.5, 0.8, 1.1),
		offering_at + Vector3(0.0, 0.4, 0.0))
	offering.commit(self, "PitOffering")
	# A cauldron over coals, burning cold: the one light at the edge of the ring,
	# and the wrong colour for it.
	var cauldron_angle := -PI * 0.5 - 1.0
	var cauldron := Node3D.new()
	cauldron.position = Vector3(cos(cauldron_angle) * (radius - 6.4), 0.0,
		sin(cauldron_angle) * (radius - 6.4))
	add_child(cauldron)
	var pot := CampKit.Merged.new()
	CampKit.cauldron(pot, mats, Vector3.ZERO, rng.randf_range(0.0, TAU), 1.0)
	FireFx.flame_cards(pot, CampDressing.cold_flame(), rng, 0.40, 0.88)
	pot.commit(cauldron, "Cauldron")
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.52, 0.68, 1.0)
	glow.light_energy = 1.4
	glow.omni_range = 9.0
	glow.position = Vector3(0.0, 1.4, 0.0)
	cauldron.add_child(glow)
	# The blood of the last fight, laid flat on the sand where the waves met.
	var stains := CampKit.Merged.new()
	var variants := CampDressing.stain_materials()
	for index in 9:
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * (radius - 6.0)
		var at := Vector3(cos(angle) * distance, 0.03, sin(angle) * distance)
		CampDressing.add_stain(stains, Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)),
			at), rng.randf_range(0.7, 1.9), rng.randf_range(0.8, 1.5),
			index % variants.size())
	stains.commit(self, "PitBlood", false)


## One prop host: the woodland's builders lay their geometry out around the host's
## own transform, so the host is what stands a prop somewhere.
func _prop_host(at: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var host := Node3D.new()
	host.position = at
	host.rotation.y = rng.randf_range(0.0, TAU)
	add_child(host)
	return host


## Two forked posts, a crossbar and a hanging cage: the pit's own gallows, built to
## the camp's recipe. The cage's floor hangs at 2.6 m - above every standing head,
## which is what keeps the doodads off the fighters' shoulders - and the two posts
## are the only part of it a body can walk into.
func _gibbet(host: Node3D, mats: Dictionary, iron: Dictionary, solids: StaticBody3D,
		rng: RandomNumberGenerator) -> void:
	var m := CampKit.Merged.new()
	var base := host.transform
	for side in [-1.0, 1.0]:
		CampKit.add_ball(m, 0.26, Vector3(side * 1.25, 0.02, 0.0), mats["boulder_stone"],
			Vector3(1.2, 0.4, 1.2), 7, 4)
		CampKit.add_beam(m, Vector3(side * 1.25, -0.18, 0.0),
			Vector3(side * 1.18, 3.72, side * 0.04), 0.12, mats["twig_dark"], 6, 0.09)
		CampKit.add_collider(solids, base, Vector3(0.26, 3.6, 0.26),
			Vector3(side * 1.22, 1.8, 0.0))
	CampKit.add_beam(m, Vector3(-1.34, 3.64, 0.0), Vector3(1.34, 3.64, 0.02), 0.10,
		mats["drift"], 6, 0.085)
	# A cold lantern lashed under the crossbar: the gallows is the one thing out at
	# the rim that a body can see from the middle of the ring.
	CampKit.add_beam(m, Vector3(0.62, 3.60, 0.02), Vector3(0.62, 3.22, 0.02), 0.010,
		mats["rag"], 3)
	CampKit.add_ball(m, 0.085, Vector3(0.62, 3.14, 0.02), mats["ember"], Vector3(1.0, 1.5, 1.0), 7, 4)
	var lantern := OmniLight3D.new()
	lantern.light_color = Color(0.62, 0.78, 1.0)
	lantern.light_energy = 1.6
	lantern.omni_range = 9.0
	lantern.position = Vector3(0.62, 3.1, 0.02)
	host.add_child(lantern)
	# The rope, then the cage under it.
	CampKit.add_beam(m, Vector3(0.0, 3.60, 0.0), Vector3(0.02, 3.02, 0.0), 0.026,
		mats["rag"], 4)
	_cage(m, mats, iron, Vector3(0.02, 3.02, 0.0), rng)
	m.commit(host, "Gibbet")


## One iron gibbet cage hung from `top`: three hoops, eight bars, a barred floor and
## the bones of whoever was left in it. Its floor sits 1.14 m under `top`, so a cage
## hung off a column's capital clears every standing head in the ring.
func _cage(m, mats: Dictionary, iron: Dictionary, top: Vector3, rng: RandomNumberGenerator) -> void:
	for row in [0.0, -0.55, -1.06]:
		CampKit.add_ring(m, top + Vector3(0.0, row, 0.0), 0.0, 0.44, 0.50, iron["iron"],
			0.0, 12, 4)
	for bar in 8:
		var angle := TAU * float(bar) / 8.0
		var foot := top + Vector3(cos(angle) * 0.45, -1.06, sin(angle) * 0.45)
		CampKit.add_beam(m, foot, foot + Vector3(0.0, 1.06, 0.0), 0.022, iron["steel"], 4)
	CampKit.add_cyl_disc(m, 0.47, 0.05, top + Vector3(0.0, -1.08, 0.0), iron["iron"], 12)
	# What the cage was for.
	CampKit.add_skull(m, mats, top + Vector3(0.02, -0.88, 0.06), 0.4, 0.55, true)
	CampKit.add_beam(m, top + Vector3(-0.22, -0.62, -0.05), top + Vector3(0.24, -0.70, 0.12),
		0.026, mats["bone"], 3, 0.012)
	CampKit.add_beam(m, top + Vector3(-0.10, -0.78, 0.18), top + Vector3(0.14, -0.88, 0.24),
		0.020, mats["bone"], 3, 0.010)
	for strip in 3:
		CampKit.add_box(m, Vector3(0.10, rng.randf_range(0.28, 0.46), 0.02),
			top + Vector3(rng.randf_range(-0.3, 0.3), -0.45, 0.46), mats["rag"],
			rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.2, 0.2))


func _scatter_rocks(kind: String, copies: int, min_scale: float, max_scale: float) -> void:
	var mesh := RockKit.mesh(kind, seed_value + kind.hash())
	if mesh == null:
		return
	var stone := Geo.material(Color(0.24, 0.23, 0.21), 0.0, 0.95)
	var instances: Array[Dictionary] = []
	for _index in copies:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(radius * 0.35, radius - 4.0)
		var scale_at := _rng.randf_range(min_scale, max_scale)
		instances.append({"transform": Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) .scaled(Vector3(scale_at, scale_at * 0.7, scale_at)),
			Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))})
	WorldScatter.batch(_dressing, "Rocks_%s" % kind, mesh, stone, instances, 20.0)


## The chamber's shell: a wall just behind the fog sheet and, for a cave, a roof
## that closes the sky. An island is a piece of the world, not a slice of it, and
## a demon floor under an open blue sky read as a stage set.
func _build_shell(colour: Color, height: float, roofed: bool) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.96
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = radius + 1.5
	wall_mesh.bottom_radius = radius + 1.5
	wall_mesh.height = maxf(2.0, height)
	wall_mesh.radial_segments = 56
	wall_mesh.rings = 3
	wall_mesh.cap_top = false
	wall_mesh.cap_bottom = false
	var wall := MeshInstance3D.new()
	wall.name = "ChamberWall"
	wall.mesh = wall_mesh
	wall.material_override = material
	wall.position = Vector3(0.0, wall_mesh.height * 0.5, 0.0)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	if not roofed:
		return
	var roof_mesh := CylinderMesh.new()
	roof_mesh.top_radius = radius + 1.5
	roof_mesh.bottom_radius = radius + 1.5
	roof_mesh.height = 1.2
	roof_mesh.radial_segments = 56
	roof_mesh.rings = 2
	var roof := MeshInstance3D.new()
	roof.name = "ChamberRoof"
	roof.mesh = roof_mesh
	roof.material_override = material
	roof.position = Vector3(0.0, wall_mesh.height + 0.6, 0.0)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(roof)


func _build_litter(data: Dictionary) -> void:
	# Enough small stones and bones to keep the floor from reading as graph paper,
	# at one draw call each.
	var bone := Geo.material(Color(0.72, 0.66, 0.53), 0.0, 0.75)
	# A pebble, not a hole: the second litter tone is mid-stone, never near-black,
	# because a flat dark decal on a lit floor reads as a gap in it.
	var stone := Geo.material(Color(0.34, 0.31, 0.26), 0.0, 0.95)
	for index in 20:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := sqrt(_rng.randf()) * (radius - 3.0)
		var at := Vector3(cos(angle) * distance, 0.02, sin(angle) * distance)
		var piece := Geo.box(_dressing, Vector3(_rng.randf_range(0.16, 0.4), 0.05,
			_rng.randf_range(0.1, 0.24)), at,
			bone if index % 3 == 0 else stone)
		piece.rotation.y = _rng.randf_range(0.0, TAU)
		piece.rotation.z = _rng.randf_range(-0.1, 0.1)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if str(data.get("id", "wilderness")) == "wilderness":
		_build_leaf_drifts()


## Fallen leaves in drifts, out of the foliage atlas the wood's own trees are
## painted from: a flat card of leaves lying on the turf is what makes a wood
## floor read as a wood floor rather than as a lawn, and two batched cards cost
## the island four draw calls. `UV2` is the foliage shader's wind weight, held at
## zero, so a leaf on the ground stays where it fell.
func _build_leaf_drifts() -> void:
	var leaves_id := "leaves_amber"
	var material := TextureLibrary.foliage_material_tuned(leaves_id, Vector2(0.0, 1.0))
	var cells := mini(2, TextureLibrary.cell_count(leaves_id))
	if cells <= 0:
		return
	var piles: Array = []
	for cell_index in cells:
		piles.append([] as Array[Dictionary])
	# Small and dark: an autumn leaf under a closed canopy, not a spot of paint.
	# A drift is many leaves, so the cards are a hand's width and there are more
	# of them than there are tufts.
	for _index in 420:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := sqrt(_rng.randf()) * (radius - 3.0)
		var size := _rng.randf_range(0.30, 0.78)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
			Vector3(size, 1.0, size))
		var shade := _rng.randf_range(0.75, 1.05)
		(piles[_rng.randi_range(0, cells - 1)] as Array[Dictionary]).append({
			"transform": Transform3D(basis, Vector3(cos(angle) * distance, 0.022,
				sin(angle) * distance)),
			"color": Color(0.34 * shade, 0.30 * shade, 0.23 * shade)})
	for cell_index in cells:
		var instances: Array[Dictionary] = piles[cell_index]
		if instances.is_empty():
			continue
		WorldScatter.batch(_dressing, "LeafDrift_%d" % cell_index,
			_leaf_card(TextureLibrary.atlas_cell(leaves_id, cell_index)),
			material, instances, 48.0, {"cast_shadow": false})


## One atlas cell laid flat: four vertices, two triangles, the cell's own rect as
## its UVs.
static func _leaf_card(cell: Rect2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector2] = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5),
		Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	var uvs: Array[Vector2] = [Vector2(cell.position.x, cell.end.y),
		Vector2(cell.end.x, cell.end.y), Vector2(cell.end.x, cell.position.y),
		Vector2(cell.position.x, cell.position.y)]
	for corner in [0, 1, 2, 0, 2, 3]:
		var point: Vector2 = corners[corner]
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[corner])
		st.set_uv2(Vector2(0.0, 0.0))
		st.set_color(Color.WHITE)
		st.add_vertex(Vector3(point.x, 0.0, point.y))
	return st.commit()


static func _pick(values: Array, fallback: Color,
		rng: RandomNumberGenerator) -> Color:
	if values.is_empty():
		return fallback
	var value: Variant = values[rng.randi_range(0, values.size() - 1)]
	if value is Color:
		return value
	return fallback
