extends RefCounted
## The armour a reward chest pays out: one random slot per body, a set the level's
## ladder can afford, and a small chance of one to three modifiers welded to the
## piece.
##
## The roll is pure but for the generator it is handed. The director owns the
## run's seed, so the same run and the same chest answer the same piece, and
## nothing here touches a scene or grants an upgrade. `RunPlayer.wear_armor` is
## what puts the piece on a body and takes its modifiers.
##
## Quality is the share of a blow a set stops (`armor_data.gd`). `naked` and
## `cloth` are never rolled - the first is what a body is born in, the second is
## the town's own robe - and a piece never rolls below the set the body already
## wears in that slot, so a chest is always a piece worth the walk to it.

const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")

## Worst to best, by the figure the set stops. Makeshift and leather share a
## body figure, so leather ranks above it only as the better-made of the two.
const QUALITY := ["naked", "cloth", "makeshift", "leather", "mail", "plate"]
## The sets a chest rolls off, by island (1-based): every island's row is a
## weight per *set index* in `ArmorData.SET_IDS`. The last row carries every
## island past it, so an endless run still rides one ladder.
const LADDER := [
	{4: 60.0, 0: 40.0},
	{4: 30.0, 0: 45.0, 1: 25.0},
	{4: 15.0, 0: 40.0, 1: 45.0},
	{4: 5.0, 0: 25.0, 1: 45.0, 2: 25.0},
	{0: 15.0, 1: 45.0, 2: 40.0},
]
## The chance a piece carries any modifiers at all: 6% on level one and a point a
## level, never past the cap. A larger level is both likelier to be modified and
## likelier to carry the second and third.
const MOD_CHANCE_BASE := 0.06
const MOD_CHANCE_STEP := 0.01
const MOD_CHANCE_CAP := 0.35
## The second is rolled from level one at 25% and two points a level; the third
## only from level ten, on its own roll. Both are capped so a piece never
## becomes a card of its own.
const SECOND_BASE := 0.25
const SECOND_STEP := 0.02
const THIRD_BASE := 0.08
const THIRD_STEP := 0.015
const THIRD_LEVEL := 10
const EXTRA_CAP := 0.55
## Steel: the colour of a piece with no tier of its own.
const STEEL := Color(0.74, 0.78, 0.80)


## One piece, rolled for a body wearing `worn` (`{slot: set index}`). `exclude`
## is the rows already at their ceiling or already bought this chest, and
## `carrier_tags` is the hand families the body can use, so a piece never welds a
## staff row onto a bow. `floor_add` raises the set floor by that many quality
## ranks: a legendary Gear chest pays a set nobody would find on this island.
static func roll(rng: RandomNumberGenerator, level: int, island: int,
		worn: Dictionary = {}, luck: int = 0, exclude: Array = [],
		carrier_tags: Array = [], floor_add: int = 0) -> Dictionary:
	var slot := str(ArmorData.SLOTS[rng.randi_range(0, ArmorData.SLOTS.size() - 1)])
	var set_index := roll_set(rng, island, int(worn.get(slot, ArmorData.NONE)),
		floor_add)
	var item_id := ArmorData.item_id(set_index, slot)
	var item: Dictionary = State.ITEMS.get(item_id, {})
	var piece := {
		"slot": slot,
		"set": set_index,
		"item_id": item_id,
		"name": str(item.get("name", slot.capitalize())),
		"level": maxi(1, level),
		"mods": [],
	}
	if rng.randf() >= mod_chance(level):
		return piece
	piece["mods"] = Mods.roll_shelf(rng, Mods.SOURCE_WELD, island,
		modifier_count(rng, level), luck, exclude, carrier_tags)
	return piece


## The set a chest rolls, never worse than `floor_set`. The island's row is
## filtered to the sets that clear the floor and rolled by weight; an island
## whose whole row sits below the floor answers the floor itself, so a plate body
## is handed plate rather than a downgrade it would have to refuse.
static func roll_set(rng: RandomNumberGenerator, island: int, floor_set: int,
		floor_add: int = 0) -> int:
	var floor_rank := quality_rank(floor_set) + maxi(0, floor_add)
	var row: Dictionary = LADDER[clampi(island, 1, LADDER.size()) - 1]
	var weights: Dictionary = {}
	var total := 0.0
	for key in row:
		if quality_rank(int(key)) < floor_rank:
			continue
		weights[int(key)] = float(row[key])
		total += float(row[key])
	if weights.is_empty():
		# An island whose whole row sits under the floor answers the floor itself,
		# which is the one piece this island could never have paid.
		return _set_at_rank(floor_rank) if floor_add > 0 \
			else clampi(floor_set, 0, ArmorData.SET_IDS.size() - 1)
	var pick := rng.randf_range(0.0, total)
	var walked := 0.0
	var last := 0
	for key in weights:
		last = int(key)
		walked += float(weights[key])
		if pick <= walked:
			return last
	return last


## The set that sits at one quality rank, clamped to the best there is.
static func _set_at_rank(rank: int) -> int:
	var best := 0
	var best_rank := -2
	for index in ArmorData.SET_IDS.size():
		var held := quality_rank(index)
		if held <= rank and held > best_rank:
			best = index
			best_rank = held
	return best


## How good a set is, worst to best. `ArmorData.NONE` and anything outside the
## table answer -1, which every row clears: a body wearing nothing is floored by
## nothing.
static func quality_rank(set_index: int) -> int:
	if set_index < 0 or set_index >= ArmorData.SET_IDS.size():
		return -1
	return QUALITY.find(str(ArmorData.SET_IDS[set_index]))


## The chance a piece carries modifiers: 6% at level one, +1% a level, capped.
static func mod_chance(level: int) -> float:
	return clampf(MOD_CHANCE_BASE + MOD_CHANCE_STEP * float(maxi(0, level - 1)),
		0.0, MOD_CHANCE_CAP)


## How many modifiers a piece that rolled any carries: always 1, the second on
## its own roll, and from level ten the third on one of its own.
static func modifier_count(rng: RandomNumberGenerator, level: int) -> int:
	if level >= THIRD_LEVEL and rng.randf() < clampf(
			THIRD_BASE + THIRD_STEP * float(level - THIRD_LEVEL), 0.0, EXTRA_CAP):
		return 3
	if rng.randf() < clampf(SECOND_BASE + SECOND_STEP * float(maxi(0, level - 1)),
			0.0, EXTRA_CAP):
		return 2
	return 1


# --- presentation -----------------------------------------------------------

## The piece's own name, as the catalogue calls the same set on the town's racks.
static func title_of(piece: Dictionary) -> String:
	return str(piece.get("name", "Armour")).to_upper()


## The short line under the pop's name: its item level and, when it has any, how
## many modifiers ride it. The names themselves go in the HUD's line - a world
## label wide enough for three of them would cover the island.
static func detail_of(piece: Dictionary) -> String:
	var line := "LV %d" % maxi(1, int(piece.get("level", 1)))
	var mods := _mods_of(piece)
	if not mods.is_empty():
		line += "  ·  +%d" % mods.size()
	return line


## What the HUD keeps: the piece, its level, and the names of what is welded on.
static func status_line(piece: Dictionary) -> String:
	var line := "%s  ·  %s" % [title_of(piece), detail_of(piece)]
	var mods := _mods_of(piece)
	if mods.is_empty():
		return line
	var names := PackedStringArray()
	for id in mods:
		names.append(str(Mods.name_of(str(id))).to_upper())
	return "%s  %s" % [line, ", ".join(names)]


## The colour a piece is drawn in: the tier of its best modifier, steel when it
## carries none. A common row is common loot, not a signal, so it stays steel.
static func colour_of(piece: Dictionary) -> Color:
	var rank := -1
	for id in _mods_of(piece):
		rank = maxi(rank, Mods.RARITIES.find(Mods.rarity_of(str(id))))
	if rank <= 0:
		return STEEL
	return Mods.RARITY_COLOUR.get(str(Mods.RARITIES[rank]), STEEL)


## The piece's welded modifier ids, whatever a dictionary that came off the wire
## carried in `mods`.
static func _mods_of(piece: Dictionary) -> Array:
	var raw: Variant = piece.get("mods", [])
	return raw if raw is Array else []
