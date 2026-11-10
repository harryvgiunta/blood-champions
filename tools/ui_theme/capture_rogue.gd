extends SceneTree
## Boots the real world, stands the party on the first island and writes its
## frames: the Town Hub with the rack and the portal, the rack's page, and the
## island under a live wave. Art-direction verification only - this script
## changes nothing and the files it writes are gitignored.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_rogue.gd --resolution 1440x900

const TOWN_OUT := "res://.runtime/capture_rogue_town.png"
const ISLAND_OUT := "res://.runtime/capture_rogue_island.png"
const PointerGate = preload("res://scripts/pointer_gate.gd")


func _initialize() -> void:
	# The shots frame the aiming HUD; the tool takes no pointer to get it.
	PointerGate.preview_aim = true
	var flow = root.get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.world_start = "town"
		flow.active = false
	var scene: Node = load("res://scenes/warband_world.tscn").instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	for _frame in 90:
		await process_frame
	_capture(TOWN_OUT)
	var town = scene.get("town")
	if town != null:
		# A page owns the pointer for it, so the frame behind it is no aim frame.
		PointerGate.preview_aim = false
		town._open_forge("rack")
		for _frame in 20:
			await process_frame
		_capture("res://.runtime/capture_rogue_rack.png")
		town.forge_panel.close_panel()
		PointerGate.preview_aim = true
	var run = scene.get("roguelite")
	if run != null:
		run.start_run()
		for _frame in 45:
			await process_frame
		run.tick(2.5)
		run.tick(2.5)
		for _frame in 90:
			await process_frame
		_capture(ISLAND_OUT)
		# The other two islands, built and stood on: the cave's dripstone and the
		# pit's colonnade are the two the first island never shows.
		var biomes := ["caves", "arena"]
		for index in biomes.size():
			run.stage_index = index + 1
			run.biome_id = str(biomes[index])
			run._build_stage()
			var body = scene.get("bodies")[0] if scene.get("bodies").size() > 0 else null
			if body != null:
				body.global_position = run.stage.entry_posts(1)[0]
			for _frame in 60:
				await process_frame
			_capture("res://.runtime/capture_rogue_%s.png" % str(biomes[index]))
		# The shop level: no wave, the stall, the rack and the portal to the boss.
		run.wave = 9
		run.level = 8
		run.level_cleared = true
		run._begin_level()
		for _frame in 60:
			await process_frame
		_capture("res://.runtime/capture_rogue_shop.png")
		# The three gates a cleared level stands, framed from the party's side on
		# the wood's neutral light: the grey ring, the black rock and bone, the red
		# flesh and ribs.
		run.stage_index = 0
		run.biome_id = "wilderness"
		# A combat clear, so the three doors carry promise cards rather than the
		# boss's hoard: level 12 stands the gates to level 13.
		run.level = 12
		run.wave = 3
		run.boss_level = false
		run.shop_level = false
		run.market_level = false
		run.active_contract = run._starter_contract()
		run._build_stage()
		run._clear_stage_props()
		run.level_cleared = true
		run._clear_level()
		if scene.get("bodies").size() > 0:
			var viewer = scene.get("bodies")[0]
			# Framed from the middle gate's own lintel, wherever the island put it.
			var gate_at := Vector3.ZERO
			for prop in run._props:
				if is_instance_valid(prop) \
						and str(prop.get_meta("roguelite_prop", "")) == "portal":
					gate_at = (prop as Node3D).global_position
					break
			viewer.global_position = gate_at + Vector3(0.0, 0.0, 6.6)
			viewer.rotation.y = 0.0
		for _frame in 45:
			await process_frame
		_capture("res://.runtime/capture_rogue_gates.png")
		# The island's furniture and the draft window: clear the last island,
		# walk the body to the chest and open the board it offers.
		run.level_cleared = true
		run._clear_level()
		for _frame in 30:
			await process_frame
		var chest = null
		for prop in run._props:
			if is_instance_valid(prop) and str(prop.get_meta("roguelite_prop", "")) == "chest":
				chest = prop
				break
		if chest != null and scene.get("bodies").size() > 0:
			var player_body = scene.get("bodies")[0]
			player_body.global_position = chest.global_position + Vector3(0.0, 0.0, 2.6)
			run._open_chest(int(chest.get_meta("serial")), player_body)
			for _frame in 20:
				await process_frame
			_capture("res://.runtime/capture_rogue_draft.png")
	quit()


func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		print("ROGUE_CAPTURE_MISS ", path)
		return
	image.save_png(path)
	print("ROGUE_CAPTURE_OK ", path, " ", image.get_size())
