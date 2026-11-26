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
	if Vector2(goal.x - p.global_position.x, goal.z - p.global_position.z).length() > 0.25:
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
	lvl.set_meta("test_no_title", true)
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
	if OS.get_cmdline_user_args().has("--debug-figure"):
		p.set_seated(false)
		lvl.door_hinge.rotation.y = deg_to_rad(100)
		lvl.door_open = true
		p.global_position = B.call(0.95, -0.75, 0)
		await lookw(lvl.story_fx.point("corridor_end"), 0.3)
		lvl.show_monster_at("corridor_end", 3.0)
		await t(0.5)
		await shot("dbg_corridor_figure")
		p.camera.fov = 25.0
		await t(0.3)
		await shot("dbg_corridor_figure_zoom")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--debug-gap"):
		p.set_seated(false)
		p.global_position = lvl.recorder.global_position + Vector3(0.3, -lvl.recorder.global_position.y, 0.6)
		await t(0.3)
		lvl.door_creep(20.0, 0.5)
		lvl.presence_in_gap(true)
		await t(1.0)
		var g: Vector3 = lvl.door_gap_point()
		await lookw(g, 0.4)
		await shot("dbg_gap_far")
		p.global_position = Vector3(g.x - 0.3, 0.0, g.z - 2.2)
		await lookw(g, 0.3)
		await shot("dbg_gap_near")
		p.camera.fov = 30.0
		await t(0.2)
		await shot("dbg_gap_zoom")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--debug-peek"):
		# EVENT 07 소은 얼굴 (정전 + 손전등 상태 재현)
		p.set_seated(false)
		for n in ["StudioCeiling", "DeskLamp", "FloorLamp"]:
			lvl.set_light(n, "off", true)
		Inventory.add(&"flashlight")
		await t(1.0)
		lvl.show_under_desk_tape()
		var ct: Vector3 = lvl.clue_tape.global_position
		p.global_position = Vector3(ct.x + 0.35, 0.0, ct.z + 0.8)
		if not p.flashlight.is_on:
			await press("flashlight")
		Input.action_press("crouch")
		await t(1.0)
		await lookw(ct, 0.4)
		await shot("dbg_peek_tape")
		lvl.soeun_peek(3.0)
		await t(0.3)
		await lookw(lvl.soeun_node.global_position + Vector3(0, 1.05, 0), 0.3)
		await shot("dbg_peek_soeun")
		p.camera.fov = 40.0
		await t(0.2)
		await shot("dbg_peek_soeun_zoom")
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
	# ---- EVENT 01: 11:47 PM — 앉아서 작업 → 헤드폰을 벗고 일어선다
	await t(1.0)
	await shot("ev01_seated_desk")
	await t(1.75)
	await shot("ev01_headphones_off")
	await t(3.0)
	await shot("ev01_stood_up")
	if OS.get_cmdline_user_args().has("--intro-only"):
		await lookw(B.call(2.6, 3.0, 1.0), 0.8)
		await shot("ev01_chair_pushed")
		get_tree().quit()
		return
	await lookw(B.call(3.2, 5.0, 1.4), 1.6)
	await walkw(B.call(3.6, 3.4, 0))
	await lookw(B.call(5.0, 1.5, 1.0), 1.2)
	await walkw(B.call(3.4, 1.6, 0))
	await lookw(B.call(0.3, 3.0, 1.2), 1.4)
	await walkw(B.call(1.6, 1.0, 0))
	var sw := lvl.find_child("stu_light_switch", true, false) as Node3D
	if sw:
		await lookw(sw.global_position, 0.8)
		await press("interact")
		await t(1.4)
		await press("interact")
		await t(1.3)
	await lookw(B.call(2.5, 4.0, 1.0), 1.2)
	await wait_ev("EV02_knock", 30)
	await t(0.4)
	# ---- EVENT 02: 노크 → 문 열기 → 복도 끝 형체 → 택배
	await lookw(lvl.door_hinge.global_position + Vector3(0.75, 1.0, 0), 1.0)
	await t(2.0)
	await walkw(B.call(0.95, 0.75, 0))
	var lever := lvl.door_hinge.find_child("stu_door_lever_in", true, false) as Node3D
	await lookw(lever.global_position, 0.6)
	await press("interact")
	await t(1.4)
	await walkw(B.call(0.95, -0.75, 0))
	await lookw(lvl.story_fx.point("corridor_end"), 0.7)
	await t(0.3)
	await shot("ev02_corridor_figure")
	await t(2.5)
	await shot("ev02_figure_gone")
	await lookw(lvl.parcel.global_position + Vector3(0, 0.15, 0), 0.9)
	await shot("parcel_at_door")
	await press("interact")
	await t(1.4)
	await shot("parcel_carry")
	await walkw(B.call(1.0, 1.0, 0))
	var dt: Transform3D = lvl._desk_place_transform()
	await walkw(dt.origin + Vector3(0.05, 0, 0.72))
	await lookw(dt.origin, 0.7)
	await press("interact")
	await t(1.4)
	await lookw(lvl.parcel.global_position + Vector3(0, 0.1, 0), 0.5)
	await press("interact")
	await t(4.4)
	await shot("parcel_opened")
	# ---- EVENT 03: 메모 → 녹음기 → TAPE 1
	var memo := lvl.parcel.find_child("prop_memo", true, false) as Node3D
	if memo:
		await lookw(memo.global_position, 0.6)
		await press("interact")
		await t(1.6)
		await shot("ev03_memo")
		await press("interact")
		await t(1.5)
	var tape := lvl.parcel.find_child("prop_tape_1", true, false) as Node3D
	if tape:
		await lookw(tape.global_position, 0.6)
		await press("interact")
		await t(1.6)
		await shot("inspect_tape_hand")
		await press("interact")
		await t(1.2)
	await lookw(lvl.recorder.global_position, 0.6)
	await press("interact")
	await t(1.2)
	await lookw(lvl.recorder.global_position + Vector3(0, -0.3, -1.0), 0.6)
	await press("recorder_play")
	await t(3.0)
	await press("recorder_play")
	await t(1.0)
	await shot("ev03_tape_playing")
	await wait_ev("EV03_tape_play", 25)
	# ---- EVENT 04: 녹음기 앞에 있는 동안 문이 천천히 열린다 → 플레이어가 직접 돌아본다
	await wait_started("EV04_door_gap", 10)
	await t(5.0)
	var gap: Vector3 = lvl.door_gap_point()
	await lookw(gap, 1.4)
	await t(0.3)
	await shot("ev04_door_gap_presence")
	await walkw(Vector3(gap.x - 0.1, 0, gap.z - 1.7), 3.0)
	await lookw(lvl.door_gap_point(), 0.3)
	await t(0.6)
	await shot("ev04_door_slammed")
	await t(2.0)
	await walkw(B.call(0.95, 0.75, 0))
	await lookw(lever.global_position, 0.5)
	await press("interact")
	await t(1.6)
	await lookw(B.call(0.95, -1.4, 1.2), 0.5)
	await shot("ev04_reopen_nobody")
	await press("interact")
	await t(1.2)
	# ---- EVENT 05: 녹음기 정지 → 등 뒤 '정우야?' → 돌아보면 아무도 없고 녹음기가 혼자 돈다
	await walkw(dt.origin + Vector3(0.05, 0, 0.72))
	await lookw(lvl.recorder.global_position, 0.6)
	await press("recorder_play")
	await wait_ev("EV05_voice_behind", 10)
	await t(0.5)
	await lookw(lvl.story_fx._behind, 1.1)
	await t(1.0)
	await shot("ev05_nobody_behind")
	await lookw(lvl.recorder.global_position, 1.0)
	await t(2.0)
	await shot("ev05_recorder_self")
	await t(4.0)
	await lookw(lvl.parcel.global_position + Vector3(0, 0.1, 0), 0.7)
	await shot("ev05_tape_missing")
	# ---- EVENT 06: 잠긴 문 → 정전
	await walkw(B.call(0.95, 0.75, 0))
	await lookw(lever.global_position, 0.5)
	await press("interact")
	await wait_ev("EV06_blackout", 8)
	await t(1.5)
	await shot("ev06_blackout")
	await t(6.0)
	var dr := lvl.find_child("stu_desk_drawer_0_front", true, false) as Node3D
	await walkw(dr.global_position + Vector3(0, 0, 0.75))
	print("DBG drawer walk pos=", p.global_position)
	await lookw(dr.global_position, 0.8)
	await press("interact")
	await t(1.2)
	await lookw(lvl.flashlight_prop.global_position, 0.6)
	await press("interact")
	await t(1.5)
	await press("interact")
	await t(1.5)
	await press("flashlight")
	await t(1.5)
	await shot("ev06_flashlight")
	# ---- EVENT 07: 책상 아래 테이프 → 집는 순간 소은의 얼굴
	await lookw(lvl.clue_tape.global_position, 1.2)
	await t(1.0)
	await shot("ev07_flashlight_finds_tape")
	var ct: Vector3 = lvl.clue_tape.global_position
	var away := Vector3(p.global_position.x - ct.x, 0, p.global_position.z - ct.z).normalized()
	await walkw(ct + away * 0.75)
	Input.action_press("crouch")
	await t(0.9)
	await lookw(lvl.clue_tape.global_position, 0.6)
	print("DBG clue target=", p._interact_target, " cam=", p.camera.global_position, " tape=", ct)
	await shot("ev07_tape_under_desk")
	await press("interact")
	await t(0.55)
	await shot("ev07_soeun_peek")
	await t(0.5)
	await shot("ev07_soeun_peek_b")
	await t(1.5)
	await mouse(0, 0)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	get_viewport().push_input(e)
	await t(1.0)
	await shot("ev07_tape_back_clue")
	Input.action_release("crouch")
	await press("interact")
	await t(1.0)
	# ---- EVENT 08: 문 밖 괴물 → 쾅쾅 → 정적 → 잠금 해제
	await lookw(lvl.door_hinge.global_position + Vector3(0.75, 1.0, 0), 1.2)
	await t(6.0)
	await shot("ev08_door_bang")
	await wait_ev("EV08_monster_door", 25)
	await walkw(B.call(0.95, 0.75, 0))
	await lookw(lever.global_position, 0.4)
	await press("interact")
	await wait_started("EV09_next_phase", 12)
	await t(3.0)
	await shot("ev09_card")
	print("TOUR DONE")
	get_tree().quit()
