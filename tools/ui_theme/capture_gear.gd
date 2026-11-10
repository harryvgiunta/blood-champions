extends SceneTree
## Opens the character screen over the running world and writes one frame per
## page: GEAR, INVENTORY and SKILLS.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_gear.gd --resolution 1440x900
##
## Writes `media/concept/game_gear.png`, `game_inventory.png` and
## `game_skills.png`. Art-direction verification only.

const OUT := {
	"gear": "res://media/concept/game_gear.png",
	"inventory": "res://media/concept/game_inventory.png",
	"skills": "res://media/concept/game_skills.png",
	"upgrades": "res://media/concept/game_upgrades.png",
	"menu": "res://media/concept/game_gear_slot.png",
}
const Doll = preload("res://scripts/warband/warband_paperdoll.gd")

var _doll = null

func _initialize() -> void:
	var flow = root.get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.world_start = "camp"
		flow.active = true
	var scene: Node = load("res://scenes/warband_world.tscn").instantiate()
	root.add_child(scene)
	_run()

func _run() -> void:
	for _i in 60:
		await process_frame
	var card = root.find_child("TutorialCard", true, false)
	if card != null and card.has_method("close"):
		card.close()
	var warband = root.get_node_or_null("/root/Warband")
	var first := -1
	if warband != null:
		var ids: Array = warband.roster.ids()
		if not ids.is_empty():
			first = int(ids[0])
		# A page with content: a spare of each kind the grid draws and the two
		# medicines the gear page counts.
		for item_id in ["sword_short", "shield_wood", "armor_leather_head",
				"armor_leather_chest", "bow_short", "focus_skull"]:
			warband.stash.add(item_id, 1)
		warband.add_supply("potion", 3)
		warband.add_supply("bandage", 5)
		# A player who has opened a few skills and put one on a key: the review list
		# and the assignment are what the page is for, so the still shows them.
		var meta = root.get_node_or_null("/root/Roguelite")
		if meta != null and first > 0:
			meta.award_keys(20)
			for ability_id in ["barrage", "dash", "energy_shield", "focus"]:
				meta.unlock_ability(ability_id)
			warband.set_hotbar_slot(first, 2, "dash")
	_doll = Doll.new()
	_doll.name = "CaptureGear"
	root.add_child(_doll)
	_doll.configure(null)
	_doll.open(first)
	for page in ["gear", "inventory", "skills", "upgrades"]:
		_doll.open_page(page)
		if page == "inventory" and not _doll.inventory_rows.is_empty():
			# The box the player gets for pointing at a tile.
			_doll._hover_item(str(_doll.inventory_rows[0]["item_id"]), "")
		# Two frames for the page's own layout, then one for the still it writes.
		for _i in 3:
			await process_frame
		_write(str(OUT[page]), page)
	# The one press the gear page is built around: a worn slot's alternatives.
	_doll.open_page("gear")
	_doll.hide_hover()
	_doll.open_slot_menu("main")
	for _i in 3:
		await process_frame
	_write(str(OUT["menu"]), "menu")
	quit()


func _write(path: String, tag: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("GEAR_CAPTURE_OK ", tag, " ", image.get_size())
	return
