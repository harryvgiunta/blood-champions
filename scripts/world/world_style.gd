class_name WorldStyle
extends RefCounted
## Presentation-only description of a world region (frontier / arena).
##
## Everything the world-art framework needs to build scenery is data: sky, ground
## blending, tree species, grass, ground cover and building materials. It is
## deliberately free of nodes and resources so a scene can clone/modify a style
## without touching the builders.
##
## Extending:
## - Add a species to `default_trees()` (or append one in a scene). Required keys are
##   documented on `_species()` below; `TreeKit` only reads those keys.
## - Add texture ids here; `TextureLibrary` resolves `res://assets/world/textures/<id>.png`.
## - Per-region tweaks belong in `frontier()` / `arena()` rather than in builders.

var id: String = ""
var sky: Dictionary = {}
var ground: Dictionary = {}
var trees: Array[Dictionary] = []
var grass: Dictionary = {}
var ground_cover: Dictionary = {}
var props: Dictionary = {}


## Returns the built-in species library. Scenes may copy this array and append
## custom species; weights are relative spawn weights, not percentages.
static func default_trees() -> Array[Dictionary]:
	return [
		_species({
			"id": "ironoak",
			"form": "broadleaf",
			"bark": "bark_oak",
			"leaves": "leaves_broadleaf",
			"height": Vector2(10.0, 15.0),
			# trunk = (base radius / height, trunk height / total height)
			"trunk": Vector2(0.046, 0.60),
			# crown = (crown radius / height, crown height / total height)
			"crown": Vector2(0.30, 0.50),
			"weight": 1.35,
			"tints": [Color("e8f2c0"), Color("d3e6a4"), Color("f8fae0"), Color("c6df98")],
			"bark_tints": [Color.WHITE, Color("f5eadc"), Color("e8d8c2")],
			"wind": Vector2(0.20, 1.0),
			"variants": 4,
		}),
		_species({
			"id": "briar_pine",
			"form": "conifer",
			"bark": "bark_pine",
			"leaves": "needles_pine",
			"height": Vector2(9.0, 16.0),
			"trunk": Vector2(0.034, 0.97),
			"crown": Vector2(0.24, 0.74),
			"weight": 1.15,
			"tints": [Color("cbe2ac"), Color("b6d49a"), Color("dcebc0"), Color("a6c78e")],
			"bark_tints": [Color("e8d3c0"), Color.WHITE, Color("d6bfa9")],
			"wind": Vector2(0.08, 0.8),
			"variants": 4,
		}),
		_species({
			"id": "silver_birch",
			"form": "birch",
			"bark": "bark_birch",
			"leaves": "leaves_birch",
			"height": Vector2(7.0, 11.0),
			"trunk": Vector2(0.024, 0.78),
			"crown": Vector2(0.20, 0.42),
			"weight": 0.75,
			"tints": [Color("eaf6c6"), Color("d8eab4"), Color("f6fae0"), Color("c9e6a2")],
			"bark_tints": [Color.WHITE, Color("f4f0e6"), Color("e6e2d6")],
			"wind": Vector2(0.24, 1.15),
			"variants": 3,
		}),
		_species({
			"id": "amber_rowan",
			"form": "broadleaf",
			"bark": "bark_oak",
			"leaves": "leaves_amber",
			"height": Vector2(6.0, 9.5),
			"trunk": Vector2(0.042, 0.56),
			"crown": Vector2(0.32, 0.54),
			"weight": 0.62,
			"tints": [Color("f8dca4"), Color("f0c88c"), Color("fcebc0"), Color("eab470")],
			"bark_tints": [Color("f1dfca"), Color.WHITE, Color("e5d0b8")],
			"wind": Vector2(0.18, 1.05),
			"variants": 3,
		}),
		_species({
			"id": "hollow_snag",
			"form": "snag",
			"bark": "bark_dead",
			"leaves": "",
			"height": Vector2(5.0, 9.0),
			"trunk": Vector2(0.052, 0.92),
			"crown": Vector2(0.12, 0.20),
			"weight": 0.38,
			"tints": [],
			"bark_tints": [Color("e8e6dc"), Color("d6d4ca"), Color.WHITE],
			"wind": Vector2(0.05, 0.7),
			"variants": 3,
		}),
	]


## Warm, sunlit woodland frontier. The palette pushes yellow-green grass and
## amber accents under a natural blue sky with a pale horizon haze.
static func frontier() -> WorldStyle:
	var style := WorldStyle.new()
	style.id = "frontier"
	style.sky = {
		"texture": "sky_frontier",
		"energy": 0.8,
		"sun_rotation": Vector3(-48.0, -32.0, 0.0),
		"sun_color": Color("ffe2b3"),
		"sun_energy": 1.05,
		"sun_shadow_distance": 110.0,
		"ambient_color": Color("c6d3dd"),
		"ambient_energy": 0.52,
		"use_sky_ambient": true,
		# Depth fog, not the old all-over exponential haze: the near field stays
		# clear to 65 m, then one smooth ramp reaches fully opaque haze at
		# 145 m. Still a long view, no longer a view across the whole valley -
		# and it is what makes parking a body at `MobLod.DORMANT_DISTANCE`
		# invisible.
		"fog_mode": "depth",
		"fog_color": Color("c9d2d8"),
		"fog_density": 0.0,
		"fog_depth_begin": 65.0,
		"fog_depth_end": 145.0,
		"fog_depth_curve": 2.0,
		"fog_sun_scatter": 0.25,
		"fog_sky_affect": 0.12,
		"fog_aerial_perspective": 0.35,
		"tonemap": Environment.TONE_MAPPER_FILMIC,
		"exposure": 0.85,
		"saturation": 1.28,
		"contrast": 1.07,
	}
	style.ground = {
		"grass_texture": "terrain_grass",
		"litter_texture": "terrain_litter",
		"dirt_texture": "terrain_dirt",
		"rock_texture": "terrain_rock",
		"noise_texture": "terrain_noise",
		"macro_texture": "terrain_macro",
		"tile": 4.0,
		"litter_tile": 3.2,
		"dirt_tile": 6.0,
		"rock_tile": 5.0,
		"macro_tile": 27.0,
		"grass_tint": Color("b9c98a"),
		"grass_dry_tint": Color("d6cf94"),
		"litter_tint": Color("c9b79a"),
		"dirt_tint": Color("c9ae86"),
		"rock_tint": Color("a9a89c"),
		"litter_cover": 0.14,
		"dry_cover": 0.32,
		"detail_strength": 1.0,
		"detail_fade": Vector2(95.0, 150.0),
	}
	style.trees = default_trees()
	style.grass = {
		"texture": "grass_meadow",
		"count": 18000,
		"range": 72.0,
		"chunk_size": 20.0,
		"radius": 118.0,
		"tints": [Color("c8dc96"), Color("b6d086"), Color("dde8aa"), Color("a5c47c"), Color("d5d58e")],
		"shade_tint": Color("6f8b4e"),
		"wind": Vector2(0.10, 1.2),
		"density_falloff": Vector2(1.0, 0.42),
		"max_slope": 30.0,
		"height_range": Vector2(-0.6, 400.0),
		"scale": Vector2(0.75, 1.4),
		"clump_variants": 3,
	}
	style.ground_cover = {
		"flowers": {
			"texture": "flowers", "count": 1400, "range": 62.0, "chunk_size": 16.0,
			"radius": 116.0, "scale": Vector2(0.6, 1.15), "wind": Vector2(0.07, 1.1),
			"max_slope": 26.0, "height_range": Vector2(-0.4, 400.0),
			"tints": [Color("f0e2a6"), Color("e8b4c6"), Color("b9c7ef"), Color("f3c98f"), Color.WHITE],
			"shade_tint": Color("80906a"),
		},
		"ferns": {
			"texture": "fern", "count": 900, "range": 56.0, "chunk_size": 20.0,
			"radius": 118.0, "scale": Vector2(0.7, 1.35), "wind": Vector2(0.06, 1.0),
			"max_slope": 34.0, "height_range": Vector2(-0.3, 400.0),
			"tints": [Color("c4dda0"), Color("a9c985"), Color("dcebb8")],
			"shade_tint": Color("5f7b48"),
		},
		# Rocks/pebbles are presentation-only props: scenes place them through
		# WorldScatter with TextureLibrary.rock_material(). GrassField intentionally
		# ignores these entries so it only returns grass/flower/fern counts.
		"rocks": {
			"texture": "rock", "count": 90, "range": 80.0, "chunk_size": 24.0,
			"radius": 120.0, "scale": Vector2(0.55, 1.7), "y_scale": Vector2(0.4, 0.9),
			"tints": [Color("a8aca1"), Color("9a9e94"), Color("b3b7ac"), Color("8e9288")],
		},
		"pebbles": {
			"texture": "rock", "count": 150, "range": 45.0, "chunk_size": 16.0,
			"radius": 118.0, "scale": Vector2(0.12, 0.34), "y_scale": Vector2(0.5, 0.8),
			"tints": [Color("b4ae9e"), Color("a49e8e"), Color("c2bcae")],
		},
	}
	style.props = {
		"kinds": {
			"wood": "wood_planks",
			"timber": "timber",
			"plaster": "plaster",
			"roof": "roof_shingles",
			"stone": "stone_blocks",
		},
		# Triplanar repeats per metre for each kind.
		"scale": {"wood": 0.6, "timber": 0.75, "plaster": 0.4, "roof": 0.9, "stone": 0.55},
		"tints": {
			"wood": Color("d9c39d"),
			"timber": Color("b9a58a"),
			"plaster": Color("f4edcf"),
			"roof": Color("d8b8a4"),
			"stone": Color("d7d9cd"),
		},
	}
	return style

## The wood at night: the frontier's own terrain and foliage, one stop down, with
## the depth fog replaced by a thick exponential haze the torches have to cut
## through. EnvironmentKit writes the density after the fog mode, which is the
## only way a density survives in Godot 4.7.
##
## Public because the one world is *this* night, not three: the camp clearing and
## the town are built inside the same style, so a body that walks from the cages
## to the square never crosses a seam in the light or the fog.
static func night() -> WorldStyle:
	var style := WorldStyle.frontier()
	style.id = "night_wood"
	style.sky = {
		"texture": "sky_frontier",
		# The panorama at 0.10 filled the frame with a near-black hemisphere the
		# moment a body turned round; it is a night sky now, not a void, and the
		# sky's own ambient is what keeps the wood behind the squad readable.
		"energy": 0.55,
		"sun_rotation": Vector3(-58.0, -34.0, 0.0),
		"sun_color": Color(0.54, 0.62, 0.88),
		"sun_energy": 1.0,
		"sun_shadow_distance": 70.0,
		"ambient_color": Color(0.17, 0.20, 0.26),
		"sun_shadows": false,
		# Sky ambient at a modest fill: the panorama is brighter now, but this is
		# still a night wood, not a lit stage.
		"ambient_energy": 1.3,
		"use_sky_ambient": true,
		"fog_mode": "exponential",
		# A lighter haze that also eats the sky: the horizon closes at its own
		# distance instead of turning the background into a black wall.
		"fog_color": Color(0.075, 0.094, 0.124),
		"fog_density": 0.012,
		"fog_sun_scatter": 0.05,
		"fog_sky_affect": 0.38,
		"fog_aerial_perspective": 0.18,
		"tonemap": Environment.TONE_MAPPER_FILMIC,
		"exposure": 1.0,
		"saturation": 0.84,
		"contrast": 1.06,
	}
	# The wood's floor: grass where the canopy opens, fallen leaves in broad
	# patches between (`litter_cover`), trodden dirt wherever the ground map says
	# feet have been, rock on the rim. The tints are the night's grade on textures
	# authored at daylight value, so a torch finds real colour in the ground.
	style.ground = {
		"grass_texture": "terrain_grass",
		"litter_texture": "terrain_litter",
		"dirt_texture": "terrain_dirt",
		"rock_texture": "terrain_rock",
		"noise_texture": "terrain_noise",
		"macro_texture": "terrain_macro",
		"tile": 4.0,
		"litter_tile": 3.2,
		"dirt_tile": 5.0,
		"rock_tile": 4.0,
		"macro_tile": 24.0,
		"grass_tint": Color("5b6a4a"),
		"grass_dry_tint": Color("6e6a4a"),
		"litter_tint": Color("857560"),
		"dirt_tint": Color("8a7a64"),
		"rock_tint": Color("54534c"),
		"litter_cover": 0.32,
		"dry_cover": 0.3,
		"blend_contrast": 0.55,
		"blend_softness": 0.1,
		"normal_strength": 1.0,
		"detail_strength": 0.6,
		"detail_fade": Vector2(70.0, 120.0),
	}
	# The cover is placed by shape, not by disc (`GrassField.for_area` with a
	# sampler): the lane's verges and the camp's rim ask for these densities per
	# square metre, and the worn ground thins them (`terrain.gd`'s `is_trodden`).
	# A chunk is drawn while its centre is inside `range`, so chunks stay small
	# enough (48 m) that the next one appears inside the shader's own fade; one
	# clump mesh and no flowers keep the whole verge to two draws a chunk.
	style.grass = {
		"texture": "grass_meadow",
		"density": 0.42,
		"range": 76.0,
		"chunk_size": 48.0,
		"tints": [Color("4c5c3a"), Color("3e4e34"), Color("5a6648"), Color("34442c")],
		"shade_tint": Color("20281c"),
		"wind": Vector2(0.10, 1.2),
		"max_slope": 30.0,
		"height_range": Vector2(-40.0, 90.0),
		"scale": Vector2(0.80, 1.5),
		"clump_variants": 1,
	}
	style.ground_cover = {
		"ferns": {
			"texture": "fern", "density": 0.05, "range": 76.0, "chunk_size": 48.0,
			"scale": Vector2(0.75, 1.45), "wind": Vector2(0.06, 1.0),
			"max_slope": 34.0, "height_range": Vector2(-40.0, 90.0),
			"tints": [Color("41552f"), Color("35472a"), Color("56683c")],
			"shade_tint": Color("1e2718"),
		},
	}
	return style


## The species entry this style builds a stand from, or {} when the id names none.
func species_by_id(species_id: String) -> Dictionary:
	for entry in trees:
		if String(entry.get("id", "")) == species_id:
			return entry
	return {}


static func _species(values: Dictionary) -> Dictionary:
	var entry := {
		"id": "",
		"form": "broadleaf",
		"bark": "bark_oak",
		"leaves": "",
		"height": Vector2(8.0, 12.0),
		"trunk": Vector2(0.04, 0.62),
		"crown": Vector2(0.28, 0.5),
		"weight": 1.0,
		"tints": [] as Array[Color],
		"bark_tints": [] as Array[Color],
		"wind": Vector2(0.15, 1.0),
		"variants": 3,
	}
	entry.merge(values, true)
	entry["tints"] = _colours(entry["tints"])
	entry["bark_tints"] = _colours(entry["bark_tints"])
	return entry


static func _colours(values: Array) -> Array[Color]:
	var result: Array[Color] = []
	for value in values:
		result.append(value as Color)
	return result
