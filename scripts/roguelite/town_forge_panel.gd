class_name TownForgePanel
extends Control
## The town's run board in two pages: the Weapon Rack and the Start Run Portal.
##
## Every weapon the armory holds stands on the rack, locked or not. A row is one
## press: a locked piece is opened for its key price and bound to the hand that
## pressed it; an open piece is simply bound. Nothing is rolled - the player picks
## the weapon they want to earn.
##
## The portal page starts the run. The rack stays live during a run's shop level,
## where the same page re-binds the hands the bodies are actually holding.

const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const MetaScript = preload("res://scripts/roguelite/roguelite_meta.gd")

const INK := Color(0.94, 0.88, 0.72)
const MUTED := Color(0.70, 0.64, 0.52)
const BRASS := Color(0.88, 0.74, 0.44)
const GOOD := Color(0.66, 0.88, 0.70)
const BLOOD := Color(0.92, 0.38, 0.30)
const LOCKED := Color(0.52, 0.46, 0.38)

var town = null
var mode := "rack"
var _title: Label
var _subtitle: Label
var _body: VBoxContainer
var _message: Label


func configure(town_node) -> void:
	town = town_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 560)
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -280
	panel.offset_bottom = 280
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.07, 0.062, 0.97)
	style.border_color = BRASS
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", BRASS)
	_title.add_theme_font_size_override("font_size", 28)
	column.add_child(_title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", MUTED)
	_subtitle.add_theme_font_size_override("font_size", 16)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_subtitle)
	var rule := HSeparator.new()
	column.add_child(rule)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 368)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_color", GOOD)
	_message.add_theme_font_size_override("font_size", 16)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	var close := Button.new()
	close.text = "CLOSE  (ESC)"
	close.pressed.connect(close_panel)
	column.add_child(close)


func open(next_mode: String = "rack") -> void:
	mode = next_mode
	visible = true
	_message.text = ""
	_refresh()


func close_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _meta():
	return get_node_or_null("/root/Roguelite")


func _refresh() -> void:
	if not visible:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var meta = _meta()
	if meta == null:
		_title.text = "THE LEDGER IS MISSING"
		return
	match mode:
		"portal":
			_title.text = "THE START RUN PORTAL"
			_subtitle.text = "Endless levels. A shop level stands right before every boss; the boss pays the keys the rack takes."
			_portal_rows(meta)
		_:
			_title.text = "THE WEAPON RACK"
			_subtitle.text = "%d keys. Every weapon is here: press a locked row to open it and take it up." % int(meta.keys)
			_rack_rows(meta)


func _row(text: String, colour: Color, height: float = 26.0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", 17)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, height)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(label)
	return label


func _button(text: String, colour: Color, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("font_color", colour)
	button.add_theme_font_size_override("font_size", 17)
	button.custom_minimum_size = Vector2(0, 42)
	button.disabled = disabled
	button.pressed.connect(callback)
	_body.add_child(button)
	return button


func _rack_rows(meta) -> void:
	var ranged_id: String = meta.loadout_for(MetaScript.RANGED_SLOT)
	var melee_id: String = meta.loadout_for(MetaScript.MELEE_SLOT)
	var ranged_def: Dictionary = Weapons.get_weapon(ranged_id)
	var melee_def: Dictionary = Weapons.get_weapon(melee_id)
	_row("RANGED  ·  %s" % str(ranged_def.get("name", ranged_id)), BRASS, 26)
	_row(str(ranged_def.get("description", "")), MUTED, 34)
	_row("MELEE  ·  %s" % str(melee_def.get("name", melee_id)), BRASS, 26)
	_row(str(melee_def.get("description", "")), MUTED, 34)
	_row("THE RANGED RACK", MUTED, 24)
	for id in Weapons.ids_for_slot(MetaScript.RANGED_SLOT):
		_rack_row(meta, MetaScript.RANGED_SLOT, str(id), ranged_id)
	_row("THE MELEE RACK", MUTED, 24)
	for id in Weapons.ids_for_slot(MetaScript.MELEE_SLOT):
		_rack_row(meta, MetaScript.MELEE_SLOT, str(id), melee_id)


## One piece on the rack: open and equipped, open, or locked with its price. The
## locked rows are buttons too - that is the whole unlock.
func _rack_row(meta, slot: String, weapon_id: String, equipped_id: String) -> void:
	var weapon: Dictionary = Weapons.get_weapon(weapon_id)
	var weapon_name := str(weapon.get("name", weapon_id))
	var archetype := str(weapon.get("archetype", ""))
	var open: bool = bool(meta.is_unlocked(weapon_id))
	if weapon_id == equipped_id:
		_row("  %s  ·  %s   [IN HAND]" % [weapon_name, archetype], GOOD, 30)
		return
	if open:
		_button("  %s  ·  %s" % [weapon_name, archetype], INK,
			_bind.bind(slot, weapon_id))
	else:
		var price: int = int(meta.unlock_cost_of(weapon_id))
		var affordable: bool = int(meta.keys) >= price
		_button("  %s  ·  %s   [LOCKED  ·  %d KEYS]" % [weapon_name, archetype, price],
			BRASS if affordable else LOCKED, _unlock_and_bind.bind(slot, weapon_id))


func _unlock_and_bind(slot: String, weapon_id: String) -> void:
	var meta = _meta()
	if meta == null:
		return
	var result: Dictionary = meta.unlock_weapon(weapon_id)
	_message.text = str(result.get("message", ""))
	_message.add_theme_color_override("font_color",
		GOOD if bool(result.get("ok", false)) else BLOOD)
	if not bool(result.get("ok", false)):
		_refresh()
		return
	_bind(slot, weapon_id)


func _bind(slot: String, weapon_id: String) -> void:
	var meta = _meta()
	if meta == null:
		return
	var result: Dictionary = meta.set_loadout_slot(slot, weapon_id)
	_message.text = str(result.get("message", ""))
	_message.add_theme_color_override("font_color",
		GOOD if bool(result.get("ok", false)) else BLOOD)
	if bool(result.get("ok", false)):
		_apply_to_bodies(slot, weapon_id)
	_refresh()


## The rack's choice has to reach the bodies it was made for: the square's dress,
## or a live run's hands at a shop level.
func _apply_to_bodies(slot: String, weapon_id: String) -> void:
	if town == null:
		return
	var world = town.get("host")
	if world == null:
		return
	var director = world.get("roguelite")
	if director != null and bool(director.is_running()):
		if director.has_method("rebind_hand"):
			director.rebind_hand(director.local_peer(), slot, weapon_id)
		return
	if world.has_method("refresh_town_dress"):
		world.refresh_town_dress()


func _portal_rows(meta) -> void:
	var ranged_def: Dictionary = Weapons.get_weapon(meta.loadout_for(MetaScript.RANGED_SLOT))
	var melee_def: Dictionary = Weapons.get_weapon(meta.loadout_for(MetaScript.MELEE_SLOT))
	_row("CARRYING  ·  %s  |  %s" % [str(ranged_def.get("name", "")),
		str(melee_def.get("name", ""))], INK, 26)
	_row("Every wave is a level. Every tenth level is a boss, and a shop level " +
"stands right before it. The deepest band keeps the record.", MUTED, 44)
	_row("Keys banked: %d  ·  runs fought: %d  ·  best level: %d" % [
		int(meta.keys), int(meta.runs), int(meta.best_level)], MUTED, 24)
	var world = town.get("host") if town != null else null
	var director = world.get("roguelite") if world != null else null
	var busy := director != null and bool(director.is_running())
	_button("STEP INTO THE PORTAL  ·  BEGIN THE RUN", BRASS, _start_run, busy)
	if busy:
		_row("A run is already live.", BLOOD, 24)


func _start_run() -> void:
	var world = town.get("host") if town != null else null
	if world == null:
		return
	var director = world.get("roguelite")
	if director == null:
		return
	var result: Dictionary = director.start_run()
	_message.text = str(result.get("message", ""))
	_message.add_theme_color_override("font_color",
		GOOD if bool(result.get("ok", false)) else BLOOD)
	if bool(result.get("ok", false)):
		close_panel()
