extends Node
## 요구사항 12 QA 비교 캡처 — 실제 Godot 화면(lavapipe)에서 같은 위치·같은 카메라 방향으로 상태만 바꿔 찍는다.
## usage: godot --path game --rendering-driver vulkan --fixed-fps 20 --resolution 1280x720 res://scenes/tests/qa_capture.tscn -- --out DIR [--only camera|lighting|box|hands]

var lvl: Node3D
var p: PlayerController
var out := "/tmp/qa"
var only := ""

func _ready() -> void:
	GameFlow.auto_pause_on_focus_loss = false
	var args := OS.get_cmdline_user_args()
	if args.has("--out"):
		out = args[args.find("--out") + 1]
	if args.has("--only"):
		only = args[args.find("--only") + 1]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func t(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func B(x: float, y: float, z: float) -> Vector3:
	return lvl.b2g(Vector3(x, y, z))

func view(pos_b: Vector3, look_b: Vector3) -> void:
	p.global_position = lvl.b2g(Vector3(pos_b.x, pos_b.y, 0.0)) + Vector3(0, 0.02, 0)
	await t(0.15)
	p.look_at_point(lvl.b2g(look_b))
	await t(0.6)

func _run() -> void:
	SaveGame.delete_save()
	Inventory.clear()
	lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lvl.enable_thunder = false
	lvl.force_story = only == "staging"
	add_child(lvl)
	p = lvl.player
	await t(2.5)
	GameFlow.set_state(GameFlow.State.PLAYING)
	if only in ["", "camera"]:
		await _camera()
	if only in ["", "box"]:
		await _box()
	if only in ["", "lighting"]:
		await _lighting()
	if only in ["", "hands"]:
		await _hands()
	if only == "staging":
		await _staging()
	print("QA CAPTURE DONE")
	get_tree().quit()

## 1인칭 시점: 같은 자리에서 FOV 65 / 70 / 75, 그리고 문 앞·책상 앞에서 본 실제 규격 확인
func _camera() -> void:
	lvl.set_lighting("normal", true)
	print("EYE ", p.camera.global_position.y - p.global_position.y, " FOV ", p.camera.fov)
	await view(Vector3(1.4, 1.1, 0), Vector3(3.0, 4.4, 0.9))
	for f in [65.0, 70.0, 75.0]:
		p.camera.fov = f
		await t(0.3)
		await shot("cam_room_fov%d" % int(f))
	p.camera.fov = GameSettings.fov
	await view(Vector3(2.95, 3.0, 0), Vector3(2.95, 4.6, 0.95))
	await shot("cam_desk_front")
	await view(Vector3(0.95, 1.2, 0), Vector3(0.95, 0.0, 1.05))
	await shot("cam_door_front")
	Input.action_press("crouch")
	await t(1.2)
	print("EYE_CROUCH ", p.camera.global_position.y - p.global_position.y)
	await shot("cam_door_crouch")
	Input.action_release("crouch")
	await t(0.8)

## 상자 개봉 → 들여다보기 시점 → 첫 테이프에 시선
func _box() -> void:
	lvl.set_lighting("normal", true)
	lvl.parcel.visible = true
	lvl.parcel.top_level = true
	lvl.parcel.global_transform = lvl._desk_place_transform()
	lvl.parcel_on_desk = true
	var dt: Transform3D = lvl._desk_place_transform()
	p.global_position = Vector3(dt.origin.x, 0.02, dt.origin.z) + Vector3(0.05, 0, 0.72)
	await t(0.2)
	p.look_at_point(dt.origin)
	await t(0.5)
	lvl._parcel_open()
	await t(4.5)
	await shot("box_lean_view")
	var t1 := lvl.parcel.find_child("prop_tape_1", true, false) as Node3D
	p.look_at_point(t1.global_position)
	await t(0.8)
	await shot("box_look_tape1")
	await shot("box_look_tape1_b")

## 조명 상태 5종 + 손전등 ON/OFF + 이상 현상 — 같은 시점
func _lighting() -> void:
	var views := [[Vector3(1.4, 1.1, 0), Vector3(3.0, 4.4, 0.9), "room"], [Vector3(4.6, 2.2, 0), Vector3(1.2, 4.2, 0.6), "corner"]]
	Inventory.add(&"flashlight")
	await t(0.8)
	for v in views:
		await view(v[0], v[1])
		for st in [["normal", false], ["partial", false], ["broken", false], ["blackout", false], ["blackout", true], ["emergency", false]]:
			lvl.set_lighting(st[0], true)
			if p.flashlight.is_on != st[1]:
				p.flashlight.set_on(st[1])
			await t(1.6)
			await shot("light_%s_%s%s" % [v[2], st[0], "_flashlight" if st[1] else ""])
	# 초자연 이상 현상: 손전등 깜빡임
	lvl.set_lighting("blackout", true)
	p.flashlight.set_on(true)
	await t(0.6)
	p.flashlight.anomaly_flicker(2.0)
	await t(0.35)
	await shot("light_room_anomaly_flicker")
	p.flashlight.set_on(false)

## 요구사항 14: 손 없이 — 손전등 '빛만' vs '모델 표시' 같은 자리 비교 (정전 상태)
func _hands() -> void:
	Inventory.add(&"flashlight")
	lvl.set_lighting("blackout", true)
	for v in [[Vector3(1.4, 1.1, 0), Vector3(3.0, 4.4, 0.9), "room"], [Vector3(3.0, 3.3, 0), Vector3(3.2, 4.5, 0.75), "desk"]]:
		await view(v[0], v[1])
		for m in [false, true]:
			p.flashlight.show_model = m
			if not p.flashlight.is_on:
				p.flashlight.set_on(true)
			await t(1.2)
			await shot("flashlight_%s_%s" % [v[2], "model" if m else "light_only"])
	p.flashlight.show_model = false


## 요구사항 16 연출 실제 화면: 복도 소은 · 기둥 괴물 · 뒤에서 꺼진 형광등 · 1998 아파트 · 복귀 후 책상 사진
func _staging() -> void:
	var st: StoryStaging = lvl.story_fx.st()
	lvl.director.active = false
	lvl.set_lighting("blackout", true)
	if lvl.door_hinge:
		lvl.door_hinge.rotation.y = deg_to_rad(100.0)
		lvl.door_open = true
	st.place_soeun_corridor(false)
	await view(Vector3(1.0, -1.15, 0), Vector3(12.15, -1.25, 1.0))
	await shot("ev08_soeun_corridor_end")
	await view(Vector3(6.5, -1.15, 0), Vector3(12.15, -1.25, 1.0))
	await shot("ev08_soeun_closer")
	lvl.soeun_node.visible = false
	st.place_monster_corner(false)
	await t(1.0)
	await view(Vector3(0.9, -1.35, 0), Vector3(-1.4, -0.9, 1.6))
	await shot("ev09_noise_peek_pillar")
	Inventory.add(&"flashlight")
	p.flashlight.set_on(true)
	await t(0.8)
	await shot("ev09_noise_peek_flashlight")
	await view(Vector3(-0.4, -1.5, 0), Vector3(-1.5, -0.8, 1.6))
	await shot("ev09_noise_close")
	st.noise.visible = false
	p.flashlight.set_on(false)
	for i in 4:
		lvl.set_light("CorLight%d" % i, "story_off", true)
	await view(Vector3(8.8, -1.1, 0), Vector3(-4.0, -1.1, 1.3))
	await shot("ev10_lights_off_behind")
	await view(Vector3(8.8, -1.1, 0), Vector3(13.0, -1.1, 1.3))
	await shot("ev10_light_ahead")
	lvl.enter_apartment()
	await t(1.5)
	var apt: AptCorridor = lvl.apt
	await _aview(Vector3(3.0, 0.85, 0), Vector3(20.0, 0.9, 1.3))
	await shot("t01_apt_corridor_spawn")
	await _aview(Vector3(16.0, 0.6, 0), Vector3(16.0, -6.0, 0.2))
	await shot("t01_apt_corridor_view_out")
	await _aview(Vector3(25.1, -2.5, -0.45), Vector3(11.0, -10.0, -0.2))
	await shot("t01_apt_entrance_to_playground")
	await _aview(Vector3(13.5, -6.0, -0.45), Vector3(9.5, -9.5, 0.4))
	await shot("t01_playground_swing")
	await _aview(Vector3(25.4, 1.2, 0.0), Vector3(25.6, 5.0, 1.7))
	await shot("t01_stairs")
	await _aview(Vector3(12.0, 0.6, 0), Vector3(4.0, 0.9, 1.2))
	await shot("t01_apt_corridor_west")
	apt.soeun.global_position = apt.point("apt_soeun_end")
	apt.soeun.look_at(apt.to_global(AptCorridor.b(Vector3(14.0, 0.85, 0))), Vector3.UP, true)
	apt.soeun.visible = true
	await _aview(Vector3(14.0, 0.7, 0), Vector3(23.4, 0.95, 0.9))
	await shot("t01_soeun_corridor_end")
	apt.soeun.visible = false
	lvl.mark_tape_finished("1")
	lvl.return_to_studio(true)
	lvl.show_photo(true)
	await t(1.5)
	await shot("t01_return_studio_view")
	p.look_at_point(lvl.photo.global_position)
	await t(0.6)
	await shot("t01_photo_on_desk")
	print("PLAYER ", p.global_position, " CAM ", p.camera.global_position, " PHOTO ", lvl.photo.global_position, " REC ", lvl.recorder.global_position)

func _aview(pos_b: Vector3, look_b: Vector3) -> void:
	var apt: AptCorridor = lvl.apt
	p.global_position = apt.to_global(AptCorridor.b(pos_b)) + Vector3(0, 0.05, 0)
	await t(0.15)
	p.look_at_point(apt.to_global(AptCorridor.b(look_b)))
	await t(0.8)
