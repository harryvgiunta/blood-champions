extends SceneTree
## A held guard must look like a block: the piece on the diagonal across the
## front of the body, out in front of the sternum, and never through its owner.
##
## The two ways this pose broke were both structural. A one-handed blade laid
## level down the guard line reads as a thrust pointed at the attacker, and a
## staff - 1.75 m of shaft gripped below its middle - laid level from the fist
## sends a metre of butt straight through the owner's chest. So both rules are
## measured on the rendered body, not on a wrist target: every kit is skinned and
## the whole weapon segment is tested against the actual torso triangles while the
## guard loop plays, and the blade's own line has to be a diagonal in the body's
## frame with the hilt out in front of the sternum - at a level eye and at a
## steep one, because the eye tilts the guard and must not flatten it.

const Archer = preload("res://scripts/archer.gd")

## Weapon, catalog index, staff. The two-handers, the shiv and both staves are
## here because each is a different solve.
const KITS := [
	["sword", 0, false],   # shortsword
	["sword", 1, false],   # arming sword
	["sword", 2, false],   # greatsword, two hands
	["sword", 3, false],   # club
	["sword", 6, false],   # iron javelin, two hands
	["dagger", 0, false],
	["sword", 0, true],    # ember staff
	["sword", 1, true],    # bone staff
]
## The eye at rest, then at each end of `Combat`'s guard pitch. The flat line is
## `Vector3.FORWARD`; the steep ones are near the zenith and the nadir.
const LOOKS := [Vector3(0.0,0.0,-1.0), Vector3(0.0,1.0,-0.12), Vector3(0.0,-1.0,-0.12)]
const FRAMES := 12
const FRAME_SECONDS := 0.04
## The blade's line as a block: a real diagonal in the body's own frame, at every
## eye angle - not straight up, not straight out, not flat.
const MIN_UP := 0.35
const MAX_UP := 0.98
const MIN_ACROSS := 0.30
## The fist in front of the sternum, so the steel is between the body and the
## attacker rather than across the ribs.
const MIN_AHEAD := 0.15
## How close the weapon may come to the body before it reads as embedded in it.
const MIN_CLEAR := 0.10

var checks := 0
var failures := 0
var rig
var body: MeshInstance3D
var vertices: PackedVector3Array
var indices: PackedInt32Array
var weights: PackedFloat32Array
var joints: PackedInt32Array
var bind_bones := PackedInt32Array()
var binds: Array[Transform3D] = []
var transforms: Array[Transform3D] = []
var influences := 4
var skinned := PackedVector3Array()

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("GUARD_POSE_FAIL  ", message)

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	rig = Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	body = rig.find_child("Male_Ranger_Body",true,false) as MeshInstance3D
	var arrays := body.mesh.surface_get_arrays(0)
	vertices = arrays[Mesh.ARRAY_VERTEX]
	indices = arrays[Mesh.ARRAY_INDEX]
	weights = arrays[Mesh.ARRAY_WEIGHTS]
	joints = arrays[Mesh.ARRAY_BONES]
	influences = joints.size()/vertices.size()
	skinned.resize(vertices.size())
	for index in body.skin.get_bind_count():
		bind_bones.append(rig.skeleton.find_bone(body.skin.get_bind_name(index)))
		binds.append(body.skin.get_bind_pose(index))
		transforms.append(Transform3D.IDENTITY)
	for kit in KITS:
		dress(str(kit[0]),int(kit[1]),bool(kit[2]))
		for look in LOOKS:
			check_guard(str(kit[0]),int(kit[1]),bool(kit[2]),look)
	rig.set_staff(false,0)
	holder.queue_free()
	await process_frame
	print("GUARD_POSE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func dress(weapon: String, index: int, staff: bool) -> void:
	rig.set_staff(false,0)
	rig.set_weapon(weapon)
	rig.set_sword(index)
	if staff:
		rig.set_staff(index,true)
	rig.aim_at(Vector3(0,1.6,-30))
	rig.set_locomotion(Vector3.ZERO,true)
	rig.advance_animation(0.2)

func check_guard(weapon: String, index: int, staff: bool, look: Vector3) -> void:
	var tilt := int(round(rad_to_deg(asin(clampf(look.normalized().y,-1.0,1.0)))))
	var label := "%s %d%s at %d deg" % [weapon,index," staff" if staff else "",tilt]
	rig.set_blocking(true,look.normalized())
	rig.advance_animation(0.2)
	var forward: Vector3 = -rig.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var closest := INF
	var embedded := 0
	var flattest := 1.0
	for frame in FRAMES:
		rig.advance_animation(FRAME_SECONDS)
		skin_body()
		var base: Vector3 = rig.get_blade_base("right")
		var tip: Vector3 = rig.get_blade_tip("right")
		var direction := (tip-base).normalized()
		check(direction.y > MIN_UP and direction.y < MAX_UP,
			"%s holds its guard on the diagonal, not straight up or level (%.2f up)"
				% [label,direction.y])
		check(absf(direction.dot(right)) > MIN_ACROSS,
			"%s holds the piece across the body's own front (%.2f across)"
				% [label,absf(direction.dot(right))])
		check(held_ahead(staff,forward) > MIN_AHEAD,
			"%s holds the guard out in front of the sternum (%.2f m ahead)"
				% [label,held_ahead(staff,forward)])
		# The flat of a blade faces the blow; a shaft is round.
		if not staff:
			var held: Node3D = rig.active_dagger if weapon == "dagger" else rig.active_sword
			if held != null and is_instance_valid(held):
				flattest = minf(flattest,held.global_basis.y.dot(forward))
		embedded += weapon_embedded(base,tip)
		closest = minf(closest,weapon_clearance(base,tip))
	check(embedded == 0,
		"%s never passes its own weapon through its own body (%d embedded frames)"
			% [label,embedded])
	check(closest > MIN_CLEAR,
		"%s keeps the held piece clear of the body (%.3f m)" % [label,closest])
	if not staff:
		check(flattest > 0.35,
			"%s turns the flat of the blade to the blow (%.2f)" % [label,flattest])
	rig.set_blocking(false)
	rig.advance_animation(0.3)

## What has to be out in front: a blade is measured at its hilt, but a staff is
## gripped below its middle, so its butt end legitimately trails behind the body -
## the hands are what hold it out there.
func held_ahead(staff: bool, forward: Vector3) -> float:
	if not staff:
		return (rig.get_blade_base("right")-rig.global_position).dot(forward)
	var joints: Dictionary = rig.get_joint_positions()
	return minf((joints.right_wrist-rig.global_position).dot(forward),
		(joints.left_wrist-rig.global_position).dot(forward))

## One frame's weapon against the skinned body: an axis-exact crossing plus four
## offsets the width of a shaft, so a piece held through a rib cannot slip between
## two triangles and pass.
func weapon_embedded(base: Vector3, tip: Vector3) -> int:
	var along := tip-base
	var across := along.cross(Vector3.UP).normalized()
	var around := along.cross(across).normalized()
	for displacement in [Vector3.ZERO,across*0.03,-across*0.03,around*0.03,-around*0.03]:
		for triangle in range(0,indices.size(),3):
			if Geometry3D.segment_intersects_triangle(base+displacement,tip+displacement,
					skinned[indices[triangle]],skinned[indices[triangle+1]],
					skinned[indices[triangle+2]]) != null:
				return 1
	return 0

## The nearest the piece comes to any skinned vertex along its whole length.
func weapon_clearance(base: Vector3, tip: Vector3) -> float:
	var closest := INF
	for step in 12:
		var point: Vector3 = base.lerp(tip,float(step)/11.0)
		for index in skinned.size():
			closest = minf(closest,point.distance_to(skinned[index]))
	return closest

func skin_body() -> void:
	for index in binds.size():
		transforms[index] = rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(bind_bones[index])*binds[index]
	for index in vertices.size():
		var point := Vector3.ZERO
		for influence in influences:
			var slot := index*influences+influence
			if weights[slot] > 0.0:
				point += (transforms[joints[slot]]*vertices[index])*weights[slot]
		skinned[index] = point
