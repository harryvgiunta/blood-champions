class_name WarbandGearDrop
extends RefCounted
## What a body lets go of when it goes down, and where it lands.
##
## One rule for both sides of a fight: a body that hits the floor drops what it
## was *holding*. Worn gear stays worn - a shield is strapped on, but it is still
## in the hand - so the two hand slots empty, the roster is the ground truth for
## what a body wears, and the piece is put in the world rather than booked into
## the shared stash. A dropped piece is on the floor, not owned by the warband: it
## has to be picked back up with `K`, or walked to by a squadmate.
##
## Enemies answer the same question through `take_weapon_item()`, which strips the
## model's own hand at the same time, so what a player sees is what a blade on the
## dirt is worth.

## The hand slots, in the order a body lets go of them: the off hand first, so a
## blade is the last thing to leave.
const DROP_SLOTS := ["off", "main"]
## Everything the roster can dress a body in, in the order a corpse gives it up:
## the steel first, then the worn plates. A hireling's death lets go of all of it
## (`strip_kit`), so the reap that erases his name has nothing left to book back
## into the shared stash and the kit stays the grave's.
const KIT_SLOTS := ["off", "main", "head", "chest", "hands", "legs", "feet"]
## How far off the body a dropped piece lands. Far enough not to be inside the
## capsule the corpse leaves behind, close enough to read as "beside it".
const DROP_OFFSET := 0.55

## Empty a mercenary's hands and answer the pieces that fell, off hand first.
## Nothing is added to the stash here: the caller puts each piece in the world,
## and the warband's worth drops by exactly what is lying in the dirt.
static func strip_hands(warband, merc_id: int) -> Array[String]:
	return _strip(warband, merc_id, DROP_SLOTS)

## Empty everything a mercenary is dressed in and answer the pieces. The fall's
## rule is `strip_hands` (a shield is still strapped on); this is the death's, for
## a body whose loss is the band's: the worn plates leave the record with the
## steel, so nothing the man was carrying survives him on the books.
static func strip_kit(warband, merc_id: int) -> Array[String]:
	return _strip(warband, merc_id, KIT_SLOTS)

static func _strip(warband, merc_id: int, slots: Array) -> Array[String]:
	var out: Array[String] = []
	if warband == null or not is_instance_valid(warband) or merc_id <= 0:
		return out
	for slot in slots:
		var item_id: String = warband.roster.unequip(merc_id, slot)
		if not item_id.is_empty():
			out.append(item_id)
	return out

## The catalog pieces in a mob's hands, taken out of it - the off hand first, the
## way a warband body lets go of its own (`strip_hands`). Answers "" entries for a
## body with empty hands, for one that is already gone, and for a kind of body that
## does not carry catalog gear at all.
static func strip_enemy_hand(enemy, off: bool) -> String:
	if not is_instance_valid(enemy):
		return ""
	var verb := "take_off_item" if off else "take_weapon_item"
	if not enemy.has_method(verb):
		return ""
	return str(enemy.call(verb))

## Where a dropped piece lands: in front of the body and on the body's own
## ground, so the drop's origin is the floor the corpse lies on.
static func drop_point(body: Vector3, facing: Vector3, offset: float = DROP_OFFSET) -> Vector3:
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() <= 0.0001:
		return body
	flat = flat.normalized() * offset
	return Vector3(body.x + flat.x, body.y, body.z + flat.z)

## A body's own forward (-Z in Godot), flattened, or ZERO for a body with no
## transform.
static func forward_of(body) -> Vector3:
	if not (body is Node3D):
		return Vector3.ZERO
	return -(body as Node3D).global_transform.basis.z
