extends Node
## Shift+Space requests one directional roll per airborne cycle; Space only jumps.
const DURATION := 0.68
const SPEED := 8.5
## The roll's own travel: its speed across its whole clock. Speed rows move the
## speed, never the duration - the rig animates the roll on `DURATION`, and a
## roll whose clock moved would play its pose out before the body landed.
const TRAVEL := SPEED * DURATION
var active := false
var direction := Vector3.FORWARD
var progress := 0.0
var takeoff_pending := false
## Per-instance tuning: a run's `roll_distance` and `roll_speed` land here, and a
## campaign body rolls on the constant above.
var speed := SPEED
var _used_in_air := false

func press_jump(movement: Vector3, facing: Vector3, grounded: bool, roll_requested: bool) -> bool:
	if active:
		return false
	if roll_requested and not _used_in_air:
		direction = Vector3(movement.x,0,movement.z)
		if direction.length_squared() < 0.01:
			direction = Vector3(facing.x,0,facing.z)
		direction = direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD
		active = true
		progress = 0.0
		takeoff_pending = true
		_used_in_air = true
		return false
	return grounded and not roll_requested

func advance(delta: float, grounded: bool) -> void:
	if active:
		progress = minf(1.0,progress+delta/DURATION)
		if progress >= 1.0:
			active = false
	elif grounded:
		_used_in_air = false

## The frame's committed velocity, at whatever speed the run has tuned in.
func velocity() -> Vector3:
	if not active:
		return Vector3.ZERO
	return Vector3(direction.x * speed,0.0,direction.z * speed)

func reset() -> void:
	active = false
	progress = 0.0
	takeoff_pending = false
	_used_in_air = false
