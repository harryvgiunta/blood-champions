extends SceneTree
## Renders the arena's chambers: the rooms of the Weeping Hollow the arena draws
## its fights from (`scripts/warband/arena_cave.gd`), each built on its own and
## looked at from inside - eye level across the fight, the room from over it, and
## a way out of it - and then one real bout through the game's own camera.
## Art-direction verification only; the frames it writes are gitignored.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_arena.gd --resolution 1440x900
##
## A room that reads only from above is a room with no eye-level light in it, so
## every room gets the eye's own frame.

const ArenaCaveScript = preload("res://scripts/warband/arena_cave.gd")
const PointerGate = preload("res://scripts/pointer_gate.gd")

## A room of each look the plan dresses: warm limestone, wet basalt, bleached bone,
## candles, flowstone, red rock, and the inner ring's own chambers.
const ROOMS := ["den", "gallery", "ossuary", "chapel", "mere", "garden", "lair", "ring_s"]
const OUT := "res://.runtime/capture_arena_%s_%s.png"


func _initialize() -> void:
	# The bout shot frames the aiming HUD; the tool takes no pointer to get it.
	PointerGate.preview_aim = true
	var flow = root.get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.world_start = "town"
		flow.active = false
	var scene: Node = load("res://scenes/warband_world.tscn").instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	for _frame in 120:
		await process_frame
	var chrome: Array = []
	for node in scene.find_children("*", "CanvasLayer", true, false):
		chrome.append([node, (node as CanvasLayer).visible])
		(node as CanvasLayer).visible = false
	# The campaign's own lights reach into the rock as well as out of it.
	for node in scene.find_children("*", "DirectionalLight3D", true, false):
		(node as DirectionalLight3D).visible = false
	var camera := Camera3D.new()
	camera.name = "ArenaCaptureCamera"
	camera.fov = 78.0
	camera.far = 400.0
	scene.add_child(camera)
	for room_id in ROOMS:
		var cave = ArenaCaveScript.new()
		cave.name = "Capture_%s" % room_id
		scene.add_child(cave)
		cave.build(str(room_id))
		camera.environment = cave.environment
		var box: AABB = cave.bounds()
		var seats: Dictionary = cave.seat(3, 3)
		var party_mid := _mid(seats["party"])
		var foe_mid := _mid(seats["foes"])
		# Eye level on the party's own line, looking across at the foes.
		await _shoot(camera, seats["party"][1] + Vector3(0.0, 1.62, 0.0),
			seats["foes"][1] + Vector3(0.0, 1.10, 0.0), OUT % [room_id, "eye"])
		# The room from over the fight: the roof, the dripstone, the walls.
		var span := foe_mid - party_mid
		span.y = 0.0
		var back := span.normalized() * span.length() * 0.22
		await _shoot(camera, party_mid - back + Vector3(0.0, box.size.y * 0.62, 0.0),
			(party_mid + foe_mid) * 0.5 + Vector3(0.0, -1.2, 0.0), OUT % [room_id, "air"])
		# A way out: the rock that shut it, with the rubble that came down at its
		# foot. The eye stands on the room's own ground, not on the doorway's: the
		# floor of a cave falls away from the mouth, and a camera set at the lower
		# end's height is a camera buried in the ground.
		var ways: Array = cave.doorways()
		if not ways.is_empty():
			var way: Dictionary = ways[0]
			var at: Vector3 = way["at"]
			var inward := Vector3(box.position.x + box.size.x * 0.5, 0.0, box.position.z
				+ box.size.z * 0.5) - Vector3(at.x, 0.0, at.z)
			var stand: Vector3 = at - inward.normalized() * 8.0
			stand.y = maxf(at.y, party_mid.y) + 1.75
			await _shoot(camera, stand, at + Vector3(0.0, 1.5, 0.0), OUT % [room_id, "way"])
		cave.queue_free()
		for _frame in 2:
			await process_frame
	# And one real bout, through the square's own gate and the game's own camera:
	# the service that opens the board, the board's own press, the fight.
	for entry in chrome:
		var layer = entry[0]
		if is_instance_valid(layer):
			(layer as CanvasLayer).visible = bool(entry[1])
	camera.queue_free()
	var town = scene.get("town")
	var arena = scene.get("arena")
	if town != null and arena != null:
		var gate: Vector3 = town.service_point("arena")
		town.interact_at(1, gate)
		for _frame in 10:
			await process_frame
		_capture("res://.runtime/capture_arena_board.png")
		var board = town.get("arena_menu")
		if board != null:
			board.select_tier("hard")
			board.fight_requested.emit("hard")
			for _frame in 90:
				await process_frame
			_capture("res://.runtime/capture_arena_fight.png")
			print("ARENA_CAPTURE room=", arena.room_id, " label=", arena.room_label(),
				" active=", arena.active)
	print("ARENA_CAPTURE_OK")
	quit()


## Frame one shot and write it: the camera is set twice, because the world's own
## possession camera re-claims the viewport on the frame after a body is seated.
func _shoot(camera: Camera3D, eye: Vector3, look: Vector3, path: String) -> void:
	camera.current = true
	camera.global_position = eye
	camera.look_at(look, Vector3.UP)
	camera.current = true
	for _frame in 6:
		await process_frame
	camera.current = true
	_capture(path)


func _mid(posts: Array) -> Vector3:
	var sum := Vector3.ZERO
	for post in posts:
		sum += post
	return sum / float(maxi(1, posts.size()))


func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("ARENA_CAPTURE ", path, " ", image.get_size())
