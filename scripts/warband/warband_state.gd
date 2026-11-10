extends Node
## Autoload `Warband`: the persistent soul, the roster, the infinite stash, the
## The roster, the purse and the campaign ledger, in one place.
##
## Ghost of the Warband is a possession game, so the thing that survives a
## battle is not a character: it is the warband. This node owns that state and
## nothing else - no scene, no camera, no input. The camp, the trail and the town
## read it and write back through it.
##
## Gold is the existing `PlayerState` purse; this node never keeps a second one.

signal changed
## A piece just woke into its skill at the altar. Whatever dresses bodies off the
## roster listens, so every body already holding a copy carries the skill at once.
## The warband armed itself out of the pool: these mercenaries' kits changed, so
## whatever keeps a live rig re-dresses them (`PossessionController`).
signal armed(merc_ids: Array)

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
## The sealed save container every game-state file is written in
## (`scripts/save_file.gd`): AES-256 over a binary payload with an HMAC tail, so a
## save is not a text file and an edited one is refused rather than loaded.
const SaveFileScript = preload("res://scripts/save_file.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const VendorScript = preload("res://scripts/warband/mercenary_vendor.gd")
const Recruits = preload("res://scripts/warband/recruit_catalog.gd")
const SoulScript = preload("res://scripts/warband/soul_router.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const EquipmentRules = preload("res://scripts/equipment_rules.gd")

## Item categories a body can wear; the same list `EquipmentRules` enforces.
const EQUIPPABLE_CATEGORIES := ["1h", "2h", "bow", "staff", "shield", "focus", "armor"]

## The order a body is armed in: steel first, then armour, then the trinkets.
## `dress_recruit` walks this list and takes the dearest spare the shared stash
## holds for each slot; `arm_one_piece` walks the same order and stops at the
## first slot it can fill, which is how one kill arms one hand.
const DRESS_SLOTS := ["main", "off", "head", "chest", "hands", "legs", "feet"]

## Additive save format. v3 added each mercenary's two weapon sets (`weapon_sets`
## plus `active_set` per record), the pair `TAB` brings up; v4 added the
## checkpoint bookmark (`checkpoint`), the autosave that remembers which stretch
## of the world the warband has already played; v5 carried a campaign ledger that
## v17 deleted - the game has no quests, and a file that still names one opens with
## no orders at all; v6 added the altar's anointed pieces (retired in v18: a skill
## is the player's unlock, never a piece's); v7 dropped the expedition's battle ledger
## (`runs`, `run_totals`); v8 added the delve (`delve`): the inventory packed at
## the Hollow's mouth and, while a party is below, who went down; v9 added the
## party's mode (`party_mode`), how the squad picks its fights; v10 added the
## auto-equip holds, retired in v19 with the right-click that set them - the band
## arms from every spare it finds; v11 added each record's disposition (the `tank` /
## `melee` / `bow` behaviour the squad AI reads per body and the arming reads when
## it picks a piece); v15 added the Hollow's difficulty (`delve.mode`), the crowd,
## pool and rate the floor is built with; v13 added each record's hotbar layout
## (`hotbar_order`), the sequence of ability ids the player has laid on the keys;
## v16 added each record's hand-set slots (`manual`), the pieces automatic
## arming may never touch; v18 makes `hotbar_order` the equipped ability list
## (player-level unlocks, family-filtered on the bar) and clears pre-v18 layouts,
## which were reorders of skills anointed onto steel; v19 makes that list
## positional - one entry per key of the five-key bar, an empty string for a key
## the player left empty, with the run's own upgrades able to buy up to five more
## keys. Older files still load: a record with no sets puts
## the pair already in its hands in Set 1 and starts Set 2 empty, a file without a
## checkpoint resumes at the town as it always did, a file still carrying a
## ledger ignores it, a file without anointings carries plain steel, a file
## without a delve has an empty pack and nobody below, a file without a party mode
## fights defensive, the band's own answer,
## a file without a disposition fields every body as melee, a file without a
## hotbar layout fires every skill from the first free key, a
## file without a delve mode goes down an easy Hollow, and a file without hand-set
## slots leaves every slot to the arming, as it always did.
const SAVE_VERSION := 19
const DEFAULT_SAVE_PATH := "user://warband_state.json"
## The areas a checkpoint may name. A checkpoint is a *place in the campaign*,
## not a save slot: the camp is the only place a run starts, so it is never a
## checkpoint (the opening is already restartable from the title).
const CHECKPOINT_AREAS := ["trail", "town"]
## What every gear and purse verb answers while the warband is lent (see `lent`).
const LENT_MESSAGE := "This is the host's warband: only the host changes its gear and purse."

var roster: WarbandRoster = RosterScript.new()
var souls: SoulRouter = SoulScript.new()
var stash: WarbandStash = StashScript.new()
## Which copy a worn piece is: `"<merc id>:<slot>" -> {item, ordinal}`. The
## roster stores catalog ids, so the copy is bookkeeping that lives here.
var worn_copies: Dictionary = {}
var deployment_cap: int = Contracts.MAX_DEPLOYMENT_CAP
var save_path := DEFAULT_SAVE_PATH
## True when a mode has already handed this warband its starting bodies, so a
## scene reload cannot seed a second copy of the same squad.
var seeded := false
## The mercenary each peer is currently inside, mirrored from the router so a
## scene hand-off can restore control without a live body.
var possession: Dictionary = {}   # peer_id -> merc_id
## Seconds into the current 5 s revive channel, keyed by peer id.
var revive_channels: Dictionary = {}  # peer_id -> {merc_id, seconds}
## The last autosave bookmark: `{id, area, position, label, at}` or `{}`. It is
## written by the world at the moments the campaign becomes a new stretch - the
## camp's six watchers down and the squad on the road, the town square entered -
## and it is what a wipe and the title's campaign list read. The roster, stash and
## essence beside it are the warband as it stood then; the purse is not rolled
## back, because `PlayerState` owns it and a reload must never repay a run.
var checkpoint: Dictionary = {}
## How the squad picks its fights (`Contracts.PARTY_MODES`): set from the warband
## menu with `set_party_mode`, saved with the books and lent with them, so a co-op
## guest's menu shows the host's mode. Only the host's squad acts on it.
var party_mode: String = Contracts.DEFAULT_PARTY_MODE
## The town desk's three rows (`Warband.town_board()`): `RecruitCatalog.offer`
## dictionaries rolled at `RecruitCatalog.TOWN_LEVEL`, each priced at the desk's
## own curve. Presentation and state at once, so a screen repaint cannot re-roll
## the bodies under the player's cursor; laid out on the first read and re-rolled
## after every sale, never saved.
var hire_board: Array[Dictionary] = []
var _board_rng := RandomNumberGenerator.new()
## True while this warband is a co-op host's, lent to this machine for the length
## of a session (`GameFlow.join_campaign`). A lent warband is shown and played and
## never touches this machine's files: `save_state` and `load_state` refuse, so the
## guest's own campaign is exactly as it was when the session ends. The host is
## the only place the shared warband changes - its purse, its roll and its kit -
## so every purse verb below answers `LENT_MESSAGE`, and every gear verb is
## carried to the host through `gear_requester` and comes back with the next copy
## (`lend()`); a gear verb with no session to ask refuses like the rest, and the
## host's own updates arrive through `lend()` as well. `end_loan()` gives this
## machine its own warband back.
var lent := false
## The band's medicine: one count per consumable kind a keeper sells (`bandage`,
## `potion`). It is deliberately *not* a stash row - a dressing is tied onto a body
## and a draught is drunk, so the count is the whole of what a purchase buys, and
## the shared stash stays the pool of pieces gathered on the field. Saved with the
## warband and lent with it. The kit's two consumable keys spend it
## (`WarbandBody.try_consume`).
var supplies: Dictionary = {"bandage": 0, "potion": 0}
## True while `arm_warband` is walking the roster, so an equip that emits
## `changed` (or anything listening to it) cannot start a second pass.
var _arming := false
## The host's purse while lent: shown, never spent on this machine.
var _lent_gold := 0

func _ready() -> void:
	set_process(false)
	# The campaign this launch resumes (`SaveSlots`): every writer below - the
	# autosave, a bookmark, a gear change - goes to that folder and no other. A
	# machine with no campaign keeps the single pre-slot path until one is made.
	var slots := get_node_or_null("/root/SaveSlots")
	if slots != null and not str(slots.active).is_empty():
		save_path = str(slots.warband_path(str(slots.active)))
	if not roster.died.is_connected(_on_merc_died):
		roster.died.connect(_on_merc_died)

# --- purse -----------------------------------------------------------------

func gold() -> int:
	if lent:
		return _lent_gold
	var state := get_node_or_null("/root/PlayerState")
	return int(state.credits) if state != null else 0

## False (and nothing spent) when the purse cannot cover it.
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if lent:
		return false
	var state := get_node_or_null("/root/PlayerState")
	if state == null or int(state.credits) < amount:
		return false
	state.add_credits(-amount)
	return true

func award_gold(amount: int) -> void:
	if amount == 0 or lent:
		return
	var state := get_node_or_null("/root/PlayerState")
	if state != null:
		state.add_credits(amount)

# --- the co-op loan ----------------------------------------------------------

## Take a co-op host's warband for the session: the roster, stash, essence,
## orders and bookmark exactly as the host holds them (its `to_dict()`), and the
## host's purse. The host sends it again whenever its warband changes, so this is
## also how the lent copy keeps up.
func lend(data: Dictionary, gold_amount: int) -> void:
	lent = true
	_lent_gold = maxi(0, gold_amount)
	from_dict(data)

## A co-op host's purse moved on its own, with no change to the books beside it: a
## kill's gold, a sale. The whole copy does not need re-sending for one number.
func lend_purse(amount: int) -> void:
	if not lent:
		return
	var next := maxi(0, amount)
	if next == _lent_gold:
		return
	_lent_gold = next
	_notify()

## Hand the lent warband back: this machine's own save is read again, or a fresh
## warband stands in when there is none, so the title opens exactly the campaign
## it opened before the session.
func end_loan() -> void:
	if not lent:
		return
	lent = false
	_lent_gold = 0
	gear_requester = Callable()
	clear_possession()
	if not load_state():
		reset_state()

## The refusal every gear and purse verb gives while lent, in the shape that verb
## always answers with.
func _lent_refusal(fields: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "message": LENT_MESSAGE}
	out.merge(fields)
	return out

## The refusal a gear verb gives on a body whose kit is its own (`is_gear_locked`).
## True when the verb must stop here; the caller returns its own shape.
func _locked_refusal(merc_id: int, fields: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "message": LOCKED_GEAR % roster.name_of(merc_id)}
	out.merge(fields)
	return out

## Whether `merc_id` may have its kit moved at all. One question, so a new verb
## cannot forget it.
func _gear_locked(merc_id: int) -> bool:
	return is_gear_locked(merc_id)

# --- gear on a lent warband --------------------------------------------------
#
# A guest plays the host's warband and never writes it, but its kit is the pool
# everyone shares: wearing a piece, taking one off, swapping a weapon set or
# re-kitting a body are all things a guest may *ask* for. The verb below is
# carried to the host, the host runs the same verb on its own books, and the
# answer comes back with the next mirror (`WarbandSession.receive_warband`).
# A lent copy with no session to ask - the title screen - refuses as it always
# did.

## What a guest is told while a gear verb is on its way to the host.
const GEAR_SENT := "Sent to the host."
## What a locked kit answers with. A body bought off a desk - the town's or a
## run's - is sworn in the hand and the armour the board sold it
## (`is_gear_locked`), so every verb that would change a worn slot, the stance or
## the bar refuses it: no paperdoll press, no pickup, no re-kit, no swap.
const LOCKED_GEAR := "%s's kit is locked: a bought body fights in what it was sworn in."
## The gear verbs a guest may ask the host for, by the name a request carries:
## the kit on a body and the skill assigned to each key, which is part of the same
## dressing (`_worn_signatures` compares both).
const GEAR_VERBS := ["equip", "unequip", "swap_set", "reequip",
	"hotbar_order", "hotbar_slot", "hand", "grant"]

## Where a lent warband's gear verbs go: the co-op session installs a callable
## that sends the request to the host. Empty on a host and on a machine with no
## session.
var gear_requester := Callable()

## Hand one gear verb to the host. False when there is nowhere to send it, which
## leaves the verb's own lent refusal standing.
func ask_gear(verb: String, args: Array) -> bool:
	if not gear_requester.is_valid():
		return false
	return bool(gear_requester.call({"verb": verb, "args": args}))

## Run one gear request a guest sent, on these books - the one place a shared
## warband's kit ever changes. The change goes out with the session's mirror, so
## the guest sees it on the next copy; `{ok, message}` is what it is told.
func apply_gear_request(request: Dictionary) -> Dictionary:
	if lent:
		return _lent_refusal({})
	var verb := str(request.get("verb", ""))
	var raw: Variant = request.get("args", [])
	var args: Array = raw if raw is Array else []
	if not GEAR_VERBS.has(verb):
		return {"ok": false, "message": "That is not a gear request."}
	match verb:
		"equip":
			if args.size() < 3:
				return {"ok": false, "message": "That is not a gear request."}
			return equip_merc(int(args[0]), str(args[1]), str(args[2]))
		"unequip":
			if args.size() < 2:
				return {"ok": false, "message": "That is not a gear request."}
			var taken := unequip_merc(int(args[0]), str(args[1]))
			if taken.is_empty():
				return {"ok": false, "message": "Nothing comes off that slot."}
			return {"ok": true, "item_id": taken, "message": "Taken off the body."}
		"swap_set":
			if args.is_empty():
				return {"ok": false, "message": "That is not a gear request."}
			return swap_weapon_set(int(args[0]))
		"reequip":
			if args.is_empty():
				return {"ok": false, "message": "That is not a gear request."}
			return reequip_merc(int(args[0]))
		"hotbar_order":
			if args.size() < 2 or not args[1] is Array:
				return {"ok": false, "message": "That is not a gear request."}
			return set_hotbar_order(int(args[0]), args[1])
		"hotbar_slot":
			if args.size() < 3:
				return {"ok": false, "message": "That is not a gear request."}
			return set_hotbar_slot(int(args[0]), int(args[1]), str(args[2]))
		"hand":
			if args.size() < 3:
				return {"ok": false, "message": "That is not a gear request."}
			return equip_hand(int(args[0]), str(args[1]), str(args[2]))
		"grant":
			# One piece per unlocked row, whatever a request asks for: the forge
			# hands over a weapon, it is not a shop a guest can mint from.
			if args.is_empty():
				return {"ok": false, "message": "That is not a gear request."}
			return grant_gear(str(args[0]), 1)
	return {"ok": false, "message": "That is not a gear request."}

# --- the quiver ------------------------------------------------------------

## Arrows are unlimited in Blood Champions. The shaft item still exists - an
## archer's corpse carries a few and the delve's inventory can hold what was
## looted - but no bow reads a count, no keeper sells a bunch, and a piece in the
## quiver is never the reason a string stays down. These accessors remain for the
## loot and delve books that still move the item.
const ARROW_ITEM := "arrow"

func arrows() -> int:
	return field_stash().pooled_count(ARROW_ITEM)

## False when the quiver is empty. A caller drawing a bow asks this first.
func has_arrows() -> bool:
	return arrows() > 0

## Take up to `count` shafts out of the pool and answer how many actually left
## it: a loosed arrow asks for one and gets 0 or 1, so the count can never go
## negative however many shots a frame resolves.
func take_arrows(count: int = 1) -> int:
	var taken := 0
	while taken < maxi(count, 0) and field_stash().remove(ARROW_ITEM, 1):
		taken += 1
	if taken > 0:
		_notify()
	return taken

## Put shafts back in the pool: a keeper's bunch, an archer's corpse, a test.
func add_arrows(count: int = 1) -> int:
	var added := maxi(count, 0)
	if added <= 0:
		return 0
	field_stash().add(ARROW_ITEM, added)
	_notify()
	return added

# --- medicine ----------------------------------------------------------------

## The consumable kind a keeper's item is bought into: the catalog row names it
## in `supply`, so a bandage is `bandage` and a draught `potion`. Empty for
## anything that is not medicine.
static func supply_kind_of(item_id: String) -> String:
	var item: Dictionary = State.ITEMS.get(item_id, {})
	return str(item.get("supply", ""))


static func supply_kind_of_item(item: Dictionary) -> String:
	return str(item.get("supply", ""))


func supply_count(kind: String) -> int:
	return maxi(0, int(supplies.get(kind, 0)))


func has_supply(kind: String) -> bool:
	return supply_count(kind) > 0


## Put `count` doses of one medicine into the band's stock and answer the new
## total. The purse is not touched here - `buy_gear` pays for it.
func add_supply(kind: String, count: int = 1) -> int:
	if kind.is_empty() or count <= 0:
		return supply_count(kind)
	supplies[kind] = supply_count(kind) + count
	_notify()
	return supply_count(kind)


## Spend one dose. False when there is none, so the key can refuse rather than
## heal off an empty pack.
func take_supply(kind: String) -> bool:
	if supply_count(kind) <= 0:
		return false
	supplies[kind] = supply_count(kind) - 1
	_notify()
	return true


# --- the field's pool ---------------------------------------------------------

## The pool the field's hands work: the shared stash. Equipping, unequipping, a
## loot take, a dead squadmate's kit and the quiver all go through this.
func field_stash() -> WarbandStash:
	return stash

## How a message names that pool.
func field_label() -> String:
	return "the shared stash"

## The mercenaries whose gear may be moved right now: the whole roster.
func dressable_ids() -> Array[int]:
	return roster.ids()

# --- roster ----------------------------------------------------------------

func merc_ids() -> Array[int]:
	return roster.ids()

func alive_merc_ids() -> Array[int]:
	return roster.alive_ids()

# --- the field and the reserve ---------------------------------------------
#
# The field is the bodies the warband has standing: at most `deployment_cap` of
# them. A name sworn while the field is full - a soldier cut out of a cage past
# the third body - waits in the reserve (`WarbandRoster.is_reserve`) with no body
# at all, and takes a place again only in the town (the world decides where; this
# only keeps the books).

## Places left on the field: the cap less every oath already standing on it. A
## joining player's own character is not an oath - the recruiter's cap is about
## how many mercenaries the town hires, not how many friends may play - so it
## never spends a place, and neither does a body bought off a run's board.
func field_room() -> int:
	return maxi(0, deployment_cap - band_field_count())

## The bodies on the field the recruiter swore, in field order.
func band_field_count() -> int:
	var count := 0
	for merc_id in roster.field_ids():
		if not roster.is_player(int(merc_id)) and not roster.is_recruit(int(merc_id)):
			count += 1
	return count

## The bodies a joining player brought with them.
func player_ids() -> Array[int]:
	var out: Array[int] = []
	for merc_id in roster.ids():
		if roster.is_player(int(merc_id)):
			out.append(int(merc_id))
	return out

## The player body a name already has, or -1. A player who has played this
## campaign before keeps the character they left, so a rejoin does not multiply
## the band.
func player_body_for(player_name: String) -> int:
	var wanted := player_name.strip_edges().to_lower()
	if wanted.is_empty():
		return -1
	for merc_id in player_ids():
		if not roster.is_alive(int(merc_id)):
			continue
		if roster.name_of(int(merc_id)).to_lower() == wanted:
			return int(merc_id)
	return -1

## Give a joining player a character of their own: the body they already had, or
## a fresh one named after them, carrying the pair a new game opens with and
## promised a place on the field whatever the band's cap says. Never charged to
## the purse - an oath costs gold, a friend does not - and never handed to the
## squad as a hire. Answers the mercenary's id, or -1 when there is no warband.
func enlist_player(player_name: String) -> int:
	var named := player_name.strip_edges()
	if named.is_empty():
		named = "Guest"
	var standing := player_body_for(named)
	if standing > 0:
		if roster.is_reserve(standing):
			roster.set_reserve(standing, false)
			_notify()
		return standing
	var merc_id := roster.create(named)
	roster.set_player(merc_id, true)
	roster.set_reserve(merc_id, false)
	# The pair a new game opens with, and nothing out of the party's shelf: a
	# guest's first minute is not the place to learn the paperdoll, and the spares
	# the town is holding stay where the host can see them.
	_issue_starting_arms(merc_id)
	_notify()
	return merc_id

## The oldest name in the reserve takes a place on the field. Returns its id, or
## -1 when the field is full or nobody waits.
func deploy_reserve() -> int:
	if field_room() <= 0:
		return -1
	var waiting := roster.reserve_ids()
	if waiting.is_empty():
		return -1
	roster.set_reserve(waiting[0], false)
	_notify()
	return waiting[0]

## A file can name more bodies on the field than the cap allows (one written
## before the reserve existed, when every rescue took the field), or none at all
## while names wait in the reserve. The newest fielded names step back into the
## reserve until the field fits, and an empty field takes the reserve's oldest,
## so a load always stands the warband up inside the cap.
func _balance_field() -> void:
	# Only the band's oaths are balanced: a player's own character never rolls
	# into the reserve because the town hired too many, never spends one of the
	# places a hire takes, and a bought recruit is on the field for the run it was
	# bought for - the cap is not about it.
	var band: Array[int] = []
	for merc_id in roster.field_ids():
		if not roster.is_player(int(merc_id)) and not roster.is_recruit(int(merc_id)):
			band.append(int(merc_id))
	for index in range(band.size() - 1, deployment_cap - 1, -1):
		roster.set_reserve(band[index], true)
	if band_field_count() > 0:
		return
	var waiting: Array[int] = []
	for merc_id in roster.reserve_ids():
		if not roster.is_player(int(merc_id)) and not roster.is_recruit(int(merc_id)):
			waiting.append(int(merc_id))
	for index in mini(waiting.size(), deployment_cap):
		roster.set_reserve(waiting[index], false)

## The dead leave the warband the moment they die: a corpse is not a party member,
## it cannot be deployed or entered, and its record used to sit on the hire cap
## forever - a band that had filled its eight places could never swear another
## body because the fallen still counted. The name leaves the roster, the body
## leaves the soul router, and everything it was still wearing goes back into the
## shared stash, so dying costs the man, never the gear - unless he died below:
## a member of the party below leaves his kit on his corpse (the world takes it
## off his books as he dies, `world_scene._leave_remains`), and the party gets it
## back only by looting the body. A hireling is the same bargain and a harder one:
## his death drops the whole kit at the body (`world_scene.drop_merc_kit`), so the
## record arrives here empty and the band's man and the steel he wore are both
## gone until the desk sells another. Returns the fallen records (`[{id, name,
## health, max_health, items}]`); empty when nobody died.
func reap_dead() -> Array[Dictionary]:
	var fallen := roster.take_dead()
	if fallen.is_empty():
		return fallen
	for entry in fallen:
		var merc_id := int(entry.get("id", 0))
		for item_id in entry.get("items", []):
			stash.add(str(item_id), 1)
		if souls.has_body(merc_id):
			souls.unregister_body(merc_id)
		for peer_id in possession.keys():
			if int(possession[peer_id]) == merc_id:
				possession.erase(peer_id)
		for peer_id in revive_channels.keys():
			var channel: Variant = revive_channels[peer_id]
			if channel is Dictionary and int((channel as Dictionary).get("merc_id", 0)) == merc_id:
				revive_channels.erase(peer_id)
	_notify()
	return fallen

func _on_merc_died(_merc_id: int) -> void:
	reap_dead()

## The band a new game opens with: one body carrying the two starter weapons.
## He is naked apart from the naked base set the paperdoll draws for an empty slot;
## the rest of the armory is unlocked on the rack with keys a boss drops.
const STARTING_BAND := [
	{"name": "Aldous"},
]
## The pair every player begins with, one per weapon set: the war bow in set 1
## and the makeshift hatchet in set 2. Both are free in the rack's registry, and
## both ride onto the island exactly as they are bound here. The bow a body wakes
## with is the longbow: a slow, heavy draw that rewards holding it, rather than
## the sapling it used to carry out of the fire.
const STARTING_RANGED := "bow_long"
const STARTING_MELEE := "hatchet_makeshift"

## Seed a new game's one starting body with the starter pair. An existing warband
## is never touched: a resume or a second boot of the same save must not multiply
## the band. Both pieces walk the one path every other piece walks - into the
## shared stash and then onto the body through `equip_merc` - so the pool stays the
## only armorer and the purse is never charged for them.
func seed_starting_band() -> int:
	if not roster.is_empty():
		return roster.count()
	for entry in STARTING_BAND:
		var merc_id := add_mercenary(str(entry["name"]))
		_issue_starting_arms(merc_id)
	_notify()
	return roster.count()


## Put the starter pair in the body's two weapon sets: the bow in set 1, the
## hatchet in set 2, with set 1 left in the hands. Silent: the seeding owns the
## single notify, and a piece that came out of the pool is not a purchase.
func _issue_starting_arms(merc_id: int) -> void:
	if merc_id <= 0 or not roster.is_alive(merc_id):
		return
	field_stash().add(STARTING_RANGED, 1)
	equip_merc(merc_id, "main", STARTING_RANGED, false, false)
	if str(roster.equipped_of(merc_id).get("main", "")) != STARTING_RANGED:
		return
	# Set 2 is the melee hand: swap onto it, put the axe there, and come back to
	# the bow so the body walks out of the fire holding the ranged piece.
	roster.swap_weapon_set(merc_id)
	field_stash().add(STARTING_MELEE, 1)
	equip_merc(merc_id, "main", STARTING_MELEE, false, false)
	if str(roster.equipped_of(merc_id).get("main", "")) == STARTING_MELEE:
		roster.swap_weapon_set(merc_id)


func add_mercenary(merc_name: String = "", equipped: Dictionary = {}) -> int:
	var room := field_room() > 0
	var merc_id := roster.create(merc_name, equipped)
	roster.set_reserve(merc_id, not room)
	_notify()
	return merc_id

## Hand a body the best kit the warband already owns.
##
## A body that swears with empty hands is dead weight, so a **rescue** walks the
## equipment slots in the order a fighter would fill them and takes the dearest
## spare out of the shared stash for each one. A body the recruiter sold never
## walks it: the desks sell whole bodies, already inside the kit on the card and
## locked to it (`is_gear_locked`), which is why this refuses one. The pool is the
## only source here: nothing is minted, a real worn piece is left alone, and the
## naked set a prisoner is born in counts as bare, so a rescue in rags still takes
## gear. A two-hander locks the off hand, exactly as `EquipmentRules` says it
## does, and a piece the player held back from auto-equip stays in the pool.
## Returns `{ok, merc_id, fitted, message}` with the ids that walked across.
func dress_recruit(merc_id: int, slots: Array = DRESS_SLOTS) -> Dictionary:
	var fitted: Array[String] = []
	if lent:
		return _lent_refusal({"merc_id": merc_id, "fitted": fitted})
	if _gear_locked(merc_id):
		return _locked_refusal(merc_id, {"merc_id": merc_id, "fitted": fitted})
	if merc_id <= 0 or not roster.is_alive(merc_id):
		return {"ok": false, "merc_id": merc_id, "fitted": fitted, "message": ""}
	for entry in _fill_slots(merc_id, slots):
		fitted.append(str(entry.get("item_id", "")))
	if fitted.is_empty():
		return {"ok": true, "merc_id": merc_id, "fitted": fitted,
			"message": "%s takes the field with what the band had spare." % roster.name_of(merc_id)}
	_notify()
	return {"ok": true, "merc_id": merc_id, "fitted": fitted,
		"message": "%s arms from %s: %s." % [roster.name_of(merc_id), field_label(),
			", ".join(fitted.map(func(item_id: String): return str(
				State.ITEMS.get(item_id, {}).get("name", item_id))))]}

## One piece, off one kill: the campaign's own arming. A body walks the same
## `DRESS_SLOTS` order `dress_recruit` walks - steel first, then the armour, then
## the trinkets - and stops at the first slot that is still bare (empty, or the
## naked set) and that the pool can actually fill, taking exactly that one piece
## and nothing more. The body's disposition decides what the slot wants, exactly
## as it does for the arming passes, and the held pieces stay held.
##
## Nothing is minted and nothing is dressed twice: a body with a full kit walks
## its whole order to no effect and answers "", as does an empty pool, a lent
## warband and a body that is not alive. The one notify and one `armed` signal
## let a live rig re-dress the body the piece landed on.
## Returns the item id that walked across, or "".
func arm_one_piece(merc_id: int) -> String:
	if lent or _arming or _gear_locked(merc_id):
		return ""
	if merc_id <= 0 or not roster.is_alive(merc_id):
		return ""
	_arming = true
	var taken := ""
	for raw_slot in DRESS_SLOTS:
		var filled := _fill_slots(merc_id, [raw_slot])
		if filled.is_empty():
			continue
		taken = str(filled[0].get("item_id", ""))
		break
	_arming = false
	if taken.is_empty():
		return ""
	_notify()
	armed.emit([merc_id])
	return taken

## Arm the whole band out of the pool it can reach. The automatic answer to a
## shopping spree: every body the field can dress fills each slot that is empty
## or still wearing the naked set, taking the dearest legal, unheld spare the
## pool holds. A real worn piece is never upgraded, so a kit the player chose by
## hand is not overruled by a lucky purchase, and a slot the player filled by hand
## is not even looked at - the pin outranks the pass. One notify and one `armed`
## signal are emitted for the pass, never one per piece.
## Returns `{ok, fitted, mercs, message}`; `fitted` is `[{merc_id, slot, item_id}]`.
func arm_warband() -> Dictionary:
	var fitted: Array[Dictionary] = []
	var mercs: Array[int] = []
	if lent or _arming:
		return {"ok": false, "fitted": fitted, "mercs": mercs, "message": ""}
	_arming = true
	for merc_id in dressable_ids():
		if not roster.is_alive(merc_id):
			continue
		var filled := _fill_slots(merc_id, DRESS_SLOTS)
		if filled.is_empty():
			continue
		mercs.append(merc_id)
		fitted.append_array(filled)
	_arming = false
	if fitted.is_empty():
		return {"ok": true, "fitted": fitted, "mercs": mercs, "message": ""}
	_notify()
	armed.emit(mercs)
	return {"ok": true, "fitted": fitted, "mercs": mercs, "message": _arm_message(fitted)}

## Fill every named slot on one body from the field's pool. A slot is open when
## it is empty or still wears the naked set; a real worn piece is left alone, and
## so is a slot the player filled by hand - that is the piece the pass must never
## take back. The dearest legal, unheld copy wins, and a two-handed main never
## costs an off-hand already in use. The equip is the band's, not a hand's
## (`manual` false): it never pins a slot and never carries a pinned piece off
## another body. Returns `[{merc_id, slot, item_id}]`; the caller owns the one
## notify, which is what keeps a band-wide pass from repainting eight times.
func _fill_slots(merc_id: int, slots: Array) -> Array[Dictionary]:
	var fitted: Array[Dictionary] = []
	var disposition := roster.disposition_of(merc_id)
	for raw_slot in slots:
		var slot_id := str(raw_slot)
		if roster.is_manual(merc_id, slot_id):
			continue
		var gear := roster.equipped_of(merc_id)
		var current := str(gear.get(slot_id, ""))
		if not current.is_empty() and not EquipmentRules.bare_garment(current):
			continue
		if slot_id == "off":
			var main_item: Dictionary = State.ITEMS.get(str(gear.get("main", "")), {})
			if Contracts.two_handed_item(main_item):
				continue
		var best := _best_spare(slot_id, gear, disposition)
		if best.is_empty():
			continue
		var result := equip_merc(merc_id, slot_id, best, false, false)
		if not bool(result.get("ok", false)):
			continue
		fitted.append({"merc_id": merc_id, "slot": slot_id, "item_id": best})
	return fitted

## The best legal spare for one slot as this body would choose it: the one
## decision a recruit dressing, a band-wide arming pass and a pickup's snap-in all
## make. A disposition moves the score rather than the rule - a tank's shield and
## one-hander beat a dearer greatsword, a bow beats everything in a bowman's main
## hand - and the price still decides between two pieces of the same kind. Naked
## coverings never compete, and a piece the body's trade refuses
## (`Contracts.disposition_refuses_gear`: a bow to a blade) is not a spare at all
## - the hands wait for what they will use, and the bow waits in the pool.
##
## The off hand is the one slot where the stance outranks the price
## (`Contracts.disposition_off_hand_rank`): a tank takes the board over a second
## blade however much the blade is worth, because holding the line is what the
## hand is for. Inside one kind the dearest still wins, as everywhere else.
func _best_spare(slot_id: String, gear: Dictionary, disposition: String = "") -> String:
	var pool := field_stash()
	var body := Contracts.disposition_id(disposition)
	var off_worn := not str(gear.get("off", "")).is_empty() \
		and not EquipmentRules.bare_garment(str(gear.get("off", "")))
	var best := ""
	var best_score := -INF
	var best_rank := -1
	for item_id in pool.pooled_ids():
		var item: Dictionary = State.ITEMS.get(item_id, {})
		if item.is_empty() or not EquipmentRules.allowed(item, slot_id):
			continue
		if EquipmentRules.bare_garment(item_id):
			continue
		if Contracts.disposition_refuses_gear(body, item):
			continue
		if slot_id == "main" and off_worn and EquipmentRules.two_handed(item):
			continue
		var rank := Contracts.disposition_off_hand_rank(body, item, slot_id)
		var score := _gear_score(item_id, item, body)
		if rank < best_rank or (rank == best_rank and score <= best_score):
			continue
		best_rank = rank
		best_score = score
		best = item_id
	return best

## What one piece is worth to one body: its price plus what its kind is worth to
## the body's disposition (`Contracts.disposition_gear_score`). The one scoring
## function the arming and a pickup both read, so a bowman's main hand and a
## tank's shield hand cannot disagree about what they want.
func _gear_score(item_id: String, item: Dictionary, disposition: String) -> float:
	var value := WarbandStash.value_of(item_id)
	return Contracts.disposition_gear_score(disposition, item, value)

## Re-equip one body from the pool: everything it wears goes back first, then the
## same choice an arming pass makes fills it again - the dearest legal spare for
## each slot, scored by the body's disposition, so a tank comes back with a shield
## and a one-hander, a bowman with a bow and a melee body with the greatsword.
##
## This is the re-kit `arm_warband` is not: the arming pass only fills what is
## empty, while this hands a dressed body back and lets the band choose again.
## Nothing is minted and nothing is lost - a released piece is a pool row before
## the refill reads it, so the warband is worth the same number either side. The
## rags a body is born in stay on (they are the mesh the rig draws, not gear) and
## are traded for real armour as the fill finds it, and a body that carried an
## alternate weapon set keeps one.
##
## Returns `{ok, merc_id, released, fitted, message}`: `released` the ids that
## went back into the pool, `fitted` the `[{merc_id, slot, item_id}]` that walked
## out of it. A lent warband, a body outside the party and a body that is down
## are all refused with the kit untouched.
func reequip_merc(merc_id: int) -> Dictionary:
	var released: Array[String] = []
	var fitted: Array[Dictionary] = []
	if lent:
		if ask_gear("reequip", [merc_id]):
			return {"ok": true, "pending": true, "merc_id": merc_id,
				"released": released, "fitted": fitted, "message": GEAR_SENT}
		return _lent_refusal({"merc_id": merc_id, "released": released, "fitted": fitted})
	if _arming:
		return {"ok": false, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": ""}
	if merc_id <= 0 or not roster.has(merc_id):
		return {"ok": false, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": "No such mercenary."}
	if not dressable_ids().has(merc_id):
		return {"ok": false, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": "%s is not with the party." % roster.name_of(merc_id)}
	if _gear_locked(merc_id):
		return _locked_refusal(merc_id, {"merc_id": merc_id,
			"released": released, "fitted": fitted})
	if not roster.is_alive(merc_id):
		return {"ok": false, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": "%s cannot be dressed right now." % roster.name_of(merc_id)}
	var second_set := _second_set_bound(merc_id)
	# The press that clears every pin on this body: the player has asked the band
	# to choose for it, which is the one answer the arming may give over a hand's.
	roster.clear_manual(merc_id)
	_arming = true
	released = _release_worn(merc_id, field_stash())
	fitted = _refill(merc_id, second_set)
	_arming = false
	var message := _reequip_message(merc_id, released, fitted)
	if released.is_empty() and fitted.is_empty():
		return {"ok": true, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": message}
	_notify()
	armed.emit([merc_id])
	return {"ok": true, "merc_id": merc_id, "released": released, "fitted": fitted,
		"message": message}

## Hand every real piece a body wears back into `pool`, both weapon sets included.
## The rags it is born in stay on: `EquipmentRules.bare_garment` is the mesh the
## rig draws rather than gear, and no arming pass would ever hand it out again.
## Returns the ids released, in wear order. The caller owns the notify.
func _release_worn(merc_id: int, pool: WarbandStash) -> Array[String]:
	var out: Array[String] = []
	if pool == null:
		return out
	for entry in roster.worn_entries(merc_id):
		var item_id := str(entry.get("item", ""))
		if item_id.is_empty() or EquipmentRules.bare_garment(item_id):
			continue
		var slot_id := str(entry.get("slot", ""))
		if roster.take_worn(merc_id, slot_id,
				int(entry.get("set", -1))) != item_id:
			continue
		# The copy comes off the body as itself, exactly as `unequip_merc` and
		# `_strip_worn` do: a claim left behind is a piece the next equip into this
		# slot hands to the pool a second time.
		pool.add(item_id, 1, _release_claim(merc_id, slot_id, item_id))
		out.append(item_id)
	return out

## Fill a body that has just been stripped, from the pool the field works. The set
## in the hands is filled first; a body that carried a second one has it filled
## too, by putting that set in the hands for the length of the fill and swapping
## back after - so what the player set up is re-armed instead of halved.
## Returns `[{merc_id, slot, item_id}]`. The caller owns the notify.
func _refill(merc_id: int, second_set: bool = false) -> Array[Dictionary]:
	var fitted := _fill_slots(merc_id, DRESS_SLOTS)
	if not second_set:
		return fitted
	var swap: Dictionary = roster.swap_weapon_set(merc_id)
	if not bool(swap.get("ok", false)):
		return fitted
	fitted.append_array(_fill_slots(merc_id, RosterScript.HAND_SLOTS))
	roster.swap_weapon_set(merc_id)
	return fitted

## Whether the body carries a pair in the weapon set the hands are not holding.
## Both halves of the pair count: a stowed blade is re-armed like one in hand.
func _second_set_bound(merc_id: int) -> bool:
	var pair := roster.weapon_set_pair(merc_id, 1)
	return not str(pair.get("main", "")).is_empty() \
		or not str(pair.get("off", "")).is_empty()

## One line naming what one body's re-equip took, or why it took nothing.
func _reequip_message(merc_id: int, released: Array, fitted: Array) -> String:
	var merc_name := roster.name_of(merc_id)
	if not fitted.is_empty():
		return "%s re-equips from %s: %s." % [merc_name, field_label(), _fitted_names(fitted)]
	if not released.is_empty():
		return "%s hands everything back; %s holds nothing spare." % [merc_name, field_label()]
	return "%s is down to rags already, and %s holds nothing spare." % [merc_name, field_label()]

## The names of the pieces a pass fitted, in fitting order.
func _fitted_names(fitted: Array) -> String:
	var names: Array[String] = []
	for entry in fitted:
		var item_id := str((entry as Dictionary).get("item_id", ""))
		names.append(str(State.ITEMS.get(item_id, {}).get("name", item_id)))
	return ", ".join(names)

## One line naming the bodies an arming pass fitted, and what each took.
func _arm_message(fitted: Array) -> String:
	var parts: Array[String] = []
	for entry in fitted:
		var row: Dictionary = entry
		var merc_id := int(row.get("merc_id", 0))
		var item_id := str(row.get("item_id", ""))
		parts.append("%s %s" % [roster.name_of(merc_id),
			str(State.ITEMS.get(item_id, {}).get("name", item_id))])
	if parts.size() == 1:
		var only: Dictionary = fitted[0]
		return "%s takes it (%s)." % [roster.name_of(int(only.get("merc_id", 0))),
			EquipmentRules.slot_label(str(only.get("slot", "")))]
	return "The band arms itself: %s." % ", ".join(parts)

## Buy one catalog item with gold. Only medicine is for sale in the town: a row
## with no `supply` is refused here, because steel and plate are opened at the
## Weapon Rack or won out of a run's chests and never bought. A purchase is a
## count in the band's pack (`supplies`), not a stash row - a dressing is tied
## onto a body and a draught is drunk, so there is nothing left over to pool.
##
## The price is the same keeper price the paperdoll and the stash sort use, so
## nothing can disagree about what a piece is worth, and a `bundle` row hands over
## that many doses for the list price per dose.
func buy_gear(item_id: String) -> Dictionary:
	if lent:
		return _lent_refusal({"item_id": item_id, "cost": 0})
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty():
		return {"ok": false, "message": "The quartermaster does not stock that.", "item_id": item_id, "cost": 0, "count": 0}
	var count := State.item_bundle(item_id)
	var cost := int(item.get("price", 0)) * count
	if int(item.get("price", 0)) <= 0:
		return {"ok": false, "message": "That piece has no price.", "item_id": item_id, "cost": 0, "count": 0}
	if not spend_gold(cost):
		return {"ok": false, "item_id": item_id, "cost": cost, "count": count,
			"message": "You need %d gold; you have %d." % [cost, gold()]}
	# Medicine is the one thing a keeper sells, and it is a count rather than a
	# row: nothing is worn, nothing is pooled, and the band's healing is the
	# number the consumable keys spend.
	var supply := supply_kind_of_item(item)
	if supply.is_empty():
		return {"ok": false, "item_id": item_id, "cost": 0, "count": 0,
			"message": "No keeper sells %s: steel is opened at the rack, not bought."
				% str(item.get("name", item_id))}
	var held := add_supply(supply, count)
	_notify()
	return {"ok": true, "item_id": item_id, "cost": cost, "count": count,
		"supply": supply, "held": held,
		"message": "Bought %d × %s for %d gold. You carry %d." % [
			count, str(item.get("name", item_id)), cost, held]}

## Sell one pooled copy back to a keeper. The piece must be in the shared pool:
## a blade somebody is wearing is not the warband's to sell behind their back,
## and the pool is the only place a copy can leave without stripping a body.
##
## The keeper pays `share` of the catalogue price (60% by default), floored to a
## whole coin, so a sale always returns less than the purchase. `price` in the
## reply is what the purse was actually paid, not the catalogue figure.
func sell_gear(item_id: String, share: float = 0.6) -> Dictionary:
	if lent:
		return _lent_refusal({"price": 0, "item_id": item_id})
	var id := State.migrate_item_id(item_id)
	var item: Dictionary = State.ITEMS.get(id, {})
	if item.is_empty():
		return {"ok": false, "message": "No keeper buys that.", "price": 0, "item_id": item_id}
	var list_price := int(item.get("price", 0))
	if list_price <= 0:
		return {"ok": false, "message": "That piece has no price.", "price": 0, "item_id": id}
	var display := str(item.get("name", id))
	# The pool is the authority on whether there is a copy to sell: a worn piece
	# is on a body, not on the keeper's shelf, and a failed removal must never pay.
	# The pool is the authority on whether there is a copy to sell, and a
	# failed removal must never pay.
	if not stash.remove(id, 1):
		return {"ok": false, "price": 0, "item_id": id,
			"message": "You have no spare %s in the stash." % display}
	var payout := int(floor(float(list_price) * clampf(share, 0.0, 1.0)))
	var state := get_node_or_null("/root/PlayerState")
	if state != null:
		state.add_credits(payout)
	_notify()
	return {"ok": true, "item_id": id, "price": payout,
		"message": "Sold %s for %d gold." % [display, payout]}

## The ability book for one body: every catalog ability, its family, whether the
## player owns it, whether it fits the kit that body is wearing, and whether the
## player has it on the bar. The rack draws the locked rows; the character
## screen's SKILLS page draws the unlocked ones.
func ability_book(merc_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var meta = get_node_or_null("/root/Roguelite")
	var gear := roster.equipped_of(merc_id) if roster.has(merc_id) else {}
	var main_row: Dictionary = State.ITEMS.get(str(gear.get("main", "")), {})
	var off_row: Dictionary = State.ITEMS.get(str(gear.get("off", "")), {})
	var equipped := roster.hotbar_order_of(merc_id) if roster.has(merc_id) else []
	for id in AbilityRules.catalog_ids():
		var definition := AbilityRules.by_id(id)
		if definition.is_empty():
			continue
		var automatic := AbilityRules.is_automatic(id)
		var unlocked := automatic or (meta != null and bool(meta.is_ability_unlocked(id)))
		out.append({
			"id": id,
			"name": str(definition.get("name", id)),
			"type": AbilityRules.type_of(definition),
			"types": AbilityRules.families_of(definition),
			"description": str(definition.get("description", "")),
			"cost": AbilityRules.unlock_cost_of(id),
			"unlocked": unlocked,
			"automatic": automatic,
			"fits": AbilityRules.fits_gear(definition, main_row, off_row),
			"equipped": equipped.has(id),
		})
	return out


## Put one ability on the bar, on its first free key, or take it off wherever it
## sits. The unlock is the player's; the assignment is the body's. The bar hides
## the families the current hands do not fit, so a skill can wait for the other
## weapon set on the key it was given.
func toggle_ability(merc_id: int, ability_id: String) -> Dictionary:
	if not roster.has(merc_id):
		return {"ok": false, "message": "No such mercenary.", "order": []}
	var definition := AbilityRules.by_id(ability_id)
	if definition.is_empty() or AbilityRules.is_automatic(ability_id):
		return {"ok": false, "message": "That skill cannot be equipped.", "order": []}
	var order := roster.hotbar_order_of(merc_id)
	var equipped := order.has(ability_id)
	if equipped:
		# Emptying the key rather than dropping the entry: the skills behind it
		# keep the keys the player gave them.
		order[order.find(ability_id)] = ""
	else:
		var free := order.find("")
		if free < 0:
			if order.size() >= AbilityRules.SLOT_COUNT:
				return {"ok": false,
					"message": "The bar holds five skills. Take one off first.",
					"order": []}
			free = order.size()
		var gear := roster.equipped_of(merc_id)
		var main_row: Dictionary = State.ITEMS.get(str(gear.get("main", "")), {})
		var off_row: Dictionary = State.ITEMS.get(str(gear.get("off", "")), {})
		if not AbilityRules.fits_gear(definition, main_row, off_row):
			return {"ok": false,
				"message": "Hold a %s to equip %s." % [
					AbilityRules.requirement_label(definition),
					str(definition.get("name", ability_id)).capitalize()],
				"order": []}
		while order.size() < free:
			order.append("")
		if order.size() == free:
			order.append(ability_id)
		else:
			order[free] = ability_id
	var result := set_hotbar_order(merc_id, order)
	if bool(result.get("ok", false)):
		result["message"] = "%s %s." % [str(definition.get("name", ability_id)),
			"taken off the bar" if equipped else "equipped"]
	return result


# --- the hotbar -------------------------------------------------------------
#
# One assignment per key. The bar is five keys, and a key holds the skill the
# player put on it or nothing at all; a run's own upgrade can buy the session up
# to ten keys, and the keys past the assignment fire nothing. A body's current
# hands decide which assigned skills are actually drawn: a bow skill waits while
# the sword is out and comes back with the bow. The family starters fill the first
# free keys behind the assigned ones, and the bare-hand charge takes one when the
# hands hold nothing. Medicine is not on this row: the bandage and the potion are
# the body's own two keys (`Z`, `V`).

## The skills this body's bar carries right now, one per key, "" for a key that
## fires nothing. Mirrors the dressing `SeatLoadout` runs, without a rig: a roster
## record may have no body at all (a reserve, a name the scene never spawned) and
## the character screen still has to draw the keys that body would fire.
func hotbar_kit(merc_id: int) -> Array[String]:
	var slots := AbilityRules.SLOT_COUNT
	var out: Array[String] = []
	for _index in slots:
		out.append("")
	var gear := roster.equipped_of(merc_id)
	var main_id := str(gear.get("main", ""))
	var off_id := str(gear.get("off", ""))
	var main_row: Dictionary = State.ITEMS.get(main_id, {})
	var off_row: Dictionary = State.ITEMS.get(off_id, {})
	var seen := {}
	var assigned := roster.hotbar_order_of(merc_id)
	for index in mini(assigned.size(), slots):
		var id := str(assigned[index])
		if id.is_empty() or seen.has(id):
			continue
		var definition := AbilityRules.by_id(id)
		if definition.is_empty() or AbilityRules.is_automatic(id):
			continue
		if not AbilityRules.fits_gear(definition, main_row, off_row):
			continue
		seen[id] = true
		out[index] = id
	# The body's own family starters fill the first free keys. The roster cannot
	# tell an AI seat from the player's, so the page draws every starter its hands
	# earn and the rig decides whether to grant them.
	for id in AbilityRules.starter_ids_for_gear(main_row, off_row):
		if seen.has(id):
			continue
		var free := out.find("")
		if free < 0:
			break
		seen[id] = true
		out[free] = id
	if main_id.is_empty() and not seen.has("charge"):
		var free := out.find("")
		if free >= 0:
			out[free] = "charge"
	return out


## The keys exactly as the HUD draws them: the assigned skills on the keys the
## player gave them, the family starters behind them, "" for a key that fires
## nothing. A run's extra keys are the body's, not the roster's, so this row is
## always the five the game ships with.
func hotbar_layout(merc_id: int) -> Array[String]:
	return hotbar_kit(merc_id)


## Write a body's bar: one entry per key, an empty string for a key that fires
## nothing. Queued ids are validated against the catalog and duplicates are
## dropped, but a rejected entry holds its key open with "" - the position is the
## assignment, and nothing here slides a skill onto a key the player did not
## choose. Caps at `AbilityRules.MAX_SLOT_COUNT`. Answers `{ok, message, order}`.
func set_hotbar_order(merc_id: int, order: Array) -> Dictionary:
	if lent:
		if ask_gear("hotbar_order", [merc_id, order]):
			return {"ok": true, "pending": true, "order": order.duplicate(),
				"message": GEAR_SENT}
		return _lent_refusal({"order": []})
	if not roster.has(merc_id):
		return {"ok": false, "message": "No such mercenary.", "order": []}
	if _gear_locked(merc_id):
		return _locked_refusal(merc_id, {"order": []})
	var laid: Array[String] = []
	for item in order:
		if laid.size() >= AbilityRules.MAX_SLOT_COUNT:
			break
		var id := str(item)
		if id.is_empty():
			laid.append("")
			continue
		if laid.has(id) or AbilityRules.is_automatic(id) \
				or AbilityRules.by_id(id).is_empty():
			laid.append("")
			continue
		laid.append(id)
	while not laid.is_empty() and laid[laid.size() - 1].is_empty():
		laid.resize(laid.size() - 1)
	roster.set_hotbar_order(merc_id, laid)
	# The body in the world is dressed from the record, so its own key row
	# follows the write; a body nobody is inside picks it up at its next spawn.
	armed.emit([merc_id])
	_notify()
	return {"ok": true, "message": "The ability keys are laid out.", "order": laid}


## Put one skill on one key, or empty that key. This is the character screen's
## assignment: the player points at a key and says what fires from it, so the
## answer is positional where `toggle_ability`'s is not. `ability_id` may be ""
## to clear the key. The skill must be the player's unlock and must fit the hands
## the body is holding; an automatic starter is never assignable. Answers
## `{ok, slot, order, message}`.
func set_hotbar_slot(merc_id: int, slot: int, ability_id: String) -> Dictionary:
	if lent:
		if ask_gear("hotbar_slot", [merc_id, slot, ability_id]):
			return {"ok": true, "pending": true, "slot": slot,
				"order": hotbar_layout(merc_id), "message": GEAR_SENT}
		return _lent_refusal({"slot": slot, "order": []})
	if not roster.has(merc_id):
		return {"ok": false, "slot": slot, "order": [],
			"message": "No such mercenary."}
	if _gear_locked(merc_id):
		return _locked_refusal(merc_id, {"slot": slot, "order": []})
	if slot < 0 or slot >= AbilityRules.MAX_SLOT_COUNT:
		return {"ok": false, "slot": slot, "order": [],
			"message": "That is not a hotbar key."}
	var id := str(ability_id)
	if not id.is_empty():
		var definition := AbilityRules.by_id(id)
		if definition.is_empty() or AbilityRules.is_automatic(id):
			return {"ok": false, "slot": slot, "order": [],
				"message": "That skill cannot be assigned."}
		var meta = get_node_or_null("/root/Roguelite")
		if meta != null and meta.has_method("is_ability_unlocked") \
				and not bool(meta.is_ability_unlocked(id)):
			return {"ok": false, "slot": slot, "order": [],
				"message": "%s is not unlocked yet." % str(definition.get("name", id))}
		var gear := roster.equipped_of(merc_id)
		var main_row: Dictionary = State.ITEMS.get(str(gear.get("main", "")), {})
		var off_row: Dictionary = State.ITEMS.get(str(gear.get("off", "")), {})
		if not AbilityRules.fits_gear(definition, main_row, off_row):
			return {"ok": false, "slot": slot, "order": [],
				"message": "Hold a %s to fire %s." % [
					AbilityRules.requirement_label(definition),
					str(definition.get("name", id)).capitalize()]}
	var order := roster.hotbar_order_of(merc_id)
	while order.size() <= slot:
		order.append("")
	order[slot] = id
	var result := set_hotbar_order(merc_id, order)
	if bool(result.get("ok", false)):
		if id.is_empty():
			result["message"] = "Key %d is empty." % (slot + 1)
		else:
			result["message"] = "%s fires from key %d." % [
				str(AbilityRules.by_id(id).get("name", id)).capitalize(), slot + 1]
	return result


## The town desk's three rows: one body of each trade, sold at
## `RecruitCatalog.TOWN_LEVEL` (rung 0 - a twig bow, makeshift steel, bark and
## rags), kit and one rolled skill on the card. Laid out on the first read, kept
## until the next sale, and named around the names the band already carries, so a
## repaint never sells the same body twice and never re-rolls the row under the
## player's cursor. Not saved: a load is a new visit.
func town_board() -> Array[Dictionary]:
	if hire_board.is_empty():
		reroll_town_board()
	# The price is the band's, not the row's: it is read live, so a body sworn in
	# between two visits never leaves the desk quoting the last roster count.
	var cost := hire_cost()
	for row in hire_board:
		row["price"] = cost
	return hire_board

## Lay out three fresh rows on the desk: one of each trade at `TOWN_LEVEL`, named
## around the names the band already carries. Prices are written when the board is
## read (`town_board`).
func reroll_town_board() -> Array[Dictionary]:
	var avoid: Array = []
	for merc in roster.records():
		avoid.append(str(merc.get("name", "")))
	hire_board = Recruits.offers(_board_rng, Recruits.TOWN_LEVEL, avoid)
	return hire_board

## Swear one body off the town desk's board (`town_board`).
##
## The desk sells what a run's recruiter sells - a body already inside the hand
## and the armour the card names, with the one skill it will fire - and nothing
## dresses it afterwards: its kit is locked (`is_gear_locked`), so the gold buys
## exactly what the card says and no piece out of the shared stash. A town oath is
## the band's, not a run's: it takes a deployment place, it may be revived, and a
## lethal blow puts it on its chest like any other name (`roster.is_recruit` stays
## false).
##
## Returns `{ok, merc_id, cost, message}`; a refused hire spends nothing.
func hire(offer: Dictionary) -> Dictionary:
	if lent:
		return _lent_refusal({"merc_id": -1, "cost": 0})
	if offer.is_empty() or str(offer.get("kind", "")) != "hire":
		return {"ok": false, "merc_id": -1, "cost": 0,
			"message": "That is not a body the recruiter is selling."}
	if band_field_count() >= deployment_cap:
		return {"ok": false, "merc_id": -1, "cost": 0,
			"message": "The warband already fields %d. No more can be sworn."
				% int(deployment_cap)}
	var cost := hire_cost()
	if gold() < cost:
		return {"ok": false, "merc_id": -1, "cost": cost,
			"message": "You need %d gold; you have %d." % [cost, gold()]}
	if not spend_gold(cost):
		return {"ok": false, "merc_id": -1, "cost": cost,
			"message": "The purse cannot cover %d gold." % cost}
	var merc_name := str(offer.get("name", "")).strip_edges()
	if merc_name.is_empty():
		merc_name = "Oath"
	var gear: Variant = offer.get("gear", {})
	# A hire takes the field at the desk when there is a place for him.
	var room := field_room() > 0
	var merc_id := roster.create(merc_name, gear if gear is Dictionary else {})
	roster.set_disposition(merc_id,
		str(offer.get("disposition", Contracts.DEFAULT_DISPOSITION)))
	# The one skill the card names, laid exactly as a run's board lays it: a bar
	# of one is what stops `SeatLoadout` handing an AI body every skill its hands
	# happen to fit.
	var skill := str(offer.get("skill", ""))
	roster.set_hotbar_order(merc_id, [skill] if not skill.is_empty() else [])
	# Sold whole, locked whole.
	roster.set_kit_locked(merc_id, true)
	roster.set_reserve(merc_id, not room)
	# The desk brings out three more: the row that was bought is not sold twice.
	reroll_town_board()
	_notify()
	var hands := str(offer.get("hands", "a blade"))
	if cost <= 0:
		return {"ok": true, "merc_id": merc_id, "cost": 0,
			"message": "%s swears to the warband: %s, the oath free."
				% [roster.name_of(merc_id), hands]}
	return {"ok": true, "merc_id": merc_id, "cost": cost,
		"message": "%s swears to the warband for %d gold: %s."
			% [roster.name_of(merc_id), cost, hands]}

func hire_cost() -> int:
	return VendorScript.hire_cost(roster)

## Buy one row off a run's recruiter board (`RecruitCatalog.offer`).
##
## The town desk sells the same body - already inside the kit the card names, with
## the one skill on it - and differs in the two ways that matter: the price is the
## board's own (it rises with the run's level, not with the roster), and the body
## does not spend a deployment place - a recruit is bought *for* the run, so it
## takes the field however full the band is, and it never rolls into the reserve.
## It also dies for good (see `dismiss_recruit` and `WarbandBody.permadeath`),
## where a town oath goes down on its chest.
##
## Returns `{ok, merc_id, price, message}`; a refused hire spends nothing.
func hire_recruit(offer: Dictionary) -> Dictionary:
	if lent:
		return _lent_refusal({"merc_id": -1, "price": 0})
	if offer.is_empty() or str(offer.get("kind", "")) != "hire":
		return {"ok": false, "merc_id": -1, "price": 0,
			"message": "That is not a body the recruiter is selling."}
	var price := maxi(0, int(offer.get("price", 0)))
	if gold() < price:
		return {"ok": false, "merc_id": -1, "price": price,
			"message": "The recruiter wants %d gold; the purse holds %d." % [price, gold()]}
	if not spend_gold(price):
		return {"ok": false, "merc_id": -1, "price": price,
			"message": "The purse cannot cover %d gold." % price}
	var merc_name := str(offer.get("name", "")).strip_edges()
	if merc_name.is_empty():
		merc_name = "Recruit"
	var gear: Variant = offer.get("gear", {})
	var merc_id := roster.create(merc_name, gear if gear is Dictionary else {})
	roster.set_recruit(merc_id, true)
	# Sold whole, locked whole: `is_recruit` already answers the lock, and the
	# record carries it outright for the save and the wire.
	roster.set_kit_locked(merc_id, true)
	roster.set_disposition(merc_id, str(offer.get("disposition", "melee")))
	# The one skill the card names: a non-empty bar is what keeps an AI body from
	# being handed every skill its hands happen to fit (`SeatLoadout.apply`).
	var skill := str(offer.get("skill", ""))
	roster.set_hotbar_order(merc_id, [skill] if not skill.is_empty() else [])
	# Bought for the field, not for the reserve: a recruit that waited behind the
	# deployment cap would never fight.
	roster.set_reserve(merc_id, false)
	_notify()
	return {"ok": true, "merc_id": merc_id, "price": price,
		"message": "%s swears on: %s, %d gold." % [roster.name_of(merc_id),
			str(offer.get("hands", "a blade")), price]}

## Whether this body's kit was bought whole with it and is never changed. The town
## desk and a run's board both sell a body already inside the hand and the armour
## on the card (`WarbandRoster.KEY_KIT_LOCK`), so every verb that would move a
## worn slot or the bar refuses it: no paperdoll press, no loot pickup, no re-kit,
## no weapon-set swap, no new skill, no new stance. The way to a better-armed body
## is a better-armed hire.
func is_gear_locked(merc_id: int) -> bool:
	return roster.is_kit_locked(merc_id)

## Pay a bought recruit off: the name leaves the warband and the run's board is the
## only place a hired body may be dismissed from (a sworn mercenary is the band's,
## and only a reap or the town's desk changes that).
##
## The kit goes with him. It was sold *with* the body and locked to it
## (`is_gear_locked`), so a dismissal that handed the steel into the shared stash
## would be a way to buy a recruit's gear for a recruit's price and keep the piece.
## Returns `{ok, merc_id, message}`; a body that may not be dismissed spends
## nothing and leaves nothing.
func dismiss_recruit(merc_id: int) -> Dictionary:
	if lent:
		return _lent_refusal({"merc_id": merc_id})
	if not roster.has(merc_id):
		return {"ok": false, "merc_id": merc_id, "message": "No such body."}
	if not roster.is_recruit(merc_id):
		return {"ok": false, "merc_id": merc_id,
			"message": "%s is sworn to the band: only a bought recruit can be paid off." \
				% roster.name_of(merc_id)}
	var merc_name := roster.name_of(merc_id)
	roster.remove(merc_id)
	_notify()
	return {"ok": true, "merc_id": merc_id,
		"message": "%s is paid off and gone, kit and all." % merc_name}

## Equip a mercenary from the collective stash. The stash is one pool, so a
## piece another mercenary is already wearing is a *transfer*, not a refusal:
## the wearer is stripped and the piece walks across. Without that rule the only
## dagger in a fresh warband could never be handed from the rescuer to a
## prisoner, which is exactly what the first scene asks the player to do.
## `announce` false lets a caller that is fitting several pieces in one pass
## (`arm_warband`, `dress_recruit`) emit a single `changed` instead of one per
## slot; the caller then owns the notify. `manual` says whose hand did it: the
## player's (the default, and every paperdoll press) pins the slot so no automatic
## arming touches it again and lets the equip take a worn copy off another body,
## while the band's own passes pass false - they never pin, and they never reach
## into a slot the player pinned.
func equip_merc(merc_id: int, slot_id: String, item_id: String,
		announce: bool = true, manual: bool = true) -> Dictionary:
	if lent:
		if ask_gear("equip", [merc_id, slot_id, item_id]):
			return {"ok": true, "pending": true, "displaced": {}, "message": GEAR_SENT}
		return _lent_refusal({"displaced": {}})
	if _gear_locked(merc_id):
		return _locked_refusal(merc_id, {"displaced": {}})
	if item_id.is_empty():
		return {"ok": false, "message": "Choose a piece of gear.", "displaced": {}}
	var pool := field_stash()
	var gear := roster.equipped_of(merc_id)
	if str(gear.get(slot_id, "")) == item_id:
		# The piece is already there; a hand on it still makes the slot the
		# player's, which is the whole point of the second press.
		if manual:
			roster.set_manual(merc_id, slot_id, true)
			if announce:
				_notify()
		return {"ok": true, "message": "%s is already worn there." % roster.name_of(merc_id),
			"displaced": {}}
	var was_wearing := str(gear.get(slot_id, ""))
	var moved_from := ""
	var moved_serial := -1
	var forever := _forever_gear(item_id)
	if pool.pooled_count(item_id) <= 0 and not forever:
		var taken := _strip_worn(item_id, pool, manual)
		if not bool(taken.get("ok", false)):
			return {"ok": false, "message": "You do not own that piece yet.", "displaced": {}}
		moved_from = str(taken.get("from", ""))
		# The stripped copy comes with the serial it was worn under.
		moved_serial = int(taken.get("serial", -1))
	var result := roster.equip(merc_id, slot_id, item_id)
	if not bool(result.get("ok", false)):
		# Put the stripped piece back where it came from: a refused equip must
		# not quietly pocket somebody else's gear.
		if not moved_from.is_empty():
			pool.remove(item_id, 1, moved_serial)
		return result
	var displaced: Dictionary = result.get("displaced", {})
	if moved_serial < 0:
		# A copy off the shelf: take the first free one, by its own serial.
		var serials: Array = pool.serials_of(item_id)
		if not serials.is_empty():
			moved_serial = int(serials[0])
		elif forever:
			# The player's ledger is the ownership of an opened piece, so a body
			# is armed with it wherever another body already carries one: the copy
			# is minted as this body takes it up and leaves the pool with the body.
			# Nothing lingers, and a looted copy is still a copy - `_strip_worn`
			# above is the only way it moves between hands.
			moved_serial = pool.mint_serial(item_id)
	# Nothing pooled answers false harmlessly: an unlocked piece was minted, not
	# taken off a shelf.
	pool.remove(item_id, 1, moved_serial)
	# The copy this body was wearing in that slot, if any, goes back to the pool
	# as itself.
	var let_go := _release_copy(merc_id, slot_id, was_wearing)
	if not let_go.is_empty():
		pool.add(str(let_go.get("item", "")), 1, int(let_go.get("serial", -1)))
	elif not was_wearing.is_empty():
		# A copy that was worn before copies had serials (a dress that never
		# claimed one): the piece itself still comes back to the pool.
		pool.add(was_wearing, 1)
	worn_copies["%d:%s" % [merc_id, slot_id]] = {"item": item_id,
		"ordinal": moved_serial}
	for slot in displaced:
		# The piece that came off is the pool's again, so the slot it left is the
		# arming's: a two-hander taking the off hand is not a pinned empty hand.
		roster.set_manual(merc_id, str(slot), false)
		# The slot being equipped was released above; releasing it twice would hand
		# the newly worn copy straight back to the pool.
		if str(slot) == slot_id:
			continue
		var old_id := str(displaced[slot])
		if old_id.is_empty():
			continue
		var off := _release_copy(merc_id, slot, old_id)
		if off.is_empty():
			pool.add(old_id, 1)
		else:
			pool.add(str(off.get("item", old_id)), 1, int(off.get("serial", -1)))
	# Whose the slot is. A hand on the paperdoll makes it the player's; the band's
	# own passes leave the question exactly as they found it. (The slot a piece was
	# stripped out of unpins itself inside `WarbandRoster.take_worn`.)
	if manual:
		roster.set_manual(merc_id, slot_id, true)
	if not moved_from.is_empty():
		result["message"] = "%s taken from %s." % [str(result.get("message", "")), moved_from]
	if announce:
		_notify()
	return result

## Wear one piece in the hand the run carries it in. The inventory's two weapon
## sets are the run's two hands: `"ranged"` is set 1 and `"melee"` set 2. The
## piece comes out of the shared pool - or off whichever body already wears it -
## exactly as a paperdoll press does, so a body can never carry a weapon the
## inventory does not own. The pair the player had in hand is put back afterwards;
## only the set that was bound is changed.
func equip_hand(merc_id: int, hand: String, item_id: String) -> Dictionary:
	if hand != "ranged" and hand != "melee":
		return {"ok": false, "message": "That is not a hand.", "displaced": {}}
	if roster.find(merc_id).is_empty():
		return {"ok": false, "message": "No such mercenary.", "displaced": {}}
	if lent:
		if ask_gear("hand", [merc_id, hand, item_id]):
			return {"ok": true, "pending": true, "displaced": {}, "message": GEAR_SENT}
		return _lent_refusal({"displaced": {}})
	var target := 0 if hand == "ranged" else 1
	var active := roster.active_weapon_set(merc_id)
	roster.select_weapon_set(merc_id, target)
	var result: Dictionary = equip_merc(merc_id, "main", item_id, false)
	if active != target:
		roster.select_weapon_set(merc_id, active)
	# One notify for the whole hand-over: the equip's own would have shown the
	# other set's hands for a frame, and the pair the player wears is the truth.
	_notify()
	if bool(result.get("ok", false)):
		result["message"] = "%s takes the %s hand." % [
			str(State.ITEMS.get(item_id, {}).get("name", item_id)), hand]
	return result

## Forge a piece into the shared stash with no purse and no roll: the rack hands
## over a weapon its keys have just opened. Nothing is minted twice - a warband
## that already owns the piece gets no second copy - so the inventory stays the
## one place a carried weapon can come from.
func grant_gear(item_id: String, count: int = 1) -> Dictionary:
	var id := State.migrate_item_id(item_id)
	if lent:
		if ask_gear("grant", [id, count]):
			return {"ok": true, "pending": true, "item_id": id,
				"count": count, "message": GEAR_SENT}
		return _lent_refusal({"item_id": id, "count": 0})
	if not State.ITEMS.has(id):
		return {"ok": false, "item_id": id, "count": 0,
			"message": "That piece is not in the catalog."}
	var display := str((State.ITEMS[id] as Dictionary).get("name", id))
	if stash.owns(id, roster):
		return {"ok": true, "item_id": id, "count": 0,
			"message": "%s is already in the warband's hands." % display}
	stash.add(id, maxi(1, count))
	_notify()
	return {"ok": true, "item_id": id, "count": maxi(1, count),
		"message": "%s is in the shared stash." % display}

## Take one worn copy of `item_id` off whichever mercenary holds it and drop it
## into `pool`. Returns `{ok, from, serial}` where `from` names the mercenary. Only
## a body whose gear may move right now is searched
## (`dressable_ids`): below, a piece is handed between the party's own and never
## fetched out of the town.
##
## Both weapon sets are searched, not just the hands: a piece waiting in the set
## the body is not carrying is still the warband's to hand over. A slot the player
## dressed by hand is not, though - `allow_manual` is true only for the player's
## own press (the paperdoll moving a piece to another body), so an automatic pass
## can never carry a chosen weapon out of the hands it was put into.
func _strip_worn(item_id: String, pool: WarbandStash, allow_manual: bool = true) -> Dictionary:
	var reachable := dressable_ids()
	for entry in _worn_entries_all():
		if str(entry.get("item", "")) != item_id:
			continue
		var merc_id := int(entry.get("merc", 0))
		if not reachable.has(merc_id):
			continue
		var slot_id := str(entry.get("slot", ""))
		if not allow_manual and roster.is_manual(merc_id, slot_id):
			continue
		var label := "%s (%s)" % [roster.name_of(merc_id), Contracts.slot_id_label(slot_id)]
		if roster.take_worn(merc_id, slot_id, int(entry.get("set", -1))) != item_id:
			continue
		# The copy leaves the body with the serial it was wearing: a relic handed
		# from one body to another is still the same weapon.
		var let_go := _release_copy(merc_id, slot_id, item_id)
		var serial := int(let_go.get("serial", -1))
		pool.add(item_id, 1, serial)
		return {"ok": true, "from": label, "serial": serial}
	return {"ok": false, "from": ""}

## Whether this piece is the player's forever, whatever the bodies are wearing:
## a weapon the rack's keys have opened (`Roguelite.is_unlocked`). The ledger is
## the ownership, so any body may be armed with it and no spare has to sit in the
## shared stash for it to be worn twice.
func _forever_gear(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	var meta = get_node_or_null("/root/Roguelite")
	if meta == null or not meta.has_method("is_unlocked"):
		return false
	return bool(meta.is_unlocked(item_id))

## Every worn piece in the warband, both weapon sets included, as `{merc, slot,
## item, set}` records.
func _worn_entries_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for merc in roster.records():
		var merc_id := int(merc.get("id", 0))
		for entry in roster.worn_entries(merc_id):
			var row := entry.duplicate()
			row["merc"] = merc_id
			out.append(row)
	return out

# --- copies ----------------------------------------------------------------

## Let go of the copy `merc_id` wears in `slot_id` when that claim names this very
## piece, and answer the serial to put it back under. `-1` when the slot holds no
## claim of its own - a slot dressed behind the state's back, a claim left by the
## other weapon set, a piece waiting in the set the hands are not carrying - so
## the caller mints a copy instead of handing over another weapon's identity.
func _release_claim(merc_id: int, slot_id: String, item_id: String) -> int:
	var key := "%d:%s" % [merc_id, slot_id]
	var held: Variant = worn_copies.get(key, {})
	if not held is Dictionary:
		return -1
	if str((held as Dictionary).get("item", "")) != item_id:
		# A claim that names another piece is stale: the slot changed hands by a
		# route that kept no record (a weapon-set swap). Drop it rather than let
		# it name this piece again on the next take.
		worn_copies.erase(key)
		return -1
	worn_copies.erase(key)
	return int((held as Dictionary).get("ordinal", -1))

## A copy leaving a body: the slot forgets it and the caller gets the piece and
## the serial it was worn under, so a weapon handed between bodies is still the
## same weapon. The caller puts it back; this only lets go. `item_id` is the piece
## the slot actually held - the claim has to name it, or the slot was dressed
## behind the record's back and the answer is no claim at all.
func _release_copy(merc_id: int, slot_id: String, item_id: String) -> Dictionary:
	var key := "%d:%s" % [merc_id, slot_id]
	var held: Variant = worn_copies.get(key, {})
	if not held is Dictionary:
		worn_copies.erase(key)
		return {}
	if str((held as Dictionary).get("item", "")) != item_id:
		worn_copies.erase(key)
		return {}
	worn_copies.erase(key)
	if item_id.is_empty():
		return {}
	return {"item": item_id, "serial": int((held as Dictionary).get("ordinal", -1))}

## Whether a body's hands already hold something to fight with - the one question
## the loot arming asks before it touches anything. A stowed weapon in the other
## weapon set is not in hand and does not count, and the naked coverings are not
## steel, so a body born in rags is still bare.
func hands_armed(merc_id: int) -> bool:
	var gear := roster.equipped_of(merc_id)
	for slot_id in RosterScript.HAND_SLOTS:
		var item_id := str(gear.get(slot_id, ""))
		if item_id.is_empty() or EquipmentRules.bare_garment(item_id):
			continue
		return true
	return false

## The piece a loot pickup should snap into the soul's hands - and the one arming
## the player never has to take back.
##
## It only ever *fills* a bare body. A member whose hands already hold something
## is not auto-armed at all, so no pickup can swap a weapon under the player (or
## a squadmate) in the middle of a fight: a spare blade waits in the stash until a
## hand on the character screen puts it on. For the same reason the target slot
## must be empty or hold the naked set, and never one the player filled by hand
## (`WarbandRoster.is_manual`). A piece the body's trade refuses is not taken at
## all, even into an empty hand (`Contracts.disposition_refuses_gear`: a bow to a
## blade). Anything else stays in the stash. Returns
## `{ok, slot, displaced, message}`.
func auto_equip(merc_id: int, item_id: String) -> Dictionary:
	if lent:
		return _lent_refusal({"slot": ""})
	if _gear_locked(merc_id):
		return _locked_refusal(merc_id, {"slot": ""})
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty() or merc_id <= 0:
		return {"ok": false, "message": "", "slot": ""}
	if not str(item.get("category", "")) in EQUIPPABLE_CATEGORIES:
		return {"ok": false, "message": "", "slot": ""}
	if not roster.is_alive(merc_id):
		return {"ok": false, "message": "", "slot": ""}
	var disposition := roster.disposition_of(merc_id)
	# A piece this body's trade never carries is not a pickup it can use: a melee
	# body does not take a bow into a hand the blade will fill later. It stays a
	# pool row.
	if Contracts.disposition_refuses_gear(disposition, item):
		return {"ok": false, "message": "", "slot": ""}
	# Armed hands are the player's hands, however they were filled.
	if hands_armed(merc_id):
		return {"ok": false, "message": "", "slot": ""}
	var gear := roster.equipped_of(merc_id)
	var slot_id := EquipmentRules.auto_slot(item, gear)
	if slot_id.is_empty():
		return {"ok": false, "message": "", "slot": ""}
	if roster.is_manual(merc_id, slot_id):
		return {"ok": false, "message": "", "slot": slot_id}
	var worn := str(gear.get(slot_id, ""))
	if not worn.is_empty() and not EquipmentRules.bare_garment(worn):
		return {"ok": false, "message": "", "slot": slot_id}
	var result := equip_merc(merc_id, slot_id, item_id, true, false)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": str(result.get("message", "")), "slot": slot_id}
	return {"ok": true, "slot": slot_id, "message": str(result.get("message", "")),
		"displaced": result.get("displaced", {})}

## Strip a worn piece back into the pool the field works.
func unequip_merc(merc_id: int, slot_id: String) -> String:
	if lent:
		if ask_gear("unequip", [merc_id, slot_id]):
			# The piece the row is showing: the host takes it off, and the mirror
			# that comes back has it in the pool.
			return str(roster.equipped_of(merc_id).get(slot_id, ""))
		return ""
	if _gear_locked(merc_id):
		return ""
	var item_id := roster.unequip(merc_id, slot_id)
	if item_id.is_empty():
		return ""
	# The copy comes off the body as itself: its serial returns with the piece.
	var off := _release_copy(merc_id, slot_id, item_id)
	field_stash().add(item_id, 1, int(off.get("serial", -1)))
	_notify()
	return item_id

## `TAB` in the world: the standing body puts away the weapon set in its hands
## and takes up the other one, exactly as the frontier's own swap does. The two
## pairs live on the roster record, so the swap is warband state - it survives a
## body hop, a reload and a scene hand-off - and the scene re-dresses the rig from
## it with `refresh_gear()`.
func swap_weapon_set(merc_id: int) -> Dictionary:
	if lent:
		if ask_gear("swap_set", [merc_id]):
			return {"ok": true, "pending": true,
				"set": int(roster.active_weapon_set(merc_id)), "message": GEAR_SENT}
		return _lent_refusal({"set": 0})
	if _gear_locked(merc_id):
		return _locked_refusal(merc_id, {"set": int(roster.active_weapon_set(merc_id))})
	var result := roster.swap_weapon_set(merc_id)
	_notify()
	return result

## What one mercenary's kit is worth. Both weapon sets count: stowing a sword in
## the set the hands are not carrying does not make it leave the warband.
func gear_value(merc_id: int) -> int:
	var total := 0
	for entry in roster.worn_entries(merc_id):
		var item_id := str(entry.get("item", ""))
		if not item_id.is_empty():
			total += WarbandStash.value_of(item_id)
	return total

## The warband's combined worth - gear and the town stash - for the HUD and tests.
func total_value() -> int:
	var total := 0
	for entry in _worn_entries_all():
		var item_id := str(entry.get("item", ""))
		if not item_id.is_empty():
			total += WarbandStash.value_of(item_id)
	total += _pool_value(stash)
	return total

func _pool_value(pool: WarbandStash) -> int:
	var total := 0
	var pooled := pool.pooled_map()
	for item_id in pooled:
		total += WarbandStash.value_of(str(item_id)) * int(pooled[item_id])
	return total

# --- the party's mode ------------------------------------------------------

## What a guest is told when it reaches for the party's mode: the squad it would
## command runs on the host.
const LENT_PARTY_MESSAGE := "This is the host's warband: only the host sets how the party fights."

## Put the party in `mode`. Returns `{ok, mode, message}`, `mode` being the one the
## party is in afterwards. An unknown mode is refused, and so is a lent warband's:
## the squad that would obey it is the host's. Only a real change is announced.
func set_party_mode(mode: String) -> Dictionary:
	if lent:
		return {"ok": false, "mode": party_mode, "message": LENT_PARTY_MESSAGE}
	if not Contracts.PARTY_MODES.has(mode):
		return {"ok": false, "mode": party_mode,
			"message": "The party has no %s mode." % mode.to_upper()}
	if mode != party_mode:
		party_mode = mode
		_notify()
	return {"ok": true, "mode": party_mode, "message": "The party is %s." % mode.to_upper()}

## Step the party to the next mode in `Contracts.PARTY_MODES` order - OFFENSIVE,
## DEFENSIVE, PASSIVE, and round again - which is what the world's `B` key does.
## The same answer and the same refusals as `set_party_mode`.
func cycle_party_mode() -> Dictionary:
	var index := Contracts.PARTY_MODES.find(party_mode)
	return set_party_mode(Contracts.PARTY_MODES[(index + 1) % Contracts.PARTY_MODES.size()])

# --- a party member's disposition ------------------------------------------

## What a guest is told when it reaches for a body's disposition: the squad it
## would command runs on the host.
const LENT_DISPOSITION_MESSAGE := "This is the host's warband: only the host says how its bodies fight."

## Give one mercenary a disposition (`Contracts.DISPOSITIONS`). The party's mode
## says which fights the squad takes; this says how this body takes them, and it
## is per record - saved with the roster and lent with it, so a guest reads the
## host's band. Returns `{ok, disposition, message}` with the body's disposition
## afterwards: an unknown word is refused, and so is a lent warband's, because the
## squad that would obey it is the host's. Only a real change is announced.
##
## A real change can leave a piece in a hand the new stance never carries - the
## band dressed a body as a melee body with the greatsword, and the player has
## just made it the front line. Those pieces go back into the pool and the hands
## are filled again by the same choice an arming pass makes
## (`_release_refused_hands`), so a TANK reads as a shield and a one-hander the
## moment the chip is pressed. A blade a bowman carries is not refused (the bow's
## trade falls back on it), and a piece the player lays in by hand after the
## change is theirs - this runs on the change itself.
func set_disposition(merc_id: int, disposition: String) -> Dictionary:
	var now := roster.disposition_of(merc_id) if roster.has(merc_id) else Contracts.DEFAULT_DISPOSITION
	if lent:
		return _lent_refusal({"disposition": now, "message": LENT_DISPOSITION_MESSAGE})
	if not roster.has(merc_id):
		return {"ok": false, "disposition": now, "message": "No such mercenary."}
	if _gear_locked(merc_id):
		return _locked_refusal(merc_id, {"disposition": now})
	var wanted := Contracts.disposition_exact(disposition)
	if wanted.is_empty():
		return {"ok": false, "disposition": now,
			"message": "%s is not a disposition." % str(disposition).to_upper()}
	roster.set_disposition(merc_id, wanted)
	if wanted != now:
		var refitted := _release_refused_hands(merc_id, wanted)
		_notify()
		if not refitted.is_empty():
			armed.emit([merc_id])
	return {"ok": true, "disposition": wanted,
		"message": "%s fights as %s." % [roster.name_of(merc_id),
			Contracts.disposition_label(wanted)]}

## Take the pieces the new stance refuses out of a body's hands and fill those
## hands again from the pool. A weight would only make a greatsword expensive; a
## refusal is what the arming enforces, and a body that becomes a tank while
## holding one would carry it to the field with the shield it costs already in
## the stash. Only refused pieces move - a bowman's blade is not refused - and
## nothing moves for a body that is down, below with the party, or in a lent
## warband. Answers the ids that went back into the pool.
func _release_refused_hands(merc_id: int, disposition: String) -> Array[String]:
	var released: Array[String] = []
	if lent or not roster.is_alive(merc_id):
		return released
	for slot_id in ["main", "off"]:
		var item_id := str(roster.equipped_of(merc_id).get(slot_id, ""))
		if item_id.is_empty() or EquipmentRules.bare_garment(item_id):
			continue
		var item: Dictionary = State.ITEMS.get(item_id, {})
		if item.is_empty() or not Contracts.disposition_refuses_gear(disposition, item):
			continue
		if roster.unequip(merc_id, slot_id).is_empty():
			continue
		field_stash().add(item_id, 1, _release_claim(merc_id, slot_id, item_id))
		released.append(item_id)
	if not released.is_empty():
		_fill_slots(merc_id, ["main", "off"])
	return released

## Step one body to the next disposition in `Contracts.DISPOSITIONS` order -
## what a press on the roster's chip does. TANK, MELEE, BOW and round again.
func cycle_disposition(merc_id: int) -> Dictionary:
	return set_disposition(merc_id, Contracts.next_disposition(roster.disposition_of(merc_id)))

# --- possession bookkeeping ------------------------------------------------

## Mirror a router decision into the persistent map.
func note_possession(peer_id: int, merc_id: int) -> void:
	if merc_id <= 0:
		possession.erase(peer_id)
	else:
		possession[peer_id] = merc_id
	_notify()

func possessed_by(peer_id: int) -> int:
	return int(possession.get(peer_id, -1))

func possessed_ids() -> Dictionary:
	return possession.duplicate()

func clear_possession() -> void:
	possession.clear()
	revive_channels.clear()
	souls.clear()
	_notify()

# --- reset -----------------------------------------------------------------

func reset_state(cap: int = Contracts.MAX_DEPLOYMENT_CAP) -> void:
	# A reset is a fresh warband of this machine's own, never a host's.
	lent = false
	_lent_gold = 0
	gear_requester = Callable()
	_arming = false
	roster.clear()
	stash.clear()
	supplies = {"bandage": 0, "potion": 0}
	worn_copies.clear()
	souls.clear()
	deployment_cap = maxi(1, cap)
	seeded = false
	possession.clear()
	revive_channels.clear()
	checkpoint.clear()
	party_mode = Contracts.DEFAULT_PARTY_MODE
	# A fresh warband meets a fresh desk: nothing the last campaign was sold is
	# for sale here.
	hire_board.clear()
	_board_rng.randomize()
	_notify()

func _notify() -> void:
	changed.emit()

# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"deployment_cap": deployment_cap,
		"roster": roster.to_dict(),
		"stash": stash.to_dict(),
		"worn_copies": worn_copies.duplicate(true),
		"checkpoint": checkpoint.duplicate(true),
		"party_mode": party_mode,
		"supplies": supplies.duplicate(),
	}

func from_dict(data: Dictionary) -> void:
	roster.from_dict(data.get("roster", {}))
	stash.from_dict(data.get("stash", {}))
	worn_copies.clear()
	var saved_copies: Variant = data.get("worn_copies", {})
	if saved_copies is Dictionary:
		for key in saved_copies:
			var held: Variant = saved_copies[key]
			if held is Dictionary:
				worn_copies[str(key)] = {"item": str((held as Dictionary).get("item", "")),
					"ordinal": int((held as Dictionary).get("ordinal", 0))}
	# The holds are item ids, not rows in a pool, so they outlive a copy moving
	# between the stash, a body and the delve inventory. A v9 file has none.
	# A file written before the keepers sold medicine carries none: an empty pack
	# is the honest reading, never a full one.
	supplies = {"bandage": 0, "potion": 0}
	var saved_supplies: Variant = data.get("supplies", {})
	if saved_supplies is Dictionary:
		for kind in saved_supplies:
			supplies[str(kind)] = maxi(0, int((saved_supplies as Dictionary)[kind]))
	# Read before the dead are reaped below: a member still on the books of a party
	# below is reaped into the delve inventory, which the load's fall then loses,
	# never into the stash. A v7 file has no delve at all.
	deployment_cap = clampi(int(data.get("deployment_cap", Contracts.MAX_DEPLOYMENT_CAP)),
		1, Contracts.MAX_DEPLOYMENT_CAP)
	# A v3 file has no checkpoint: it resumes at the town, which is what every
	# save written before autosave existed meant.
	checkpoint = sanitise_checkpoint(data.get("checkpoint", {}))
	# A v8 file has no party mode: the squad fights defensive, the band's own
	# answer, and so does a mode this build has never heard of.
	var mode := str(data.get("party_mode", Contracts.DEFAULT_PARTY_MODE))
	party_mode = mode if Contracts.PARTY_MODES.has(mode) else Contracts.DEFAULT_PARTY_MODE
	# A file written before the dead left the books still carries their records.
	# They leave now, and whatever they wore joins the stash that was just read:
	# opening an old warband must free the hire cap, not inherit a graveyard.
	reap_dead()
	# The field fits the cap on every load. A lent copy is the host's books as the
	# host keeps them, never rebalanced here, so both machines field one squad.
	if not lent:
		_balance_field()
	# Nothing is ever paid here: the purse and the essence wallet already hold
	# what a run earned, so a save/load cycle cannot pay one twice.
	seeded = roster.count() > 0
	# The desk is not part of the books: a load is a new visit to the square, and
	# the board it lays out is rolled on the next read.
	hire_board.clear()
	_notify()

## `GameFlow.goto()` and every scene's `_exit_tree()` call this, so the file is
## written with the roster as the world last mirrored it.
func save_state() -> void:
	# A lent warband is the host's: writing it here would put somebody else's
	# campaign over this machine's own save.
	if lent:
		return
	if not SaveFileScript.write(save_path, to_dict()):
		push_warning("Warband: cannot write %s" % save_path)

func load_state() -> bool:
	# Reading this machine's file into a lent warband would swap the host's
	# campaign for the guest's in the middle of a session.
	if lent:
		return false
	var opened: Dictionary = SaveFileScript.inspect(save_path)
	if not bool(opened.get("ok", false)):
		_note_refusal(str(opened.get("problem", "")))
		return false
	var parsed: Dictionary = opened.get("data", {})
	if int(parsed.get("version", 0)) > SAVE_VERSION:
		push_warning("Warband: %s is from a newer build" % save_path)
		return false
	var version := int(parsed.get("version", 0))
	from_dict(parsed)
	# Before v18 the hotbar was a reordering of skills anointed onto steel. The
	# anoint grant is gone; a clean cutover empties those lists rather than
	# silently equipping old welds as if the player had unlocked them.
	if version < 18:
		for merc_id in roster.ids():
			roster.set_hotbar_order(int(merc_id), [])
	return true

## One line for a save this build will not open. A missing file is silent - a
## fresh machine has none, and that is not a problem - while a sealed file whose
## bytes no longer match its own tag says so: it changed outside the game.
func _note_refusal(problem: String) -> void:
	if problem.is_empty() or problem == "missing":
		return
	push_warning("Warband: %s will not open (%s)" % [save_path, problem])
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("warband", "save_refused", {"path": save_path, "problem": problem})

## What a warband file holds, read without adopting it: `{exists, roster,
## checkpoint}`. The title says what HOST GAME's checkpoint door would open with
## this, and must not load a save into the live warband just to describe one.
static func peek_save(path: String) -> Dictionary:
	var out := {"exists": false, "roster": 0, "checkpoint": {}}
	if path.is_empty() or not SaveFileScript.exists(path):
		return out
	out["exists"] = true
	var opened: Dictionary = SaveFileScript.inspect(path)
	if not bool(opened.get("ok", false)):
		return out
	var parsed: Dictionary = opened.get("data", {})
	var roster_data: Variant = parsed.get("roster", {})
	if roster_data is Dictionary and (roster_data as Dictionary).get("mercenaries", []) is Array:
		out["roster"] = ((roster_data as Dictionary)["mercenaries"] as Array).size()
	out["checkpoint"] = sanitise_checkpoint(parsed.get("checkpoint", {}))
	return out

# --- checkpoints (the autosave bookmark) ------------------------------------
#
# A checkpoint is the campaign's own memory of "how far we got", written at the
# moments that begin a new stretch: the camp's six watchers down with the squad
# on the road (`trail_start`), and the town square entered (`town`). It rides in
# the same `warband_state.json` as everything else, so one file is one truthful
# picture - a wiped run loads the roster, stash and essence as they stood there
# and puts the warband back on that ground. A v3 file has no checkpoint and
# resumes at the town, exactly as it did before.

func has_checkpoint() -> bool:
	return not checkpoint.is_empty()

func checkpoint_id() -> String:
	return str(checkpoint.get("id", ""))

## `"trail"` or `"town"`, or `""` when there is no bookmark.
func checkpoint_area() -> String:
	return str(checkpoint.get("area", ""))

func checkpoint_label() -> String:
	return str(checkpoint.get("label", ""))

## The ground the bookmark was taken on. Zero when there is none; callers that
## need a standable point snap it to the terrain.
func checkpoint_position() -> Vector3:
	return checkpoint_vector(checkpoint)

## The moment the bookmark was taken, as a unix stamp.
func checkpoint_at() -> int:
	return int(checkpoint.get("at", 0))

## Write a checkpoint and the whole warband with it. The warband is saved at the
## same time on purpose: a bookmark that points at a state the file has never
## held is a lie the reload cannot honour. Returns the stored record.
func save_checkpoint(id: String, area: String, position: Vector3, label: String = "") -> Dictionary:
	var wanted_id := id.strip_edges()
	var wanted_area := area if CHECKPOINT_AREAS.has(area) else "town"
	if wanted_id.is_empty():
		wanted_id = wanted_area
	checkpoint = {
		"id": wanted_id,
		"area": wanted_area,
		"position": [position.x, position.y, position.z],
		"label": label,
		"at": int(Time.get_unix_time_from_system()),
	}
	save_state()
	_notify()
	return checkpoint.duplicate(true)

func clear_checkpoint() -> void:
	if checkpoint.is_empty():
		return
	checkpoint.clear()
	_notify()

## How many bodies the bookmark can put on the field. A checkpoint whose whole
## squad is dead is not a checkpoint: the wipe path must not loop on it.
func checkpoint_standing() -> int:
	var count := 0
	for merc_id in roster.ids():
		if roster.state_of(merc_id) != Contracts.HealthState.DEAD:
			count += 1
	return count

## The same check a reader gets out of the file: malformed data is dropped, never
## half-read. Static because a save's checkpoint is untrusted input.
static func sanitise_checkpoint(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var record: Dictionary = data
	var id := str(record.get("id", "")).strip_edges()
	var area := str(record.get("area", ""))
	if id.is_empty() or not CHECKPOINT_AREAS.has(area):
		return {}
	if not is_standable(record.get("position", null)):
		return {}
	var point := checkpoint_vector(record)
	return {
		"id": id,
		"area": area,
		"position": [point.x, point.y, point.z],
		"label": str(record.get("label", "")),
		"at": int(record.get("at", 0)),
	}

## A checkpoint's position, read from a record or from the live field.
static func checkpoint_vector(record: Dictionary) -> Vector3:
	var value: Variant = record.get("position", [])
	if not (value is Array) or (value as Array).size() != 3:
		return Vector3.ZERO
	var values: Array = value
	for index in 3:
		if typeof(values[index]) not in [TYPE_INT, TYPE_FLOAT]:
			return Vector3.ZERO
	var point := Vector3(float(values[0]), float(values[1]), float(values[2]))
	return point if point.is_finite() else Vector3.ZERO

static func is_standable(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 3:
		return false
	for entry in value as Array:
		if typeof(entry) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(entry)):
			return false
	return true

## One line for the log card and for tests.
func describe() -> String:
	return "mercs=%d alive=%d cap=%d gold=%d stash=%d checkpoint=%s" % [
		roster.count(), roster.alive_count(), deployment_cap,
		gold(), stash.pooled_total(),
		checkpoint_id() if has_checkpoint() else "-"]
