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
	cam.fov = 70
	cam.near = 0.03
	cam.position = Vector3(0, 1.62, 0)
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
	# 왼손: 손전등 (원통 축 = 0.8R + 0.6F 대각선), 오른손: 녹음기를 손바닥에
	var beam := Vector3(0.10, 0.06, -1).normalized()
	var axes := arms.grip_axes("L", beam, Vector3(-0.55, 0.83, 0.1))
	var fl_center := Vector3(-0.17, -0.19, -0.42)
	# 원통 중심 = 손목 + F*0.065 - N*0.042 → 손목 = 중심 - (...)
	var F: Vector3 = axes[0]
	var R: Vector3 = axes[1]
	var N := arms._dorsal_for(arms.sides["L"], F, R)
	arms.aim("L", fl_center - F * 0.065 + N * 0.042, F, R, 12.0)
	arms.set_mode("L", ViewmodelArms.Mode.HOLD_FLASHLIGHT)
	arms.aim("L", fl_center - F * 0.065 + N * 0.042, F, R, 12.0)
	var A := (R * 0.8 + F * 0.6).normalized()
	# 손 프레임 기준 오프셋 (R,N,F): 원통 축 A, 위(스위치) = N
	var a_local := Vector3(0.8, 0.0, 0.6).normalized()
	var y_local := Vector3(0, 1, 0)
	var z_local := -a_local
	var x_local := y_local.cross(z_local)
	var center := Vector3(0, -0.042, 0.065)
	arms.attach("L", fl, Transform3D(Basis(x_local, y_local, z_local), center - a_local * -(-0.15)))
	var rN := Vector3(-0.1, -0.86, 0.5).normalized()
	var rF := Vector3(-0.35, 0.45, -0.82)
	rF = (rF - rN * rF.dot(rN)).normalized()
	var rR := -rN.cross(rF)
	if arms._dorsal_for(arms.sides["R"], rF, rR).dot(rN) < 0:
		rR = -rR
	var rec_center := Vector3(0.15, -0.2, -0.40)
	arms.set_mode("R", ViewmodelArms.Mode.HOLD_RECORDER)
	arms.aim("R", rec_center - rF * 0.07 + rN * 0.032, rF, rR, 12.0)
	arms.attach("R", rec, Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)), Vector3(0, -0.032 - 0.017, 0.07)))

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("SHOT ", name)

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	await frames(3)
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
	get_tree().quit()
