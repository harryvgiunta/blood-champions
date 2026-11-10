extends SceneTree
## Throwaway lookbook: one rendered frame per ability signature and per proc
## consequence, all from the same camera, so the set can be judged as art.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_fx.gd --resolution 900x700
##
## Writes .runtime/fx_cells/<slug>.png. Nothing here ships.

const Signatures = preload("res://scripts/ability_signatures.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const ProcFx = preload("res://scripts/roguelite/proc_fx.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")

const OUT := "res://.runtime/fx_cells"
## Which beat to photograph for a skill with several: the one that draws the most.
const CUE := {
	"spin_slash": 1, "lunge_thrust": 1, "backstab": 1, "three_strike": 2,
	"shield_charge": 0, "rain_of_ash": 0,
}
## The proc effects, in the order the sheet reads them.
const PROCS := ["chain_web", "blast_front", "spike_ring", "whirl_vortex",
	"splash_gout", "nova_ring", "heal_motes", "gold_glints", "level_pillar",
	"crit_star", "bleed_drip", "zone_field", "double_flash", "kill_pop",
	"bomb_charge", "shockwave_arc", "arc_blade", "explosion", "shockwave"]

var stage: Node3D
var camera: Camera3D
var lens: Node3D


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build()
	await process_frame
	for id in AbilityRules.catalog_ids():
		var definition: Dictionary = AbilityRules.by_id(str(id))
		var cues: Array = definition.get("cues", [])
		if cues.is_empty():
			continue
		var index := clampi(int(CUE.get(str(id), 0)), 0, cues.size() - 1)
		var beat: Dictionary = cues[index]
		_lens_reset()
		# The line is turned off the camera's own axis, the way a player's aim
		# usually is: a lance fired straight at the lens reads as a dot.
		var line := Vector3(0.62, 0.0, -0.78).normalized()
		Signatures.cue(stage, lens, definition, str(beat.get("cue", "")), index,
			line, line * 6.0)
		await _snap("ability_" + str(id))
	for kind in ["bandage", "potion"]:
		_lens_reset()
		Signatures.consume(stage, lens, str(kind))
		await _snap("consume_" + str(kind))
	for name in PROCS:
		_lens_reset()
		_proc(str(name))
		await _snap("proc_" + str(name))
	quit(0)


func _proc(name: String) -> void:
	var at := Vector3(0.0, 0.1, -1.2)
	match name:
		"chain_web":
			ProcFx.chain_web(stage, at, [Vector3(1.2, 1.6, -1.0),
				Vector3(-1.4, 0.9, 0.4)], ProcFx.BLOOD)
		"blast_front":
			ProcFx.blast_front(stage, at, 2.0, ProcFx.SPARK)
		"spike_ring":
			ProcFx.spike_ring(stage, at, 2.0, ProcFx.SPARK)
		"whirl_vortex":
			ProcFx.whirl_vortex(stage, at, 2.0, ProcFx.SPARK)
		"splash_gout":
			ProcFx.splash_gout(stage, at, 2.0, ProcFx.BLOOD)
		"nova_ring":
			ProcFx.nova_ring(stage, at, ProcFx.SPARK, 8)
		"heal_motes":
			ProcFx.heal_motes(stage, at + Vector3.UP * 1.1, ProcFx.HEAL, 1.4)
		"gold_glints":
			ProcFx.gold_glints(stage, at + Vector3.UP * 1.1, ProcFx.GOLD, 1.4)
		"level_pillar":
			ProcFx.level_pillar(stage, at, ProcFx.GOLD)
		"crit_star":
			ProcFx.crit_star(stage, at + Vector3.UP * 1.5, ProcFx.SPARK)
		"bleed_drip":
			ProcFx.bleed_drip(stage, at, 1.4, ProcFx.BLOOD)
		"zone_field":
			ProcFx.zone_field(stage, at, 2.2, 1.4, ProcFx.HEAL)
		"double_flash":
			ProcFx.double_flash(stage, at + Vector3.UP * 1.4, ProcFx.SPARK)
		"kill_pop":
			ProcFx.kill_pop(stage, at, ProcFx.SPARK, 1.4)
		"bomb_charge":
			ProcFx.bomb_charge(stage, at, 2.0, 0.35, ProcFx.BLOOD)
		"shockwave_arc":
			ProcFx.shockwave_arc(stage, Vector3(0.0, 0.0, 1.4), Vector3.FORWARD,
				ProcFx.SPARK)
		"arc_blade":
			ProcFx.arc_blade(stage, Vector3(-1.6, 1.2, 0.4),
				Vector3(1.4, 1.6, -1.6), ProcFx.SPARK)
		"explosion":
			AbilityFx.explosion(stage, Vector3(0.0, 1.0, -1.0), 2.4)
		"shockwave":
			AbilityFx.ground_shockwave(stage, Vector3(0.0, 0.0, -0.8), 3.0)


func _build() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.030, 0.038, 0.046)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.47, 0.54)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.115, 0.100, 0.086)
	stone.roughness = 1.0
	plane.material = stone
	stage.add_child(ground)
	# A standing post where a body would be: it is not the rig (the rig has no
	# skeleton here) but it gives the eye the body's height, so an effect at chest
	# height can be judged as chest height.
	var post := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.34
	body.height = 1.8
	post.mesh = body
	var hide := StandardMaterial3D.new()
	hide.albedo_color = Color(0.20, 0.18, 0.16)
	hide.roughness = 0.9
	body.material = hide
	post.position = Vector3(0.0, 0.9, 0.0)
	stage.add_child(post)
	lens = Node3D.new()
	lens.name = "Lens"
	stage.add_child(lens)
	camera = Camera3D.new()
	camera.fov = 50.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 1.95, 4.6), Vector3(0.0, 1.10, -0.9),
		Vector3.UP)
	camera.current = true


func _lens_reset() -> void:
	lens.global_position = Vector3(0.0, 0.0, 0.0)


## One frame, then enough clock for the effect to finish and free itself before
## the next one is spawned in the same place.
func _snap(slug: String) -> void:
	await create_timer(0.16).timeout
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT, slug])
	print("FX_CELL ", slug)
	await create_timer(1.5).timeout
