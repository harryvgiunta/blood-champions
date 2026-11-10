class_name RogueliteCardArt
extends RefCounted
## The reward card's rendered art: rarity frames, family sigils and the plate a
## world prop hangs its name on.
##
## `assets/ui/cards/cards.json` is the manifest `tools/build_reward_cards.py`
## writes; this reads it once, loads each texture once and hands the HUD a
## `Texture2D`. A rarity the renderer did not produce falls back to `neutral`, so
## a new tier needs a new render rather than a blank card.
##
## Nothing here decides what a card *says*: the catalogue owns the words, this
## owns only the pictures.

const DIR := "res://assets/ui/cards/"
const MANIFEST := DIR + "cards.json"
const FALLBACK_RARITY := "neutral"
const FALLBACK_FAMILY := "perk"

static var _frames: Dictionary = {}
static var _sigils: Dictionary = {}
static var _plaques: Dictionary = {}
static var _margin := 48
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST):
		push_warning("card art manifest missing: %s" % MANIFEST)
		return
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	_margin = int(data.get("frame_margin", _margin))
	for rarity in (data.get("frames", {}) as Dictionary):
		var states: Dictionary = (data["frames"] as Dictionary)[rarity]
		var pair := {}
		for state in states:
			var path := DIR + str((states[state] as Dictionary).get("file", ""))
			var texture := _texture(path)
			if texture != null:
				pair[str(state)] = texture
		if not pair.is_empty():
			_frames[str(rarity)] = pair
	for family in (data.get("sigils", {}) as Dictionary):
		var texture := _texture(DIR + str((data["sigils"] as Dictionary)[family].get("file", "")))
		if texture != null:
			_sigils[str(family)] = texture
	for rarity in (data.get("plaques", {}) as Dictionary):
		var texture := _texture(DIR + str((data["plaques"] as Dictionary)[rarity].get("file", "")))
		if texture != null:
			_plaques[str(rarity)] = texture


static func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The card's plate. `lit` is the state under the pointer; a rarity with no lit
## render reuses its idle one, and an unknown rarity falls to `neutral`.
static func frame(rarity: String, lit: bool) -> Texture2D:
	_load()
	var row: Dictionary = _frames.get(rarity, _frames.get(FALLBACK_RARITY, {}))
	if row.is_empty():
		return null
	return row.get("lit" if lit else "idle", row.get("idle", null))


## The 9-slice border, in texture pixels and in drawn pixels alike.
static func margin() -> int:
	_load()
	return _margin


## A family's emblem, drawn on the card's field beside its name.
static func sigil(family: String) -> Texture2D:
	_load()
	return _sigils.get(family, _sigils.get(FALLBACK_FAMILY, null))


## The plate a prop's name stands on, as a world billboard.
static func plaque(rarity: String) -> Texture2D:
	_load()
	return _plaques.get(rarity, _plaques.get(FALLBACK_RARITY, null))


## The rarity a promise is drawn in. A chest with no tier (a cache, a hoard) has
## no rarity, and the plate still has to exist.
static func rarity_key(rarity: String) -> String:
	_load()
	return rarity if _frames.has(rarity) else FALLBACK_RARITY
