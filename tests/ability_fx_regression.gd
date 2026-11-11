extends SceneTree
## Every ability's art and every proc's consequence.
##
## Two contracts, both player-visible and both cheap to break silently:
##
##   * **One icon per skill.** The bar draws `AbilityRules.icon_texture`, which
##     answers null for a row with no file, and the tile then falls back to an
##     acronym. A shipped skill therefore cannot be allowed to point at a missing
##     file, and no two skills may share one: two different keys with the same
##     picture is a player pressing the wrong one. The two consumables are in the
##     table too - they are rows of the same bar.
##   * **One visual signature per skill, and one consequence per proc.** A cue
##     with no signature is a skill that plays a sound and nothing else; a proc
##     with no effect is a number that moves with no reason. This walks the real
##     catalog, calls the real entry points against a bare rig, and insists every
##     one of them draws something. It also lets the whole set of one-shots run
##     their clocks out and asserts they clean up, because a visual that never
##     frees is a leak the frame budget only finds later.
##
## The bands are deliberately loose: this asserts "there is art, it is unique, it
## arrives and it leaves", not a pixel layout. Art direction is judged by eye, in
## the game, not here.

const AbilityRules = preload("res://scripts/ability_rules.gd")
const Signatures = preload("res://scripts/ability_signatures.gd")
const ProcFx = preload("res://scripts/roguelite/proc_fx.gd")
const Vfx = preload("res://scripts/vfx_library.gd")

## The two automatic rows of the bar: consumables, not combat skills.
const CONSUMABLES := ["bandage", "healing_potion"]
## What the icon generator writes, and what the importer brings back.
const ICON_SIZE := Vector2i(256, 256)
## Long enough for the slowest one-shot here (the three-strike glow, the level
## pillar, an ash curtain) to finish and free itself. Nothing in this file may
## outlive this window.
const SETTLE_SECONDS := 4.0

var checks := 0
var failures := 0
var stage: Node3D
var rig: Node3D


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ABILITY_FX_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	rig = Node3D.new()
	stage.add_child(rig)
	rig.global_position = Vector3(2.0, 0.0, 3.0)
	_check_icons()
	_check_textures()
	_check_coverage()
	_check_signatures()
	_check_proc_effects()
	await _settle()
	check(stage.get_child_count() == 1,
		"every one-shot freed itself (the stage holds the rig and nothing else, got %d)"
		% stage.get_child_count())
	print("ABILITY_FX_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


# --- icons -----------------------------------------------------------------

func _check_icons() -> void:
	var seen := {}
	var count := 0
	for id in AbilityRules.catalog_ids():
		_check_icon(str(id), seen)
		count += 1
	for id in CONSUMABLES:
		_check_icon(str(id), seen)
		count += 1
	check(count == 38, "the catalog is 36 skills plus 2 consumables, got %d" % count)
	check(seen.size() == count, "every skill has its own icon (%d files for %d rows)"
		% [seen.size(), count])


func _check_icon(id: String, seen: Dictionary) -> void:
	var definition: Dictionary = AbilityRules.by_id(id)
	check(not definition.is_empty(), "%s is in the catalog" % id)
	var path := str(definition.get("icon", ""))
	check(not path.is_empty(), "%s authors an icon path" % id)
	if path.is_empty():
		return
	check(not seen.has(path), "%s has its own icon, not %s's (%s)"
		% [id, str(seen.get(path, "?")), path])
	seen[path] = id
	check(ResourceLoader.exists(path), "%s's icon exists: %s" % [id, path])
	var texture := AbilityRules.icon_texture(id)
	check(texture != null, "%s's icon loads as a texture" % id)
	if texture == null:
		return
	check(texture.get_size() == Vector2(ICON_SIZE),
		"%s's icon is %s, got %s" % [id, str(ICON_SIZE), str(texture.get_size())])


# --- painted textures -------------------------------------------------------

## The texture set the effects draw from. A missing sheet is not an error at
## runtime - every call falls back to a dot - which is exactly why it has to be
## caught here, in the build that shipped without it.
func _check_textures() -> void:
	var expected := {
		Vfx.FLAME: Vector2i(1024, 128),
		Vfx.SMOKE: Vector2i(1024, 128),
		Vfx.SPARK: Vector2i(256, 256),
		Vfx.CRESCENT: Vector2i(512, 256),
		Vfx.GLINT: Vector2i(512, 256),
		Vfx.RING: Vector2i(512, 512),
		Vfx.RUNES: Vector2i(512, 512),
		Vfx.SPLAT: Vector2i(256, 256),
	}
	for name in expected:
		var sheet := Vfx.texture(str(name))
		check(sheet != null, "the %s sheet is imported" % str(name))
		if sheet == null:
			continue
		check(Vector2i(sheet.get_size()) == Vector2i(expected[name]),
			"the %s sheet is %s, got %s" % [str(name), str(expected[name]),
			str(sheet.get_size())])
	# The flipbooks have to be wired to the particle animation, or the sheet is
	# just a still image standing in for fire.
	var flame := Vfx.flame_particles(Color(1, 0.5, 0.2), 8, 1.0, 3.0, 0.5, 0.3)
	var flame_material := (flame.mesh as QuadMesh).material as StandardMaterial3D
	check(flame_material.particles_anim_h_frames == Vfx.FLAME_FRAMES,
		"fire walks all %d flame frames" % Vfx.FLAME_FRAMES)
	check(flame.anim_speed_max > 0.0, "the flame flipbook animates")
	flame.queue_free()
	var sparks := Vfx.spark_burst(Color(1, 0.7, 0.3), 12, 2.0, 6.0, 0.4, 0.05)
	var spark_material := (sparks.mesh as QuadMesh).material as StandardMaterial3D
	check(spark_material.particles_anim_h_frames == Vfx.SPARK_COLUMNS,
		"a spark burst draws from the %d-column atlas" % Vfx.SPARK_COLUMNS)
	check(spark_material.particles_anim_v_frames == Vfx.SPARK_ROWS,
		"and from all %d of its rows" % Vfx.SPARK_ROWS)
	sparks.queue_free()
	var smoke := Vfx.smoke_particles(Color(0.6, 0.6, 0.6), 6, 1.0, 0.5)
	var smoke_material := (smoke.mesh as QuadMesh).material as StandardMaterial3D
	check(smoke_material.particles_anim_h_frames == Vfx.SMOKE_FRAMES,
		"smoke walks all %d frames" % Vfx.SMOKE_FRAMES)
	check(smoke_material.blend_mode == BaseMaterial3D.BLEND_MODE_MIX,
		"smoke mixes rather than adding light")
	smoke.queue_free()
	var decal := Vfx.decal(stage, Vector3.UP, Vfx.RING, Vector2.ONE, Color.WHITE, 0.4)
	check(decal != null and decal.mesh != null, "a decal lays down one quad")


# --- coverage tables -------------------------------------------------------

## Each combat skill must have at least one beat. A skill with no cue is a skill
## the scene never dresses, which is exactly the silent gap this file exists for.
func _check_coverage() -> void:
	var duplicate := {}
	for id in Signatures.signature_ids():
		var key := str(id)
		check(not duplicate.has(key), "%s is signed once" % key)
		duplicate[key] = true
	check(Signatures.missing_signatures().is_empty(),
		"every catalog skill has a signature, missing %s"
		% str(Signatures.missing_signatures()))
	for id in AbilityRules.catalog_ids():
		var definition: Dictionary = AbilityRules.by_id(str(id))
		var cues: Array = definition.get("cues", [])
		check(not cues.is_empty(), "%s declares a beat" % str(id))
	for id in CONSUMABLES:
		check(Signatures.has_signature(str(id)), "%s has a beat" % str(id))


# --- signatures ------------------------------------------------------------

## Walk the real cue table and make every beat draw. The rig is a bare `Node3D`
## on purpose: a signature may read the rig's own helpers when they exist, and
## must never require them, because the same code runs against replicas and
## harnesses.
func _check_signatures() -> void:
	for id in AbilityRules.catalog_ids():
		var definition: Dictionary = AbilityRules.by_id(str(id))
		var cues: Array = definition.get("cues", [])
		for index in cues.size():
			var beat: Dictionary = cues[index]
			var before := stage.get_child_count()
			var drew := Signatures.cue(stage, rig, definition,
				str(beat.get("cue", "")), index, Vector3.FORWARD,
				Vector3(0.0, 0.0, 6.0))
			check(drew, "%s's %s beat is signed" % [str(id), str(beat.get("cue", ""))])
			check(stage.get_child_count() > before,
				"%s's %s beat draws at least one node"
				% [str(id), str(beat.get("cue", ""))])
	for id in CONSUMABLES:
		var kind := "bandage" if str(id) == "bandage" else "potion"
		var before := stage.get_child_count()
		check(Signatures.consume(stage, rig, kind),
			"%s draws its own completion beat" % str(id))
		check(stage.get_child_count() > before,
			"%s's completion beat creates art" % str(id))
	# A skill that is not a signature at all must be refused, not guessed at.
	check(not Signatures.cue(stage, rig, {"id": "not_a_skill"}, "arc", 0,
		Vector3.FORWARD), "an unknown id draws nothing")


# --- proc effects ----------------------------------------------------------

## Every consequence the arena can roll, called once with a live parent. Each has
## to create art; `_settle` then insists they all leave. The calls are written out
## rather than driven from a table because these are static functions on a script
## resource, not methods of an object, and a table would only hide a missing one
## behind a string.
func _check_proc_effects() -> void:
	_expect("arc_blade", func() -> void:
		ProcFx.arc_blade(stage, Vector3.ZERO, Vector3.UP * 2.0, ProcFx.SPARK))
	_expect("nova_ring", func() -> void:
		ProcFx.nova_ring(stage, Vector3.ZERO, ProcFx.SPARK, 8))
	_expect("chain_web", func() -> void:
		ProcFx.chain_web(stage, Vector3.ZERO, [Vector3.ONE, Vector3.UP * 3.0],
			ProcFx.BLOOD))
	_expect("bomb_charge", func() -> void:
		ProcFx.bomb_charge(stage, Vector3.ZERO, 3.0, 0.2, ProcFx.BLOOD))
	_expect("blast_front", func() -> void:
		ProcFx.blast_front(stage, Vector3.ZERO, 2.0, ProcFx.SPARK))
	_expect("splash_gout", func() -> void:
		ProcFx.splash_gout(stage, Vector3.ZERO, 2.0, ProcFx.BLOOD))
	_expect("spike_ring", func() -> void:
		ProcFx.spike_ring(stage, Vector3.ZERO, 2.0, ProcFx.SPARK))
	_expect("shockwave_arc", func() -> void:
		ProcFx.shockwave_arc(stage, Vector3.ZERO, Vector3.FORWARD, ProcFx.SPARK))
	_expect("whirl_vortex", func() -> void:
		ProcFx.whirl_vortex(stage, Vector3.ZERO, 2.0, ProcFx.SPARK))
	_expect("zone_field", func() -> void:
		ProcFx.zone_field(stage, Vector3.ZERO, 2.0, 0.4, ProcFx.HEAL))
	_expect("heal_motes", func() -> void:
		ProcFx.heal_motes(stage, Vector3.UP, ProcFx.HEAL, 1.0))
	_expect("gold_glints", func() -> void:
		ProcFx.gold_glints(stage, Vector3.UP, ProcFx.GOLD, 1.0))
	_expect("bleed_drip", func() -> void:
		ProcFx.bleed_drip(stage, Vector3.ZERO, 0.4, ProcFx.BLOOD))
	_expect("wound_sear", func() -> void:
		ProcFx.wound_sear(stage, Vector3.ZERO, ProcFx.BLOOD))
	_expect("level_pillar", func() -> void:
		ProcFx.level_pillar(stage, Vector3.ZERO, ProcFx.GOLD))
	_expect("double_flash", func() -> void:
		ProcFx.double_flash(stage, Vector3.UP, ProcFx.SPARK))
	_expect("crit_star", func() -> void:
		ProcFx.crit_star(stage, Vector3.UP, ProcFx.SPARK))
	_expect("kill_pop", func() -> void:
		ProcFx.kill_pop(stage, Vector3.ZERO, ProcFx.SPARK, 1.0))
	# The old four are still the same four: a co-op peer of an older build uses
	# them, and the guest handler reaches them by name.
	_expect("lightning", func() -> void:
		ProcFx.lightning(stage, Vector3.ZERO, Vector3.UP * 2.0))
	_expect("ring", func() -> void: ProcFx.ring(stage, Vector3.ZERO))
	_expect("flare", func() -> void: ProcFx.flare(stage, Vector3.UP))


## Run one effect and insist it left something behind to look at.
func _expect(name: String, effect: Callable) -> void:
	var before := stage.get_child_count()
	effect.call()
	check(stage.get_child_count() > before, "the %s proc draws art" % name)


## Let every one-shot run out. A tween that ends in `queue_free` only frees when
## the frame clock advances, so this is a real wait rather than a claim.
func _settle() -> void:
	await create_timer(SETTLE_SECONDS).timeout
