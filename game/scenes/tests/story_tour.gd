extends Node
## 프롤로그 EVENT 01~08 시연 (실제 플레이어·손·상호작용·이벤트를 그대로 사용, 입력만 스크립트가 누른다)
## 영상: godot --path game --rendering-driver vulkan --write-movie out.avi --fixed-fps 24 res://scenes/tests/story_tour.tscn
## 스크린샷: ... -- --out /tmp/story (각 장면에서 PNG 저장)

var lvl: Node3D
var p: PlayerController
var out := ""
var shots := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--out"):
		out = args[args.find("--out") + 1]
		DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func t(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	shots += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, shots, name])
	print("SHOT ", name)

func lookw(pos: Vector3, dur := 0.8) -> void:
	var d := pos - p.head.global_position
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var cur: float = p.get("_yaw")
	yaw = cur + wrapf(yaw - cur, -PI, PI)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "_yaw", yaw, dur)
	tw.tween_property(p, "_pitch", pitch, dur)
	await t(dur)

func walkw(goal: Vector3, max_t := 6.0) -> void:
	goal.y = 0
	Input.action_press("move_forward")
	var el := 0.0
	while el < max_t:
		var d := goal - Vector3(p.global_position.x, 0, p.global_position.z)
		if d.length() < 0.22:
			break
		var want := atan2(-d.x, -d.z)
		var cur: float = p.get("_yaw")
		p.set("_yaw", cur + wrapf(want - cur, -PI, PI) * 0.15)
		p.set("_pitch", lerpf(float(p.get("_pitch")), -0.15, 0.05))
		await get_tree().physics_frame
		el += get_physics_process_delta_time()
	Input.action_release("move_forward")
	if Vector2(goal.x - p.global_position.x, goal.z - p.global_position.z).length() > 0.6:
		p.global_position = Vector3(goal.x, p.global_position.y, goal.z)
	await t(0.25)

func press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await t(0.05)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)

func mouse(dx: float, dy: float, steps := 20) -> void:
	for i in steps:
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(dx, dy) / steps
		ev.screen_relative = ev.relative
		ev.position = get_viewport().get_visible_rect().size * 0.5
		get_viewport().push_input(ev)
		await get_tree().process_frame

func wait_ev(id: String, timeout := 25.0) -> void:
	var el := 0.0
	while el < timeout and not lvl.director.is_done(id):
		await t(0.2)
		el += 0.2

func wait_started(id: String, timeout := 25.0) -> void:
	var el := 0.0
	while el < timeout and not lvl.director.started.has(id):
		await t(0.1)
		el += 0.1

func _run() -> void:
	SaveGame.delete_save()
	Inventory.clear()
	lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lvl.force_story = true
	lvl.enable_thunder = true
	add_child(lvl)
	p = lvl.player
	await t(1.5)
	var B := func(x: float, y: float, z: float) -> Vector3: return lvl.b2g(Vector3(x, y, z))
	if OS.get_cmdline_user_args().has("--debug-inspect"):
		lvl.parcel.visible = true
		lvl.parcel.top_level = true
		lvl.parcel.global_transform = lvl._desk_place_transform()
		lvl.parcel_on_desk = true
		lvl._parcel_open()
		await t(3.5)
		var dt0: Transform3D = lvl._desk_place_transform()
		p.global_position = dt0.origin + Vector3(0.05, -dt0.origin.y, 0.72)
		await t(0.3)
		for nm in ["prop_memo", "prop_tape_1"]:
			var o := lvl.parcel.find_child(nm, true, false) as Node3D
			await lookw(o.global_position, 0.4)
			await press("interact")
			await t(1.6)
			await shot("dbg_" + nm)
			await mouse(-150, 60)
			await t(0.6)
			await shot("dbg_rot_" + nm)
			await press("interact")
			await t(1.0)
		await lookw(lvl.recorder.global_position, 0.4)
		await press("interact")
		await t(1.2)
		await press("recorder_play")
		await t(0.75)
		await shot("dbg_insert")
		await t(2.5)
		await press("recorder_play")
		await t(1.0)
		await shot("dbg_play")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--debug-carry"):
		lvl.show_parcel_at_door()
		var pp: Vector3 = lvl.parcel.global_position
		print("parcel gt ", lvl.parcel.global_transform, " aabb ", Interactable.local_aabb(lvl.parcel))
		p.global_position = Vector3(pp.x, 0.0, pp.z - 0.8)
		await t(0.3)
		await lookw(pp + Vector3(0, 0.1, 0), 0.4)
		await shot("dbg_before")
		var pit := lvl.parcel.find_child("ParcelInteract", false, false) as Interactable
		pit.action.call()
		await t(0.35)
		await shot("dbg_mid")
		await t(1.2)
		print("cam ", p.camera.global_position, " box ", lvl.parcel.global_transform, " carryT ", p.arms.carry_T)
		await shot("dbg_carry")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--debug-hands"):
		print("arms enabled=", p.arms.enabled, " skel=", p.arms.skel, " cam=", p.arms.camera, " vis=", p.arms.is_visible_in_tree())
		Inventory.add(&"flashlight")
		await t(1.0)
		print("L pos ", p.arms.sides["L"].pos, " mode ", p.arms.sides["L"].mode, " arms global ", p.arms.global_position, " cam ", p.camera.global_position)
		await shot("debug_hands")
		var sw0 := lvl.find_child("stu_light_switch", true, false) as Node3D
		var off: Vector3 = lvl.b2g(Vector3(1.6, 1.0, 0)) - sw0.global_position
		off.y = 0
		p.global_position = sw0.global_position + off.normalized() * 0.75 - Vector3(0, sw0.global_position.y, 0)
		await t(0.3)
		await lookw(sw0.global_position, 0.5)
		await press("interact")
		await t(0.25)
		await shot("debug_reach_a")
		await t(0.2)
		await shot("debug_reach_b")
		await t(0.6)
		var lev := lvl.door_hinge.find_child("stu_door_lever_in", true, false) as Node3D
		await walkw(lvl.b2g(Vector3(0.95, 0.75, 0)))
		await lookw(lev.global_position, 0.5)
		await press("interact")
		await t(0.42)
		await shot("debug_door")
		get_tree().quit()
		return
	# ---- EVENT 01: 정상 작업실 — 둘러보기·걷기·스위치 (손으로 누름)
	await lookw(B.call(3.2, 5.0, 1.4), 1.6)
	await shot("ev01_studio_normal")
	await walkw(B.call(3.6, 3.4, 0))
	await lookw(B.call(5.0, 1.5, 1.0), 1.2)
	await walkw(B.call(3.4, 1.6, 0))
	await lookw(B.call(0.3, 3.0, 1.2), 1.4)
	await walkw(B.call(1.6, 1.0, 0))
	var sw := lvl.find_child("stu_light_switch", true, false) as Node3D
	if sw:
		await lookw(sw.global_position, 0.8)
		await press("interact")
		await t(0.18)
		await shot("hand_press_switch")
		await t(1.2)
		await press("interact")
		await t(1.3)
	# 튜토리얼 조건 (이동·둘러보기·조사) 충족 → 노크
	await lookw(B.call(2.5, 4.0, 1.0), 1.2)
	await wait_ev("EV02_knock", 30)
	await t(0.4)
	# ---- EVENT 02: 노크 → 문 열기 (레버를 잡는 손)
	await lookw(lvl.door_hinge.global_position + Vector3(0.75, 1.0, 0), 1.0)
	await t(2.0)
	await walkw(B.call(0.95, 0.75, 0))
	var lever := lvl.door_hinge.find_child("stu_door_lever_in", true, false) as Node3D
	await lookw(lever.global_position, 0.6)
	await press("interact")
	await t(0.42)
	await shot("hand_door_lever")
	await t(1.5)
	await walkw(B.call(0.95, -0.25, 0))
	await lookw(lvl.parcel.global_position + Vector3(0, 0.15, 0), 0.9)
	await shot("parcel_at_door")
	await press("interact")
	await t(1.4)
	await shot("parcel_carry")
	# 책상으로
	await walkw(B.call(1.0, 1.0, 0))
	var dt: Transform3D = lvl._desk_place_transform()
	await walkw(dt.origin + Vector3(0.05, 0, 0.72))
	await lookw(dt.origin, 0.7)
	await press("interact")
	await t(1.4)
	await lookw(lvl.parcel.global_position + Vector3(0, 0.1, 0), 0.5)
	await press("interact")
	await t(0.9)
	await shot("hand_open_parcel")
	await t(3.5)
	await shot("parcel_opened")
	# 메모 집어 읽기
	var memo := lvl.parcel.find_child("prop_memo", true, false) as Node3D
	if memo:
		await lookw(memo.global_position, 0.6)
		await press("interact")
		await t(1.6)
		await shot("inspect_memo_hand")
		await mouse(120, 0)
		await t(0.6)
		await press("interact")
		await t(1.0)
	var tape := lvl.parcel.find_child("prop_tape_1", true, false) as Node3D
	if tape:
		await lookw(tape.global_position, 0.6)
		await press("interact")
		await t(1.6)
		await shot("inspect_tape_hand")
		await mouse(-160, 40)
		await t(0.8)
		await shot("inspect_tape_rotated")
		await press("interact")
		await t(1.0)
	# 녹음기 들기 → R 테이프 넣기 → R 재생
	await lookw(lvl.recorder.global_position, 0.6)
	await press("interact")
	await t(1.2)
	await lookw(lvl.recorder.global_position + Vector3(0, -0.3, -1.0), 0.6)
	await press("recorder_play")
	await t(0.75)
	await shot("hand_tape_insert")
	await t(2.2)
	await press("recorder_play")
	await t(1.0)
	await shot("recorder_playing_hand")
	await wait_ev("EV03_tape_play", 20)
	await t(0.5)
	await press("recorder_play")        # 정지
	await wait_ev("EV04_voice_behind", 10)
	await t(1.6)
	await lookw(lvl.story_fx._behind, 1.1)
	await wait_ev("EV05_anomaly", 6)
	await t(2.5)
	await shot("ev05_anomaly_monitor")
	# 잠긴 문 → 정전
	await lookw(lvl.door_hinge.global_position + Vector3(0.75, 1.0, 0), 1.0)
	await walkw(B.call(0.95, 0.75, 0))
	await lookw(lever.global_position, 0.5)
	await press("interact")
	await wait_ev("EV06_blackout", 8)
	await t(1.5)
	await shot("ev06_blackout")
	await t(4.5)
	# 서랍 → 손전등
	var dr := lvl.find_child("stu_desk_drawer_0_front", true, false) as Node3D
	await walkw(dr.global_position + Vector3(0, 0, 0.75))
	await lookw(dr.global_position, 0.8)
	await shot("ev06_guide_light")
	await press("interact")
	await t(1.2)
	await lookw(lvl.flashlight_prop.global_position, 0.6)
	await press("interact")
	await t(1.5)
	await shot("inspect_flashlight_hand")
	await press("interact")
	await t(1.5)
	await press("flashlight")
	await t(0.6)
	await lookw(B.call(2.0, 3.0, 0.4), 1.0)
	await shot("flashlight_in_hand")
	await lookw(B.call(4.5, 4.0, 1.0), 1.4)
	await shot("flashlight_room")
	# EVENT 07: 문 앞 → 문틈 그림자
	await walkw(B.call(1.2, 1.4, 0))
	await lookw(lvl.door_hinge.global_position + Vector3(0.45, 0.05, -0.05), 0.8)
	await wait_started("EV07_silhouette", 15)
	await t(1.25)
	await shot("ev07_door_gap_shadow")
	await wait_ev("EV07_silhouette", 15)
	await walkw(B.call(0.95, 0.75, 0))
	await lookw(lever.global_position, 0.4)
	await press("interact")
	await wait_started("EV08_transition", 12)
	await t(4.0)
	await shot("ev08_apartment_soeun")
	await t(4.0)
	await shot("ev08_title_card")
	await t(5.0)
	print("TOUR DONE")
	get_tree().quit()
