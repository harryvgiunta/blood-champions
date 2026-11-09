extends SceneTree
## Runs the title scene and writes its two doors, then the join form over them.
const OUT := "res://.runtime/capture_title.png"
const JOIN_OUT := "res://.runtime/capture_title_join.png"

func _initialize() -> void:
	var scene: Node = load("res://title.tscn").instantiate()
	root.add_child(scene)
	_run(scene)

func _run(title: Node) -> void:
	await _capture(OUT, "TITLE_CAPTURE_OK", 30)
	title.call("_open_join")
	await _capture(JOIN_OUT, "TITLE_JOIN_OK", 8)
	quit()

func _capture(path: String, marker: String, frames: int) -> void:
	for _i in frames:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(path)
	print(marker, " ", image.get_size())
