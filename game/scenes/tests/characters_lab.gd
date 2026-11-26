extends Node3D
## 캐릭터 검토 캡처 (실제 Godot 렌더): 소은·괴물 전신/측면/얼굴, 괴물 고개 숙임·들기·달리기·붙잡기
var out := "/tmp/chars"
var cam: Camera3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--out"):
		out = args[args.find("--out") + 1]
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.22, 0.2)
	fl.material_override = fm
	add_child(fl)
	for spec in [[Vector3(1.5, 2.4, 2.0), 2.4, Color(1, 0.9, 0.8)], [Vector3(-2, 1.6, 1.0), 0.9, Color(0.7, 0.8, 1.0)], [Vector3(0, 2.2, -2.0), 1.6, Color(0.9, 0.9, 1.0)]]:
		var l := OmniLight3D.new()
		l.position = spec[0]
		l.light_energy = spec[1]
		l.light_color = spec[2]
		l.omni_range = 8
		l.shadow_enabled = true
		add_child(l)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	_run()

func spawn(path: String, pos: Vector3) -> CharacterPoser:
	var c := (load(path) as PackedScene).instantiate() as Node3D
	add_child(c)
	c.position = pos
	var sk := c.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var p := CharacterPoser.new()
	c.add_child(p)
	p.setup(sk)
	return p

func view(eye: Vector3, at: Vector3, fov := 40.0) -> void:
	cam.fov = fov
	cam.global_position = eye
	cam.look_at(at)

func shot(n: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("SHOT ", n)

func _run() -> void:
	var so := spawn("res://assets/models/characters/chr_soeun.gltf", Vector3(-0.9, 0, 0))
	var mo := spawn("res://assets/models/characters/gst_prologue_monster.gltf", Vector3(0.9, 0, 0))
	mo.hunch = 1.0
	mo.head_raise = 0.0
	await get_tree().process_frame
	view(Vector3(0, 1.3, 4.6), Vector3(0, 1.0, 0), 42)
	await shot("01_both_front")
	view(Vector3(-0.9, 1.05, 1.0), Vector3(-0.9, 1.05, 0), 35)
	await shot("02_soeun_face")
	view(Vector3(-3.2, 0.9, 1.2), Vector3(-0.9, 0.7, 0), 32)
	await shot("03_soeun_side")
	mo.head_raise = 1.0
	view(Vector3(0.9, 1.6, 2.4), Vector3(0.9, 1.5, 0), 40)
	await shot("04_monster_head_up")
	mo.mode = "run"
	mo.head_raise = 0.7
	view(Vector3(3.6, 1.3, 2.2), Vector3(0.9, 1.1, 0), 40)
	await shot("05_monster_run")
	mo.mode = "grab"
	view(Vector3(0.9, 1.6, 2.0), Vector3(0.9, 1.4, 0), 50)
	await shot("06_monster_grab_pov")
	get_tree().quit()
