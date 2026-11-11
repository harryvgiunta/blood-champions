extends "res://scripts/warband/cage_watcher.gd"
## The Hollow's caster: one of the wood's watchers carrying a single fire rite,
## rolled when the body is filed into a wave.
##
## It is a watcher first - the same creature skin, the same sight, pursuit,
## separation and corpse - with two changes:
##
##   * its `_fire_kit()` is one spell, not the goatmen's three. The pool is
##     `SPELL_POOL`: the camp's fireball, its breath, its ember rain and the
##     Ember Staff's Fire Ray, so a party that meets a caster at level five can
##     meet the same ray the player can unlock.
##   * it keeps a makeshift club in hand - it is still a watcher and must swing
##     like one at contact range - while the fire gathers at its chest and comes
##     out of the free hand. No staff is needed for the rite.
##
## The cast itself is `devil_mob.gd`'s: a windup the eye can answer, then the
## spell lands on the point and down the line it was loosed on. The beam is the
## shared `fire_ray.gd` node, frozen to that line, and its damage is the watcher's
## own `DemonFire.line_scorch` - every party body in the ray, not just the one the
## caster chose to face.
##
## A run picks the body's spell on the host and carries it in the wave spec, so
## every peer dresses the same caster with the same rite. A body spawned outside
## a wave (a test, a hand-placed scene) falls back to `spell_index_for`, a hash of
## its ground position and species, which is deterministic on every machine.

## The rites a caster may be born with, shared with the casting archers:
## `fire_ray` is the player's own staff spell; the other three are the Hollow's
## older fire.
const SPELL_POOL := DemonFireScript.RITE_POOL
## The camp's family, beside the demons' 93 (`DemonFire.DAMAGE_SOURCE`).
const WATCHER_DAMAGE_SOURCE := 90

## The spell this body was filed with. Empty until `_fire_kit` runs.
var assigned_spell := ""


func _ready() -> void:
	super()
	profile["display"] = "Hollow caster"


## One rite, chosen from where the body stands when no wave named it. The wave
## itself writes the pick into the spec (`set_caster_spell`), because the body is
## built on every peer and the pick must be the same on all of them.
func _fire_kit() -> Array[String]:
	if assigned_spell.is_empty():
		assigned_spell = SPELL_POOL[spell_index_for(global_position, mob_id)]
	var out: Array[String] = []
	out.append(assigned_spell)
	return out


## The wave's word on which rite this body carries. Called after `_ready` by the
## spawner on the host and the replica, so the AI's kit and its clock are both the
## spec's. An unknown id is refused rather than turning a caster into a melee body.
func set_caster_spell(spell_id: String) -> void:
	if not SPELL_POOL.has(spell_id):
		return
	assigned_spell = spell_id
	if is_node_ready():
		set_fire_spell(spell_id)


## The rite this body carries, "" before the kit is assigned.
func caster_spell() -> String:
	return assigned_spell


## A watcher's fire is the camp's, not the goatmen's.
func fire_damage_source() -> int:
	return WATCHER_DAMAGE_SOURCE


## The deterministic fallback pick: position and species, both of which a peer
## has before it enters the tree, so a hand-placed caster does not differ between
## machines either.
static func spell_index_for(at: Vector3, species: String) -> int:
	var seed_value := int(round(at.x * 13.0)) + int(round(at.z * 7.0)) \
		+ absi(str(species).hash())
	return absi(seed_value) % SPELL_POOL.size()


## The body a caster is drawn as: the same creature, in a colder violet, with a
## makeshift club in hand. The club is what the body swings when the party closes
## the distance; the rite comes from the free hand and the chest.
func _pick_variant() -> Dictionary:
	var out: Dictionary = super._pick_variant()
	out["name"] = "Hollow Caster"
	out["tint"] = Color(1.12, 1.00, 1.35)
	out["scale"] = 0.98
	out["main"] = "club_makeshift"
	out["swing"] = SWING_OVERHEAD
	out["armor"] = "makeshift"
	out["pieces"] = ["chest", "head"]
	out["guard"] = 0.30
	out["crouch"] = false
	return out


## The party a caster's fire can burn: the quarry it faces plus every other living
## body of the band. A beam is a line through the field, not a duel - the watcher
## still chooses whom to cast at, but the fire takes whoever is standing in it.
func fire_targets() -> Array:
	return _spell_candidates()
