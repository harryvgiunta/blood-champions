class_name AbilityIndex
extends RefCounted
## One query over the two catalogs that use the word "ability".
##
## They are different kinds and stay different kinds:
##
##   active    the skills a body fires from the hotbar (`ability_rules.gd`):
##             Barrage, Fireball, Dash, the shields, the wards, and the free
##             family starters (Snap Shot, Quick Cut, Heavy Swing, Quick Stab,
##             Shield Shove, Focus, Charge). 36 rows.
##   upgrade   the run's ability-upgrade rows (`mod_catalog.gd`, family
##             `ability`): the throw/roll/guard/parry verb upgrades plus the
##             weapon-family rows (Spiral Shot, Whirlwind, Guardian's Instinct...).
##             The verb rows carry a `verb`; the family rows carry `tags`.
##
## The index is a derived view, never a third catalog: every field comes from
## the owning definition or pool row. It exists so the game, the docs and the
## tests can answer "what is this thing?" without treating a passive upgrade as
## a key or a skill as a card. `entries()` is the merged list; `find()` is the
## single-id lookup.

const AbilityRules = preload("res://scripts/ability_rules.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")

const KIND_ACTIVE := "active"
const KIND_UPGRADE := "upgrade"


## The 36 skills the Ability Book lists, in catalog order.
static func active_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in AbilityRules.catalog_ids():
		var definition := AbilityRules.by_id(id)
		var automatic := AbilityRules.is_automatic(id)
		out.append({
			"id": id,
			"name": str(definition.get("name", id)),
			"kind": KIND_ACTIVE,
			"family": AbilityRules.type_of(definition),
			"families": AbilityRules.families_of(definition),
			"category": AbilityRules.type_of(definition),
			"cost": 0 if automatic else AbilityRules.unlock_cost_of(id),
			"automatic": automatic,
			"starter": AbilityRules.is_starter(id),
			"ready": true,
			"description": str(definition.get("description", "")),
		})
	return out


## Every ability-family row, in pool order: the 19 verb rows and the 40 live
## weapon-family rows, each with its `verb` or `tags`.
static func upgrade_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in Mods.all():
		var id := str(row.id)
		if Mods.family_of(id) != Mods.FAMILY_ABILITY:
			continue
		var verb := Mods.verb_of(id)
		var tags := Mods.tags_of(id)
		out.append({
			"id": id,
			"name": Mods.name_of(id),
			"kind": KIND_UPGRADE,
			"family": Mods.FAMILY_ABILITY,
			"families": [Mods.FAMILY_ABILITY],
			"verb": verb,
			"tags": tags,
			"category": verb if not verb.is_empty() else str(tags[0]) if not tags.is_empty() else "ability",
			"rarity": Mods.rarity_of(id),
			"max_stacks": Mods.max_stacks(id),
			"cost": 0,
			"automatic": false,
			"starter": false,
			"ready": Mods.ready_of(id),
			"description": str(Mods.get_mod(id).get("description", "")),
		})
	return out


## The merged list: every active skill, then every ability upgrade. Ids never
## collide across the two kinds; the test pins that.
static func entries() -> Array[Dictionary]:
	var out := active_entries()
	out.append_array(upgrade_entries())
	return out


static func counts() -> Dictionary:
	return {
		"active": active_entries().size(),
		"upgrade": upgrade_entries().size(),
		"total": entries().size(),
	}


## One entry by id, whichever kind owns it. Empty for anything neither catalog
## knows.
static func find(id: String) -> Dictionary:
	for entry in entries():
		if str(entry.id) == id:
			return entry
	return {}


## The verb upgrades grouped by verb, in display order. Each value is the rows
## that write that verb, so a doc, a card or a test can say "the throw upgrades"
## without re-reading the pool.
static func upgrades_by_verb() -> Dictionary:
	var out := {}
	for verb in Mods.VERB_ORDER:
		out[verb] = []
	for entry in upgrade_entries():
		var verb := str(entry.get("verb", ""))
		if out.has(verb):
			(out[verb] as Array).append(entry)
	return out
