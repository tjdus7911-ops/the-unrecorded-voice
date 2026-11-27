extends Node3D
## 손·팔 검토 장면 (실제 Godot 렌더 캡처): 1인칭 시점 + 외부 시점.
## usage: godot --path game --rendering-driver vulkan res://scenes/tests/hands_lab.tscn -- --out /tmp/hands [--plain]

const FL := "res://assets/models/props/prop_flashlight.gltf"
const REC := "res://assets/models/props/prop_recorder.gltf"

var out := "/tmp/hands"
var cam: Camera3D
var arms: ViewmodelArms
var fl: Node3D
var rec: Node3D
var spot: SpotLight3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--out"):
		out = args[args.find("--out") + 1]
	DirAccess.make_dir_recursive_absolute(out)
	ViewmodelArms.plain_materials = args.has("--plain")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.28, 0.22, 0.17)
	fm.roughness = 0.7
	floor.material_override = fm
	add_child(floor)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(4, 3, 0.1)
	wall.mesh = wm
	wall.position = Vector3(0, 1.5, -1.6)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.62, 0.6, 0.55)
	wall.material_override = wmat
	add_child(wall)
	var key := OmniLight3D.new()
	key.position = Vector3(0.6, 2.4, 0.4)
	key.light_energy = 2.2
	key.omni_range = 6
	key.light_color = Color(1.0, 0.85, 0.7)
	key.shadow_enabled = true
	add_child(key)
	cam = Camera3D.new()
	cam.fov = 68
	cam.near = 0.03
	cam.position = Vector3(0, 1.64, 0)
	add_child(cam)
	cam.current = true
	arms = ViewmodelArms.new()
	arms.camera = cam
	add_child(arms)
	fl = (load(FL) as PackedScene).instantiate()
	add_child(fl)
	rec = (load(REC) as PackedScene).instantiate()
	add_child(rec)
	for c in fl.find_children("*", "CollisionObject3D", true, false) + rec.find_children("*", "CollisionObject3D", true, false):
		c.queue_free()
	spot = SpotLight3D.new()
	spot.light_energy = 6
	spot.spot_angle = 32
	spot.spot_range = 12
	spot.shadow_enabled = true
	spot.position = Vector3(0, 0, -0.26)
	fl.add_child(spot)
	_run()

func hold_both() -> void:
	# 실제 게임과 같은 프리셋 (ViewmodelArms.hold_flashlight / hold_recorder)
	var rig := Node3D.new()
	add_child(rig)
	fl.get_parent().remove_child(fl)
	rig.add_child(fl)
	fl.position = Vector3(0, 0, 0.15)
	spot.position = Vector3(0, 0, -0.26)
	spot.reparent(rig, false)
	spot.position = Vector3(0, 0, -0.11)
	arms.hold_flashlight(rig)
	arms.hold_recorder(rec)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("SHOT ", name)

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _diag() -> void:
	# 진단: 손가락 앞(-Z), 손등 위(+Y) — 위에서 보면 손등·손톱이 보여야 하고, 엄지는 몸 안쪽을 향해야 한다
	for side in ["L", "R"]:
		var h: ViewmodelArms.Hand = arms.sides[side]
		var F := Vector3(0, 0, -1)
		var R := Vector3(1, 0, 0) if side == "L" else Vector3(-1, 0, 0)
		print(side, " dorsal_for(F,R)=", arms._dorsal_for(h, F, R), " hand_sign=", h.hand_sign)
		arms.set_mode(side, ViewmodelArms.Mode.HOLD_FLASHLIGHT if side == "L" else ViewmodelArms.Mode.HOLD_RECORDER)
		arms.set_pose(side, "open")
		arms.aim(side, Vector3(0.12 * h.sign, -0.2, -0.38), F, R, 20.0)
	await frames(40)
	var ext := Camera3D.new()
	ext.fov = 45
	add_child(ext)
	ext.global_position = Vector3(0.0, 2.3, -0.25)
	ext.look_at(Vector3(0.0, 1.44, -0.40))
	ext.current = true
	arms.follow_stiffness = 1000.0
	await frames(10)
	await shot("diag_top")
	ext.global_position = Vector3(0.0, 1.0, -0.6)
	ext.look_at(Vector3(0.0, 1.44, -0.40))
	await frames(10)
	await shot("diag_below")
	get_tree().quit()

func _run() -> void:
	await frames(3)
	if OS.get_cmdline_user_args().has("--diag"):
		await _diag()
		return
	hold_both()
	await frames(40)
	await shot("01_fps_hold")
	cam.rotation.x = deg_to_rad(-25)
	await frames(30)
	await shot("02_fps_look_down")
	cam.rotation.x = 0
	# 외부 시점 (손 모양·파지 확인)
	var ext := Camera3D.new()
	ext.fov = 40
	add_child(ext)
	ext.global_position = Vector3(0.75, 1.62, -0.55)
	ext.look_at(Vector3(0.0, 1.42, -0.38))
	ext.current = true
	arms.follow_stiffness = 1000.0
	await frames(20)
	await shot("03_ext_right")
	ext.global_position = Vector3(-0.8, 1.55, -0.7)
	ext.look_at(Vector3(-0.12, 1.42, -0.4))
	await frames(10)
	await shot("04_ext_left")
	ext.global_position = Vector3(0.1, 1.95, -0.95)
	ext.look_at(Vector3(0.0, 1.42, -0.4))
	await frames(10)
	await shot("05_ext_front")
	ext.current = false
	cam.current = true
	arms.follow_stiffness = 16.0
	arms.lower_tool("R")
	await frames(40)
	await shot("06_fps_flashlight_only")
	arms.lower_tool("L")
	await frames(40)
	await shot("07_fps_empty")
	get_tree().quit()
