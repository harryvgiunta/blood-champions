class_name MobHealthBars
extends CanvasLayer
## One thin bar over every hostile that has actually been hurt.
##
## The whole thing is a single `Control` and one `_draw()`: no node per mob, no
## Label3D atlas, no texture. A bar is two `draw_rect` calls and one small string,
## so a dozen wounded bodies inside the camera cost a dozen rectangles a frame and
## a run whose mobs are whole costs nothing at all - a body at its full pool is
## never drawn, and neither is one behind the camera, past the range or off screen.
##
## It reads the director's living hostiles and each one's own `health` /
## `max_health`, which is the same pair every damage number is measured against,
## so the plate cannot disagree with the fight.

## Under the run's own plate (layer 7) and over the world.
const LAYER := 6
## How far a bar is drawn at all. Past this the body is a few pixels and the
## number would be unreadable anyway.
const MAX_DISTANCE := 70.0
const BAR_WIDTH := 34.0
const BAR_HEIGHT := 3.0
## The bar floats this far over the body's own chest point.
const HEAD_LIFT := 0.46
const FONT_SIZE := 11

const BACK := Color(0.03, 0.02, 0.02, 0.72)
const FRAME := Color(0.0, 0.0, 0.0, 0.55)
const FILL := Color(0.86, 0.26, 0.20, 0.95)
const ELITE := Color(1.0, 0.72, 0.28, 0.95)
const INK := Color(0.95, 0.91, 0.82, 0.96)
const OUTLINE := Color(0.02, 0.02, 0.03, 0.92)

var world = null
var director = null
var _canvas: Control
var _font: Font


func setup(world_node: Node3D, director_node) -> void:
	world = world_node
	director = director_node
	layer = LAYER
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.name = "HostileBars"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_bars)
	add_child(_canvas)


func _process(_delta: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _draw_bars() -> void:
	if director == null or not is_instance_valid(director) or not bool(director.is_running()):
		return
	if _panels_open():
		return
	var camera := _camera()
	if camera == null:
		return
	var screen := _canvas.get_viewport_rect().size
	for mob in director.live_mobs():
		var pair := _health_pair(mob)
		if pair.y <= 0.0 or pair.x >= pair.y:
			continue
		var head := _head_point(mob)
		if camera.is_position_behind(head):
			continue
		if camera.global_position.distance_squared_to(head) > MAX_DISTANCE * MAX_DISTANCE:
			continue
		var at := camera.unproject_position(head)
		if at.x < -BAR_WIDTH or at.y < 0.0 or at.x > screen.x + BAR_WIDTH or at.y > screen.y:
			continue
		_draw_one(at, pair, _elite(mob))


func _draw_one(at: Vector2, pair: Vector2, elite: bool) -> void:
	var left := at.x - BAR_WIDTH * 0.5
	var top := at.y
	_canvas.draw_rect(Rect2(left - 1.0, top - 1.0, BAR_WIDTH + 2.0, BAR_HEIGHT + 2.0), FRAME)
	_canvas.draw_rect(Rect2(left, top, BAR_WIDTH, BAR_HEIGHT), BACK)
	var share := clampf(pair.x / pair.y, 0.0, 1.0)
	_canvas.draw_rect(Rect2(left, top, BAR_WIDTH * share, BAR_HEIGHT),
		ELITE if elite else FILL)
	# The numbers sit over the bar's own left edge, small enough to read at ten
	# paces and gone at seventy: `health/max` is the whole readout.
	var text := "%d/%d" % [int(ceil(pair.x)), int(ceil(pair.y))]
	var baseline := Vector2(at.x, top - 3.0)
	_canvas.draw_string_outline(_font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER,
		BAR_WIDTH, FONT_SIZE, 3, OUTLINE)
	_canvas.draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER,
		BAR_WIDTH, FONT_SIZE, INK)


## A body's pool as it stands. A mob of a family this plate does not know answers
## zero and is never drawn, instead of being guessed at.
func _health_pair(mob) -> Vector2:
	if mob == null or not is_instance_valid(mob):
		return Vector2.ZERO
	if mob.get("alive") == false:
		return Vector2.ZERO
	var current: Variant = mob.get("health")
	var pool: Variant = mob.get("max_health")
	if typeof(current) != TYPE_FLOAT and typeof(current) != TYPE_INT:
		return Vector2.ZERO
	if typeof(pool) != TYPE_FLOAT and typeof(pool) != TYPE_INT:
		return Vector2.ZERO
	return Vector2(maxf(0.0, float(current)), float(pool))


func _head_point(mob) -> Vector3:
	if mob.has_method("get_aim_position"):
		return (mob as Node3D).call("get_aim_position") + Vector3.UP * HEAD_LIFT
	return (mob as Node3D).global_position + Vector3(0.0, 2.2, 0.0)


func _elite(mob) -> bool:
	return mob.get("elite") == true or mob.get("boss") == true


func _panels_open() -> bool:
	var hud = world.get("roguelite_hud") if world != null else null
	if hud != null and hud.has_method("open_panels"):
		return bool(hud.call("open_panels"))
	return false


func _camera() -> Camera3D:
	var viewport := _canvas.get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()
