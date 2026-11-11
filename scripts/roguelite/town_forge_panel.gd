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
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilityIndex = preload("res://scripts/roguelite/ability_index.gd")
const State = preload("res://scripts/player_state.gd")

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
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	column.add_child(nav)
	for page in [["rack", "WEAPON RACK"], ["abilities", "ABILITY BOOK"],
			["portal", "START RUN"]]:
		var page_button := Button.new()
		page_button.text = str(page[1])
		page_button.focus_mode = Control.FOCUS_NONE
		page_button.custom_minimum_size = Vector2(0, 28)
		page_button.add_theme_font_size_override("font_size", 14)
		page_button.add_theme_color_override("font_color", MUTED)
		page_button.pressed.connect(open.bind(str(page[0])))
		nav.add_child(page_button)
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
		"abilities":
			_title.text = "THE ABILITY BOOK"
			_subtitle.text = ("Skills are found, not bought: an ABILITY chest pays "
				+ "one. Equip an open skill on a body whose hands fit its family.")
			_ability_rows()
		_:
			_title.text = "THE WEAPON RACK"
			_subtitle.text = "%d keys. Every weapon is here: press a locked row to open it into the stash and wear it." % int(meta.keys)
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


## The pair a body is carrying, read straight out of the inventory: the same
## `Weapons.hand_pair` the run itself uses, so the rack, the character page and
## the island can never name three different weapons.
func _carried(context: Dictionary) -> Dictionary:
	var warband = context.get("warband")
	if warband == null:
		return {"ranged": "", "melee": ""}
	return Weapons.hand_pair(warband.roster, int(context.get("merc", -1)))


func _rack_rows(meta) -> void:
	var context := _ability_context()
	if context.is_empty():
		_row("No body stands on the rack ground.", MUTED, 28)
		return
	var pair := _carried(context)
	var ranged_id := str(pair.get("ranged", ""))
	var melee_id := str(pair.get("melee", ""))
	var ranged_def: Dictionary = Weapons.get_weapon(ranged_id)
	var melee_def: Dictionary = Weapons.get_weapon(melee_id)
	_row("BODY  ·  %s" % str(context["name"]), BRASS, 26)
	_row("RANGED  ·  %s" % str(ranged_def.get("name", "empty hand")), BRASS, 24)
	_row(str(ranged_def.get("description", "")) if not ranged_def.is_empty() \
		else "No bow or staff in this body's kit: the rack hands one over.", MUTED, 30)
	_row("MELEE  ·  %s" % str(melee_def.get("name", "empty hand")), BRASS, 24)
	_row(str(melee_def.get("description", "")) if not melee_def.is_empty() \
		else "No blade in this body's kit: the rack hands one over.", MUTED, 30)
	_row("THE RANGED RACK", MUTED, 24)
	for id in Weapons.ids_for_slot(Weapons.RANGED):
		_rack_row(meta, Weapons.RANGED, str(id), ranged_id)
	_row("THE MELEE RACK", MUTED, 24)
	for id in Weapons.ids_for_slot(Weapons.MELEE):
		_rack_row(meta, Weapons.MELEE, str(id), melee_id)


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


## Opening a piece is two bookings: the player's ledger pays the keys, and the
## warband forges the piece into the shared stash - the inventory is the one place
## a body can then pick it up from.
func _unlock_and_bind(slot: String, weapon_id: String) -> void:
	var meta = _meta()
	if meta == null:
		return
	var result: Dictionary = meta.unlock_weapon(weapon_id)
	if not bool(result.get("ok", false)):
		_say(str(result.get("message", "")), false)
		_refresh()
		return
	_bind(slot, weapon_id)


## Wear the piece in the hand the run carries it in. In a run that is the run
## director's call - the island's pair is re-read out of the kit and the rig is
## re-dressed; in the town the warband's own `equip_hand` does it, and the body
## the square stands up is dressed from the roster as any wardrobe change is.
func _bind(slot: String, weapon_id: String) -> void:
	var world = town.get("host") if town != null else null
	if world == null:
		_say("No world to carry that piece.", false)
		_refresh()
		return
	# A piece the keys have opened is owed to the stash, once: an open row the
	# ledger has not booked as forged is granted here - the inventory is always
	# where the hand takes the piece from. A weapon the player has since worn and
	# sold is not re-minted by pressing the row again.
	var warband = world.get("warband")
	var meta = _meta()
	if warband != null and meta != null and meta.needs_forge(weapon_id):
		if warband.stash.owns(weapon_id, warband.roster):
			# A ledger from before the forge already has the piece: book it and
			# mint no spare.
			meta.mark_forged(weapon_id)
		else:
			var forged: Dictionary = warband.grant_gear(weapon_id)
			if bool(forged.get("ok", false)):
				meta.mark_forged(weapon_id)
	var director = world.get("roguelite")
	var result: Dictionary
	if director != null and bool(director.is_running()):
		result = director.rebind_hand(int(director.local_peer()), slot, weapon_id)
	else:
		var context := _ability_context()
		var held = context.get("warband")
		if held == null or int(context.get("merc", -1)) <= 0:
			result = {"ok": false, "message": "No body stands on the rack ground."}
		else:
			result = held.equip_hand(int(context["merc"]), slot, weapon_id)
	_say(str(result.get("message", "")), bool(result.get("ok", false)))
	_refresh()


func _say(text: String, good: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", GOOD if good else BLOOD)


## The body whose hands decide what can be equipped. The rack is opened from the
## square, so the controlled mercenary is the one the page works; a lent warband
## goes through the same state verbs and sends the equip to its host.
func _ability_context() -> Dictionary:
	var world = town.get("host") if town != null else null
	var warband = world.get("warband") if world != null else null
	if warband == null:
		return {}
	var controller = world.get("controller")
	var actor = controller.get("active_actor") if controller != null else null
	var merc := -1
	if controller != null and actor != null and controller.has_method("merc_of"):
		merc = int(controller.merc_of(actor))
	if merc <= 0:
		var ids: Array = warband.roster.ids()
		if not ids.is_empty():
			merc = int(ids[0])
	if merc <= 0:
		return {}
	var gear: Dictionary = warband.roster.equipped_of(merc)
	return {"warband": warband, "merc": merc,
		"name": str(warband.roster.name_of(merc)), "gear": gear}


func _ability_rows() -> void:
	var context := _ability_context()
	if context.is_empty():
		_row("No body stands on the rack ground.", MUTED, 28)
		return
	var warband = context["warband"]
	var merc := int(context["merc"])
	var gear: Dictionary = context["gear"]
	var book: Array = warband.ability_book(merc)
	var order := {"any": 0, "unarmed": 1, "bow": 2, "sword": 3, "two_hand": 4,
		"dagger": 5, "staff": 6, "shield": 7}
	book.sort_custom(func(a, b):
		var rank_a := int(order.get(str(a.get("type", "any")), 8))
		var rank_b := int(order.get(str(b.get("type", "any")), 8))
		if rank_a != rank_b:
			return rank_a < rank_b
		return str(a.get("name", "")) < str(b.get("name", "")))
	var equipped := 0
	for entry in book:
		if bool(entry.get("equipped", false)) and not bool(entry.get("automatic", false)):
			equipped += 1
	_row("BODY  ·  %s  ·  %s" % [str(context["name"]),
		_hand_summary(gear)], BRASS, 28)
	_row("%d / %d keys taken  ·  the five keys hold the family starters and these; medicine has its own two keys." % [
		equipped, AbilityRules.SLOT_COUNT], MUTED, 30)
	var index := AbilityIndex.counts()
	_row("%d active skills in this book  ·  %d ability upgrades live in the pool, not here." % [
		int(index.active), int(index.upgrade)], MUTED, 28)
	_row("An ABILITY chest stands three skills and keeps one; the first chest of "
		+ "every island is one.", MUTED, 28)
	for entry in book:
		var id := str(entry.get("id", ""))
		var definition := AbilityRules.by_id(id)
		var display := str(entry.get("name", id)).capitalize()
		var types: Variant = entry.get("types", [])
		var family := AbilityRules.family_labels(types if types is Array \
			else [str(entry.get("type", "any"))])
		var requirement := AbilityRules.requirement_label(definition)
		var description := str(entry.get("description", ""))
		if bool(entry.get("automatic", false)):
			var automatic := "STARTER" if AbilityRules.is_starter(id) else "UNARMED"
			if not bool(entry.get("fits", false)):
				automatic += "  ·  NEEDS " + requirement
			var label := _row("  %s  ·  %s  ·  %s" % [display, family, automatic], MUTED, 28)
			label.tooltip_text = description
			continue
		if not bool(entry.get("unlocked", false)):
			# No key price any more: a skill is opened by an ABILITY chest, and a
			# row the player has not found is a row the rack cannot sell.
			var locked := _row("  %s  ·  %s   [NOT FOUND  ·  AN ABILITY CHEST PAYS IT]" % [
				display, family], LOCKED, 28)
			locked.tooltip_text = description
			continue
		if bool(entry.get("equipped", false)):
			var take_off := _button("  %s  ·  %s   [EQUIPPED%s]" % [display, family,
				"" if bool(entry.get("fits", false)) else "  ·  WAITING FOR " + requirement],
				GOOD, _toggle_ability.bind(merc, id))
			take_off.tooltip_text = description + "\nClick to take it off the bar."
			continue
		var fits := bool(entry.get("fits", false))
		var equip := _button("  %s  ·  %s   %s" % [display, family,
			"EQUIP" if fits else "[HOLD A %s]" % requirement], INK if fits else LOCKED,
			_toggle_ability.bind(merc, id), not fits)
		equip.tooltip_text = description


func _hand_summary(gear: Dictionary) -> String:
	var main := str(gear.get("main", ""))
	var off := str(gear.get("off", ""))
	var parts: Array[String] = []
	parts.append(str((State.ITEMS.get(main, {}) as Dictionary).get("name", "empty hand")) if main else "empty hand")
	if not off.is_empty():
		parts.append("off: %s" % str((State.ITEMS.get(off, {}) as Dictionary).get("name", off)))
	return "  +  ".join(PackedStringArray(parts))


func _toggle_ability(merc_id: int, ability_id: String) -> void:
	var context := _ability_context()
	if context.is_empty():
		return
	var result: Dictionary = context["warband"].toggle_ability(merc_id, ability_id)
	_message.text = str(result.get("message", ""))
	_message.add_theme_color_override("font_color",
		GOOD if bool(result.get("ok", false)) else BLOOD)
	_refresh()


func _portal_rows(meta) -> void:
	var context := _ability_context()
	var pair := _carried(context) if not context.is_empty() else {"ranged": "", "melee": ""}
	var ranged_def: Dictionary = Weapons.get_weapon(str(pair.get("ranged", "")))
	var melee_def: Dictionary = Weapons.get_weapon(str(pair.get("melee", "")))
	_row("CARRYING  ·  %s  |  %s" % [
		str(ranged_def.get("name", "empty hand")),
		str(melee_def.get("name", "empty hand"))], INK, 26)
	_row("The pair the portal carries is the kit the body is wearing: put a weapon " +
"in its hands on the rack or the character page.", MUTED, 30)
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
