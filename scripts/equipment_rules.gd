extends RefCounted
## Pure equipment vocabulary for the warband's seven equipment slots: the slot
## list, the category rules and the auto-slot routing. Nothing here touches a
## roster or a stash - the paperdoll and the loot ask what a piece may wear, and
## commit the move itself.
##
## The slots are steel and armour only. There is no neck and no ring: a body's
## growth is the run's upgrades and the skills it carries, so nothing worn has to
## be managed in a slot the fight never reads.

const SLOTS := ["head","chest","hands","legs","feet","main","off"]
const SLOT_LABELS := {
	"head":"Head", "chest":"Chest", "hands":"Hands", "legs":"Legs", "feet":"Boots",
	"main":"Main Hand", "off":"Off-Hand",
}
## Every category the catalog uses. `misc` is carried, never worn: a bandage is a
## dressing. `ammo` is the other carried kind - shafts the quiver counts and a bow
## spends.
const CATEGORIES := ["1h","2h","bow","staff","shield","focus","armor",
	"armor_bundle","misc","ammo"]
const EQUIPPABLE := ["1h","2h","bow","staff","shield","focus","armor"]
const TWO_HANDED := ["2h","bow","staff"]

static func slot_label(slot: String) -> String:
	return str(SLOT_LABELS.get(slot, slot.capitalize()))

static func item_name(item: Dictionary) -> String:
	return str(item.get("name", "Gear"))

static func two_handed(item: Dictionary) -> bool:
	return str(item.get("category", "")) in TWO_HANDED

## The "naked" set is the covering a body is born in, not armour: bare head, an
## old shirt, bare hands, tight shorts and bare feet exist so the rig has a mesh
## in every slot. The arming pass may replace one of these exactly as if the slot
## were empty, which is what lets a band that starts in rags put on real gear.
const BARE_GARMENT_PREFIX := "armor_naked_"

static func bare_garment(item_id: String) -> bool:
	return item_id.begins_with(BARE_GARMENT_PREFIX)

## Whether the item's category may occupy the slot at all.
static func allowed(item: Dictionary, slot: String) -> bool:
	if item.is_empty() or not slot in SLOTS:
		return false
	match str(item.get("category", "")):
		"1h":
			return slot == "main" or slot == "off"
		"2h", "bow", "staff":
			return slot == "main"
		"shield", "focus":
			return slot == "off"
		"armor":
			return slot == str(item.get("slot", ""))
	return false

## The slot a fresh equip would choose: a one-hander to the main hand, an off
## piece to the off hand, armour to its own slot. Nothing else is worn. The worn
## kit is still an argument because a caller's question is "where would this go
## on that body" even when this answer never reads it.
static func auto_slot(item: Dictionary, _equipped: Dictionary) -> String:
	match str(item.get("category", "")):
		"1h", "2h", "bow", "staff":
			return "main"
		"shield", "focus":
			return "off"
		"armor":
			return str(item.get("slot", ""))
	return ""
