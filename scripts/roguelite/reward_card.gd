class_name RogueliteRewardCard
extends Button
## One upgrade or ware, drawn as a card instead of a line of text.
##
## The plate is the rarity's rendered frame (`RogueliteCardArt`), the emblem is
## its family's sigil, and the words are laid inside the frame in the ledger's
## own faces: a display name, a small-caps line naming the hand and the tier, and
## the catalogue's description wrapped under a rule. A card does not know the
## catalogue - the caller passes the strings and the two keys the art reads - so
## the draft, the shop and any later surface share one component.
##
## It is a `Button` on purpose: focus, hover, activation and the keyboard all
## already work, and a card that cannot be chosen with a gamepad is a picture.

const Ledger = preload("res://scripts/ui/ledger_theme.gd")
const Art = preload("res://scripts/roguelite/card_art.gd")

const WIDTH := 352.0
const HEIGHT := 232.0
## The text's inset from the plate's edge: inside the rendered ring, which is the
## 9-slice margin on screen as well as in the texture. The top and bottom take a
## little more, because the ring's inner moulding eats into the field there.
const PAD_X := 48.0
const PAD_Y := 52.0
const SIGIL := 56.0
const INK := Color(0.96, 0.93, 0.85)
const MUTED := Color(0.85, 0.80, 0.69)
const RULE := Color(0.32, 0.27, 0.20)
const VALUE := Color(0.90, 0.79, 0.48)

var rarity := "common"
var family := "perk"
var _plate: NinePatchRect
var _sigil: TextureRect
var _name: Label
var _meta: Label
var _body: Label
var _value: Label
var _lit := false


func _ready() -> void:
	if _plate == null:
		_build()
	_apply_art()


func compose(title: String, meta: String, body: String, rarity_key: String,
		family_key: String, value: String = "", count: int = 0) -> void:
	rarity = Art.rarity_key(rarity_key)
	family = family_key
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if _plate == null:
		_build()
	_name.text = title
	_meta.text = meta
	_body.text = body
	_value.text = value
	_value.visible = not value.is_empty()
	_sigil.texture = Art.sigil(family)
	# A second copy of a row already carried: the number is on the card, because
	# the plate below the draft is not where a choice is made.
	if count > 0:
		_meta.text = "%s   ×%d" % [meta, count]
	_apply_art()


func _build() -> void:
	_plate = NinePatchRect.new()
	_plate.name = "Plate"
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := Art.margin()
	_plate.patch_margin_left = margin
	_plate.patch_margin_right = margin
	_plate.patch_margin_top = margin
	_plate.patch_margin_bottom = margin
	add_child(_plate)

	var column := VBoxContainer.new()
	column.name = "Copy"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = PAD_X
	column.offset_right = -PAD_X
	column.offset_top = PAD_Y - 4.0
	column.offset_bottom = -PAD_Y + 4.0
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	_sigil = TextureRect.new()
	_sigil.custom_minimum_size = Vector2(SIGIL, SIGIL)
	_sigil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sigil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_sigil)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(titles)
	_name = _label(titles, 25, INK, Ledger.FONT_DISPLAY)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = 2
	_meta = _label(titles, 13, MUTED, Ledger.FONT_BODY)
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var rule := ColorRect.new()
	rule.color = RULE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	_body = _label(column, 15, Color(0.93, 0.90, 0.82), Ledger.FONT_BODY)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# The price sits on the plate's own rule, one margin in from the ring: a
	# right-aligned label at the field's edge runs into the bevel.
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(foot)
	_value = _label(foot, 13, VALUE, Ledger.FONT_BODY)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# The foot is a short line by design - a price, a tag - so it takes its own
	# width. `clip_text` collapsed that width to a pixel, and every price and
	# every tag the shop and the draft laid on the plate was measured one pixel
	# wide and never drawn.
	_value.max_lines_visible = 1

	mouse_entered.connect(_set_lit.bind(true))
	mouse_exited.connect(_set_lit.bind(false))
	focus_entered.connect(_set_lit.bind(true))
	focus_exited.connect(_set_lit.bind(false))


func _label(parent: Node, size: int, colour: Color, font: Font) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_override("font", font)
	# No drop shadow: a one-pixel shadow at these sizes draws a second, softer
	# copy of every glyph, which is what makes small type read as fuzzy. The
	# plate behind the words is dark enough to carry them on its own.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## A ware the party already bought. The card stays on the board - a stall that
## hides its sold rows makes a player reread the whole row - but it is inert.
func set_spent(spent: bool) -> void:
	disabled = spent
	_apply_art()


func _set_lit(lit: bool) -> void:
	if _lit == lit:
		return
	_lit = lit
	_apply_art()


## The lit plate is a second render - the ring under the pointer's own light -
## so hover is a texture swap rather than a colour multiply. The name takes the
## tier's colour in both states, because the tier has to be readable at a glance.
func _apply_art() -> void:
	if _plate == null:
		return
	var texture := Art.frame(rarity, _lit)
	if texture != null:
		_plate.texture = texture
	_name.add_theme_color_override("font_color", _rarity_ink())
	_plate.modulate = Color(1, 1, 1) if not disabled else Color(0.55, 0.55, 0.55)


func _rarity_ink() -> Color:
	match rarity:
		"legendary":
			return Color(0.97, 0.81, 0.42)
		"epic":
			return Color(0.68, 0.83, 1.0)
		"greed":
			return Color(0.96, 0.50, 0.40)
		"common":
			return Color(0.86, 0.89, 0.84)
	return INK
