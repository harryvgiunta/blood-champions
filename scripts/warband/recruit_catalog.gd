class_name RecruitCatalog
extends RefCounted
## The recruiter's board: who a party can buy, what they carry, and what they
## cost.
##
## A recruit is a *body*, not a card: it is sworn as a warband mercenary
## (`Warband.hire_recruit`), fights the island with the band's own AI, and costs
## plain gold out of the run's purse. Its archetype is the contract's disposition
## (`WarbandContracts.DISPOSITIONS`), so the way it fights is not written here at
## all - the squad already owns a tank's hold-the-line, a melee body's press and a
## bow's kite, and it fights on the blood clone's clocks (`SquadDrive.FIGHT_TIER`).
##
## What this file owns is the three things a board has to answer:
##
##   who     the archetype, its label and the name on the card;
##   what    the kit it is sworn in - hands and armour - rolled from the rung its
##           level sits in, plus **one** item skill it will actually perform;
##   price   gold, rising with the level and with the rung's gear.
##
## ## The ladder, levels 1 to 50
##
## Five rungs of ten levels, the same blocks the run's islands are cut into, so a
## recruit bought at the first market is a rung-0 body and one bought before the
## fifth boss is a rung-4 body. A rung is a *kit*, not a stat block: the same
## hundred-health body is a twig bow in rags on level 6 and a longbow in leather
## on level 46.
##
## | rung | levels | ranged | tank | melee | armour |
## | --- | --- | --- | --- | --- | --- |
## | 0 | 1-10 | twig bow | club or cleaver + wooden board | heavy branch, or cleaver + shiv | makeshift |
## | 1 | 11-20 | shortbow | shortsword + buckler | shortsword + shiv, or cleaver + iron dagger | leather / mail |
## | 2 | 21-30 | shortbow or recurve | arming sword + kite shield | arming sword + iron dagger | leather / mail |
## | 3 | 31-40 | recurve | arming sword + kite or tower shield | greatsword, or arming sword + iron dagger | leather / plate |
## | 4 | 41-50 | recurve or longbow | arming sword + tower shield | greatsword, or arming sword + iron dagger | leather / plate |
##
## The opening is deliberately poor: rung 0 is the salvage tier - the same
## make-do steel a prisoner climbs out of a cage with - because a recruit bought
## for a level-6 party is a body, and a body with a twig bow in bark armour is a
## body the party's own arming has to carry. What changes with depth is the kit a
## recruit arrives *already wearing*; nothing re-dresses it afterwards (a
## recruit's gear is locked, see `Warband.is_gear_locked`), so the way to a
## better-armed body is a better-armed hire at a deeper board.
##
## ## The one skill
##
## A recruit is sworn with exactly one item skill on its bar - the rolled id is
## written into the roster's key list, which is what stops `SeatLoadout` from
## handing an AI body every skill its hands happen to fit. The pool is filtered
## three ways, in this order, and the last one is the hand:
##
##   1. `AbilityRules.AI_KINDS`: the kinds a body can aim and land on another
##      body (a ward, a backstab or a blink is not a recruit's skill);
##   2. the archetype's families from `AbilityRules.ABILITY_FAMILIES` - a bow
##      recruit rolls a bow skill and nothing else;
##   3. `AbilityRules.fits_gear` against the kit it just rolled, so the skill on
##      the card is one its own hands can fire.
##
## ## The board
##
## Three rows, always: one of each archetype, in a shuffled order, re-rolled
## every time the level loads (`RunDirector` rolls them with the stall's own RNG
## when a market or shop level stands). The kit, the skill, the name and the
## price are all rolled there, so two visits to two different level-6 markets
## offer three different recruits.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")

const ARCHETYPE_RANGED := "ranged"
const ARCHETYPE_TANK := "tank"
const ARCHETYPE_MELEE := "melee"
## Every archetype, the order the board lists them in before it is shuffled.
const ARCHETYPES := [ARCHETYPE_RANGED, ARCHETYPE_TANK, ARCHETYPE_MELEE]

## How many rows a board always carries: three options, one of each archetype.
const OPTIONS := 3
## The level one rung is worth, and the deepest rung the table has.
const RUNG_LEVELS := 10
const MAX_LEVEL := 50
## The level a town desk sells at. Hearthstead stands at the bottom of the
## ladder: its three bodies are rung-0 kits - a twig bow, makeshift steel and bark
## or rags - whatever the party has already fought, because the desk sells the
## body and not the progress. The deeper boards are the run's, priced by the
## level they stand on.
const TOWN_LEVEL := 1
## What a card calls itself. The first is the family sigil the art reads.
const LABELS := {
	ARCHETYPE_RANGED: "RANGED",
	ARCHETYPE_TANK: "TANK",
	ARCHETYPE_MELEE: "MELEE",
}
## The behaviour line on the card: what this body does when it locks on, in the
## contract's own words.
const BEHAVIOUR := {
	ARCHETYPE_RANGED: "Back line: looses from range, gives ground when crowded.",
	ARCHETYPE_TANK: "Holds the line behind its shield and never falls back.",
	ARCHETYPE_MELEE: "Presses the densest knot and falls back under 30% to bind a wound.",
}
## The skill families an archetype may roll. These are `AbilityRules`' own tags,
## not a second vocabulary.
const FAMILIES := {
	ARCHETYPE_RANGED: [AbilityRules.TYPE_BOW],
	ARCHETYPE_TANK: [AbilityRules.TYPE_SWORD, AbilityRules.TYPE_SHIELD],
	ARCHETYPE_MELEE: [AbilityRules.TYPE_TWO_HAND, AbilityRules.TYPE_SWORD,
		AbilityRules.TYPE_DAGGER],
}
## The disposition each archetype fights on (`WarbandContracts.DISPOSITIONS`).
const DISPOSITIONS := {
	ARCHETYPE_RANGED: Contracts.DISPOSITION_BOW,
	ARCHETYPE_TANK: Contracts.DISPOSITION_TANK,
	ARCHETYPE_MELEE: Contracts.DISPOSITION_MELEE,
}

## The kit ladder. One entry per rung: the hands it may be sworn with (a rolled
## pair of `[main, off]`, `""` for a bare hand) and the armour set every slot is
## cut from (`ArmorData.SET_IDS` by name). A rung with one row is not a choice -
## the deeper rungs are, because a body that costs four figures should be a body
## the board can sell twice.
const KITS := {
	ARCHETYPE_RANGED: [
		{"hands": [["bow_twig", ""]], "armor": "makeshift"},
		{"hands": [["bow_short", ""]], "armor": "leather"},
		{"hands": [["bow_short", ""], ["bow_recurve", ""]], "armor": "leather"},
		{"hands": [["bow_recurve", ""]], "armor": "leather"},
		{"hands": [["bow_recurve", ""], ["bow_long", ""]], "armor": "leather"},
	],
	ARCHETYPE_TANK: [
		{"hands": [["club_makeshift", "shield_wood"], ["sword_makeshift", "shield_wood"]],
			"armor": "makeshift"},
		{"hands": [["sword_short", "shield_buckler"]], "armor": "mail"},
		{"hands": [["sword_arming", "shield_kite"]], "armor": "mail"},
		{"hands": [["sword_arming", "shield_kite"], ["sword_short", "shield_tower"]],
			"armor": "plate"},
		{"hands": [["sword_arming", "shield_tower"]], "armor": "plate"},
	],
	ARCHETYPE_MELEE: [
		{"hands": [["branch_heavy", ""], ["sword_makeshift", "dagger_ironwood"]],
			"armor": "makeshift"},
		{"hands": [["sword_short", "dagger_ironwood"], ["sword_makeshift", "dagger_iron"]],
			"armor": "mail"},
		{"hands": [["sword_arming", "dagger_iron"], ["sword_short", "dagger_iron"]],
			"armor": "mail"},
		{"hands": [["sword_great", ""], ["sword_arming", "dagger_iron"]], "armor": "plate"},
		{"hands": [["sword_great", ""], ["sword_arming", "dagger_iron"]], "armor": "plate"},
	],
}

## What a body costs before the gear is weighed: a base and a step per level, so
## the purse's own curve (the stall's `22 + 5 * level`) is one the party can read
## against a body. The tank is dearest - a shield and a mail coat are two pieces
## where an archer carries one - and the gear premium is the rung's own weight on
## top, because a plate-and-greatsword body is not a rags body with a long name.
const PRICE := {
	ARCHETYPE_RANGED: {"base": 120, "step": 9, "gear": 2.2},
	ARCHETYPE_TANK: {"base": 140, "step": 10, "gear": 2.4},
	ARCHETYPE_MELEE: {"base": 135, "step": 10, "gear": 2.4},
}

## The names the board cycles through. Not the town's `WarbandVendor.NAMES`: a
## recruit is not an oath, and a board that sold you "Aldous" twice in one run
## would read as the same man.
const NAMES := [
	"Rook", "Wyst", "Harrow", "Tallow", "Ghent", "Corvin", "Marrow", "Sable",
	"Dune", "Vane", "Holt", "Crane", "Pell", "Roth", "Skade", "Wren",
]


## The level a board prices against: past the cap a hire is a level-50 hire, so
## an endless run cannot price a body into nonsense.
static func level_cap(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL)


## Which rung a level sits in, clamped to the table.
static func rung_for(level: int) -> int:
	return clampi((level_cap(level) - 1) / RUNG_LEVELS, 0, KITS[ARCHETYPE_RANGED].size() - 1)


## What one body costs at this level, in gold.
static func price_for(level: int, archetype: String) -> int:
	var row: Dictionary = PRICE.get(archetype, PRICE[ARCHETYPE_MELEE])
	var depth := float(level_cap(level) - 1)
	var base := float(row.get("base", 120)) + float(row.get("step", 9)) * depth
	# The rung's gear is a premium on the price, and it is the rung's *own*
	# weight: rung 0 costs what a base body costs, rung 4 costs the base plus the
	# whole of `gear`.
	var premium := float(row.get("gear", 2.0)) * float(rung_for(level)) \
		/ float(KITS[ARCHETYPE_RANGED].size() - 1)
	return maxi(1, int(round(base * (1.0 + premium))))


## The armour a rung is sworn in, as five slot ids.
static func armor_for(armor_set: String) -> Dictionary:
	var index := ArmorData.SET_IDS.find(armor_set)
	if index < 0:
		index = ArmorData.SET_IDS.find("makeshift")
	var out := {}
	for slot in ArmorData.SLOTS:
		out[slot] = ArmorData.item_id(index, slot)
	return out


## The kit one recruit of this archetype is sworn in at this rung: hands and
## armour, as the slot -> item id dictionary `WarbandRoster.create` takes.
static func gear_for(archetype: String, rung: int, rng: RandomNumberGenerator) -> Dictionary:
	var ladder: Array = KITS.get(archetype, KITS[ARCHETYPE_MELEE])
	var kit: Dictionary = ladder[clampi(rung, 0, ladder.size() - 1)]
	var hands: Array = kit.get("hands", [["sword_makeshift", ""]])
	var pair: Array = hands[rng.randi_range(0, hands.size() - 1)]
	var out := armor_for(str(kit.get("armor", "makeshift")))
	out["main"] = str(pair[0]) if pair.size() > 0 else ""
	out["off"] = str(pair[1]) if pair.size() > 1 else ""
	# A two-hander holds the off hand: a kit that named one would otherwise be
	# sworn with a board it cannot raise.
	if Contracts.two_handed_item(State.ITEMS.get(str(out["main"]), {})):
		out["off"] = ""
	return out


## The one item skill an archetype rolls for this kit, or `""` when nothing in
## the catalog fits the hands - a recruit with no skill is still a body, and the
## card says so rather than lying about a skill it cannot fire.
static func skill_for(archetype: String, gear: Dictionary, rng: RandomNumberGenerator) -> String:
	var main: Dictionary = State.ITEMS.get(str(gear.get("main", "")), {})
	var off: Dictionary = State.ITEMS.get(str(gear.get("off", "")), {})
	var families: Array = FAMILIES.get(archetype, [])
	var pool: Array[String] = []
	for definition in AbilityRules.ABILITIES:
		var id := str(definition.get("id", ""))
		if id.is_empty():
			continue
		# 1. A kind a body can aim and land on another body.
		if not str((definition.get("effect", {}) as Dictionary).get("kind", "")) \
				in AbilityRules.AI_KINDS:
			continue
		# A family starter is not a card: the eight starters sit on a bar by the
		# hands that hold them (`AbilityRules.is_automatic`), so a "rolled" starter
		# would be stripped off the recruit's bar and the body would fall back to
		# every skill its kit fits - the one thing this roll exists to stop.
		if AbilityRules.is_automatic(id):
			continue
		# 2. The archetype's own families.
		if not _family_matches(families, definition):
			continue
		# 3. The hands that would fire it.
		if not AbilityRules.fits_gear(definition, main, off):
			continue
		pool.append(id)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


## Whether any of this ability's tags is one the archetype allows. `fits_gear`
## asks the *hands*; this asks the *family*, which is the archetype's trade.
static func _family_matches(families: Array, definition: Dictionary) -> bool:
	for tag in AbilityRules.families_of(definition):
		if families.has(str(tag)):
			return true
	return false


## One row of the board: who, what, and how much.
static func offer(rng: RandomNumberGenerator, level: int, archetype: String,
		merc_name: String = "") -> Dictionary:
	var rung := rung_for(level)
	var gear := gear_for(archetype, rung, rng)
	var skill := skill_for(archetype, gear, rng)
	if merc_name.is_empty():
		merc_name = str(NAMES[rng.randi_range(0, NAMES.size() - 1)])
	var price := price_for(level, archetype)
	var main_name := str(State.ITEMS.get(str(gear.get("main", "")), {}).get("name", "unarmed"))
	var off_name := str(State.ITEMS.get(str(gear.get("off", "")), {}).get("name", ""))
	var armor_set := str((KITS.get(archetype, [{}])[rung] as Dictionary).get("armor", "makeshift"))
	var skill_name := skill_name_of(skill)
	return {
		"kind": "hire",
		"archetype": archetype,
		"archetype_label": str(LABELS.get(archetype, "FIGHTER")),
		"disposition": str(DISPOSITIONS.get(archetype, Contracts.DISPOSITION_MELEE)),
		"name": merc_name,
		"level": level_cap(level),
		"rung": rung,
		"price": price,
		"gear": gear,
		"skill": skill,
		"skill_name": skill_name,
		"armor_set": armor_set,
		"hands": main_name if off_name.is_empty() else "%s + %s" % [main_name, off_name],
		"body": _body_line(BEHAVIOUR.get(archetype, ""), main_name, off_name,
			skill_name, armor_set),
	}


## A whole board: three rows, one of each archetype, in a fresh order. `avoid`
## carries the names already on the books - the town desk's board is the band's
## own roster and three rows that read as three people cannot repeat one of them.
static func offers(rng: RandomNumberGenerator, level: int,
		avoid: Array = []) -> Array[Dictionary]:
	var order: Array = ARCHETYPES.duplicate()
	# A Fisher-Yates on the run's own RNG: the same seed sells the same board.
	for index in range(order.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var held = order[index]
		order[index] = order[other]
		order[other] = held
	var out: Array[Dictionary] = []
	var names: Array = NAMES.duplicate()
	var taken: Dictionary = {}
	for entry in avoid:
		taken[str(entry).to_lower()] = true
	for archetype in order:
		var merc_name := ""
		# Distinct names on one board: three rows that read as three people.
		for attempt in names.size():
			var candidate := str(names[rng.randi_range(0, names.size() - 1)])
			if not taken.has(candidate.to_lower()):
				merc_name = candidate
				taken[candidate.to_lower()] = true
				break
		out.append(offer(rng, level, str(archetype), merc_name))
	return out


## The card's body text: what the body carries and what it will do with it.
static func _body_line(behaviour: String, main_name: String, off_name: String,
		skill_name: String, armor_set: String) -> String:
	var hands := main_name if off_name.is_empty() else "%s + %s" % [main_name, off_name]
	var skill := skill_name if not skill_name.is_empty() else "no skill"
	return "%s · %s · %s\n%s" % [hands, str(armor_set).capitalize(), skill, behaviour]


## The name of a skill id, empty for an id this build does not know.
static func skill_name_of(skill_id: String) -> String:
	if skill_id.is_empty():
		return ""
	return str(AbilityRules.by_id(skill_id).get("name", ""))
