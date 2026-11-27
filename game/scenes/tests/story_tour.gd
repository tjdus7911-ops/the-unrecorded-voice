extends Node
## 요구사항 16 공식 흐름 시연: 프롤로그 EVENT 01~10 → TAPE 01(1998) → 작업실 복귀 → TAPE 02 삽입.
## 실제 플레이어·상호작용·이벤트를 그대로 쓰고 입력(이동·E·R·F·시선)만 스크립트가 누른다.
## --part prologue|tape01 로 나눠 찍을 수 있다 (tape01은 apt_entered 저장에서 이어하기).
## 영상: godot --path game --rendering-driver vulkan --write-movie out.avi --fixed-fps 24 res://scenes/tests/story_tour.tscn
## 스크린샷: ... -- --out /tmp/story (각 장면에서 PNG 저장)

var lvl: Node3D
var p: PlayerController
var out := ""
var shots := 0

func _ready() -> void:
	GameFlow.auto_pause_on_focus_loss = false
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

func _lookw_once(pos: Vector3, dur: float) -> void:
	var d := pos - p.camera.global_position
	var cur: float = p.get("_yaw")
	var yaw := cur + wrapf(atan2(-d.x, -d.z) - cur, -PI, PI)
	var tw := create_tween().set_parallel()
	tw.tween_property(p, "_yaw", yaw, dur)
	tw.tween_property(p, "_pitch", atan2(d.y, Vector2(d.x, d.z).length()), dur)
	await t(dur)

func lookw(pos: Vector3, dur := 0.8) -> void:
	var d := pos - p.camera.global_position
	if p.leaning:
		# 몸을 숙인 상태에서는 머리가 몸 앞쪽에 있어 시선 회전 중 위치가 바뀐다 → 몸 중심 기준으로 근사 후 두 번 보정
		await _lookw_once(pos, dur * 0.6)
		d = pos - p.camera.global_position
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

## 키 입력 대신 같은 처리 함수를 직접 호출 (헤드리스에서도 동일 동작). 실제 OS 키 입력 경로는 tools/ci/input_test_x11.sh가 따로 검증한다.
func press(action: String) -> void:
	match action:
		"interact":
			if p.inspect.active:
				p.inspect.close(p.inspect.active.pickup_item != &"")
			else:
				p.try_interact()
		"recorder_play":
			p.recorder_key_pressed.emit()
		"flashlight":
			p.flashlight.toggle()
	await t(0.05)

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

func Bw(x: float, y: float, z := 0.0) -> Vector3:
	return lvl.b2g(Vector3(x, y, z))

func Aw(x: float, y: float, z := 0.0) -> Vector3:
	return lvl.apt.to_global(AptCorridor.b(Vector3(x, y, z)))

func interact_at(pos: Vector3, wait := 0.6) -> void:
	await lookw(pos, 0.5)
	var ray: RayCast3D = p.get("interact_ray") if p.get("interact_ray") else p.find_child("InteractRay", true, false)
	if ray:
		ray.force_raycast_update()
		print("TOUR interact -> ", ray.get_collider(), " dist ", p.camera.global_position.distance_to(pos))
	await press("interact")
	await t(wait)
	print("TOUR   after: target=", p.get("_interact_target"), " door_open=", lvl.door_open, " paused=", get_tree().paused, " state=", GameFlow.state, " carrying=", p.carrying, " inspect=", p.inspect.active)

## 특정 물건을 보고 조사 화면을 연다 (상자 안 작은 물건은 조준이 덮개·운송장에 걸리기 쉬워 대상 지정)
func inspect_obj(node: Node3D, wait := 1.2) -> void:
	await lookw(node.global_position, 0.5)
	var it := node.find_child("*Interact*", true, false) as Interactable
	if it == null:
		for c in node.find_children("*", "Interactable", true, false):
			it = c
	if it:
		p.inspect.open(it)
	await t(wait)

func _run() -> void:
	var part := "all"
	var args := OS.get_cmdline_user_args()
	if args.has("--part"):
		part = args[args.find("--part") + 1]
	if part == "tape01":
		SaveGame.pending = SaveGame.read()
		GameFlow.start_mode = "continue"
	else:
		SaveGame.delete_save()
		Inventory.clear()
	lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lvl.force_story = true
	lvl.enable_thunder = true
	add_child(lvl)
	p = lvl.player
	await t(1.5)
	if part != "tape01":
		await _prologue()
	if part != "prologue":
		await _tape01()
	print("TOUR DONE")
	get_tree().quit()

func _prologue() -> void:
	var d: EventDirector = lvl.director
	# EVENT 01 — 평범한 작업실
	await t(2.0)
	await shot("ev01_studio_normal")
	await mouse(-260, 0, 40)
	await walkw(Bw(3.2, 2.6), 3.0)
	await mouse(380, -20, 50)
	await walkw(Bw(2.2, 3.3), 3.0)
	p.interacted_any.emit()
	await wait_started("EV02_knock", 30)
	await t(0.4)
	await shot("ev02_knock")
	await t(2.6)
	# EVENT 02 — 문을 열면 택배
	var door_in: Vector3 = lvl.door_inside_point()
	await walkw(door_in + Vector3(0, 0, -0.12), 5.0)
	await interact_at(door_in + Vector3(0, 0.2, 0), 1.6)
	await lookw(lvl.parcel.global_position, 0.7)
	await wait_ev("EV02b_parcel_seen", 6)
	await shot("ev02_parcel_at_door")
	var pp: Vector3 = lvl.parcel.global_position
	await walkw(pp + (door_in - pp) * Vector3(1, 0, 1).normalized() * 0.75, 3.0)
	await interact_at(pp, 1.8)
	print("TOUR carrying parcel: ", p.carrying == lvl.parcel)
	var desk: Transform3D = lvl._desk_place_transform()
	await walkw(desk.origin + Vector3(0.05, 0, 0.72), 6.0)
	await lookw(desk.origin, 0.5)
	await press("interact")
	await t(1.4)
	await press("interact")
	await t(4.2)
	print("TOUR box: on_desk=", lvl.parcel_on_desk, " open=", lvl.parcel_open, " carrying=", p.carrying)
	await shot("ev03_box_open")
	var memo := lvl.parcel.find_child("prop_memo", true, false) as Node3D
	await inspect_obj(memo, 1.4)
	await shot("ev03_letter")
	await t(2.2)
	await press("interact")
	await t(0.8)
	var tape1 := lvl.parcel.find_child("prop_tape_1", true, false) as Node3D
	await inspect_obj(tape1, 1.2)
	await press("interact")
	await t(0.8)
	print("TOUR items: ", Inventory.items, " ev03=", lvl.director.is_done("EV03_letter"))
	# EVENT 04 — 첫 번째 녹음 → 등 뒤 문이 쾅
	await walkw(lvl.recorder.global_position + Vector3(0.1, 0, 0.62), 4.0)
	await interact_at(lvl.recorder.global_position, 3.2)
	print("TOUR recorder: ", lvl.recorder_state, " tape=", lvl.recorder_tape_no)
	await shot("ev04_tape_inserted")
	await press("recorder_play")
	await t(9.3)
	await shot("ev04_soeun_on_tape")
	await t(DialogueDB.duration_of("PRO_E04_T01") - 0.2)
	await t(0.5)
	await lookw(lvl.door_inside_point() + Vector3(0, 0.9, 0), 0.5)
	await shot("ev04_door_slammed")
	await t(1.5)
	# EVENT 05 — 잠긴 문 · 조용해짐 · 정지 후 등 뒤 목소리
	await walkw(lvl.door_inside_point() + Vector3(0, 0, -0.12), 5.0)
	await interact_at(lvl.door_inside_point() + Vector3(0, 0.2, 0), 1.0)
	await shot("ev05_locked")
	await t(4.0)
	await walkw(lvl.recorder.global_position + Vector3(0.1, 0, 0.62), 5.0)
	await lookw(lvl.recorder.global_position, 0.5)
	await press("recorder_play")
	await t(3.4)
	await shot("ev05_voice_behind")
	await t(0.6)
	await lookw(lvl.story_fx._behind, 1.1)
	await wait_ev("EV05c_nobody", 6)
	await shot("ev05_nobody")
	# EVENT 06 — 깜빡임 → 정전
	await wait_started("EV06_blackout", 12)
	await lookw(lvl.story_fx.point("ceiling"), 0.6)
	await t(1.0)
	await shot("ev06_flicker")
	await t(1.2)
	await lookw(Bw(3.0, 2.5, 1.2), 0.6)
	await shot("ev06_blackout")
	await t(3.5)
	# 스위치는 반응 없음
	var sw := lvl.find_child("stu_light_switch", true, false) as Node3D
	if sw:
		await walkw(sw.global_position + (lvl.door_inside_point() - sw.global_position).normalized() * 0.2 + Vector3(0.3, 0, 0.5), 5.0)
		await interact_at(sw.global_position, 1.0)
	var dr := lvl.find_child("stu_desk_drawer_0", true, false) as Node3D
	await walkw(dr.global_position + Vector3(0.0, 0, 0.75), 6.0)
	await interact_at(dr.global_position + Vector3(0, 0.05, 0.1), 1.2)
	await shot("ev06_drawer_open")
	if lvl.flashlight_prop and is_instance_valid(lvl.flashlight_prop):
		await interact_at(lvl.flashlight_prop.global_position, 1.0)     # 요구사항 20: E 한 번에 획득
		await t(0.6)
	await press("flashlight")
	await t(1.0)
	await lookw(Bw(3.0, 2.5, 1.0), 0.8)
	await shot("ev06_flashlight_on")
	# EVENT 07 — 문 밖 '정우야... 여기야.' · 노크 · 잠금 해제
	await walkw(lvl.door_inside_point() + Vector3(0, 0, -0.12), 6.0)
	await lookw(lvl.door_inside_point() + Vector3(0, 0.6, 0.4), 0.5)
	await wait_ev("EV07_door_voice", 12)
	await shot("ev07_unlocked")
	await interact_at(lvl.door_inside_point() + Vector3(0, 0.2, 0), 1.6)
	# EVENT 08 — 정전된 복도: 손전등으로 끝을 비추면 등 돌린 소은 → 손전등 깜빡 → 없음 → 2초 정적
	await walkw(Bw(0.95, -1.15), 4.0)
	await lookw(lvl.story_fx.point("soeun_corridor") + Vector3(0, -0.25, 0), 1.2)
	await t(0.3)
	await shot("ev08_soeun_lit")
	await wait_started("EV08_soeun_corridor", 10)
	await t(1.6)
	await shot("ev08_gone")
	# STEP 03 — 뒤에서 떨어지는 소리 → 돌아보면 모퉁이(화장실 통로)에서 머리·어깨
	await wait_started("EV08b_drop", 8)
	await t(0.6)
	var st: StoryStaging = lvl.story_fx.st()
	await lookw(st.point("monster_corner"), 1.0)
	await wait_started("EV09_monster_seen", 10)
	await t(0.3)
	await shot("ev09_corner_peek")
	# STEP 04 — 걸어 나와 몸을 돌리고 멈춘다
	await t(2.6)
	await lookw(st.noise.global_position + Vector3(0, 1.4, 0), 0.4)
	await shot("ev09_walks_out")
	await wait_started("EV09b_chase", 10)
	await t(0.4)
	await shot("ev09_starts_running")
	# STEP 05 — 동쪽으로 도망 · 한 번 돌아보면 실제로 달려오는 모습
	await lookw(Bw(10.0, -1.1, 1.4), 0.5)
	Input.action_press("sprint")
	await walkw(Bw(4.5, -1.1), 4.0)
	Input.action_release("sprint")
	await lookw(st.noise.global_position + Vector3(0, 1.3, 0), 0.35)
	await t(0.25)
	await shot("ev10_look_back_chase")
	await lookw(Bw(11.0, -1.1, 1.4), 0.35)
	Input.action_press("sprint")
	await walkw(Bw(10.8, -1.1), 5.0)
	Input.action_release("sprint")
	# STEP 06 — 지정 구간: 손전등 깜빡 → 꺼짐 → 정적 → '찾았다.' → 암전 → 1998
	await wait_started("EV10_transition", 8)
	await t(0.8)
	await shot("ev10_flicker")
	await t(1.9)
	await shot("ev10_dark_found")
	await wait_ev("EV10_transition", 25)
	await shot("ev10_1998")

func _tape01() -> void:
	await t(0.5)
	var apt: AptCorridor = lvl.apt
	if apt == null:
		return
	await shot("t01_corridor_1998")
	await lookw(Aw(12.0, -6.0, 0.4), 1.2)
	await t(0.6)
	await lookw(Aw(20.0, 0.9, 1.3), 1.0)
	# 복도 → 계단실 → 현관 → 놀이터
	await walkw(Aw(23.6, 0.85), 12.0)
	await walkw(Aw(25.0, 0.6), 3.0)
	await walkw(Aw(25.1, -0.6), 3.0)
	await walkw(Aw(25.1, -2.2), 3.0)
	await lookw(Aw(9.5, -9.5, 0.3), 0.8)
	await shot("t01_playground_from_entrance")
	await walkw(Aw(13.6, -8.2), 14.0)
	await lookw(apt.point("apt_swing") + Vector3(0, -0.6, 0), 0.6)
	await wait_started("T01_frag1_swing", 6)
	await t(1.4)
	await shot("t01_swing_moves")
	await wait_ev("T01_frag1_swing", 12)
	# 계단: 위층 발소리 → 올라가면 아무도 없음
	await walkw(Aw(25.1, -2.2), 14.0)
	await walkw(Aw(25.1, -0.4), 3.0)
	await walkw(Aw(25.5, 1.6), 3.0)
	await lookw(Aw(25.6, 5.0, 2.2), 0.6)
	await wait_started("T01_frag2_steps", 6)
	await t(0.8)
	await shot("t01_stairs_steps")
	await walkw(Aw(25.55, 4.6), 5.0)
	await walkw(Aw(26.3, 5.0), 3.0)
	await lookw(Aw(26.75, 2.0, 2.9), 0.7)
	await wait_ev("T01_frag2_nobody", 6)
	await shot("t01_landing_nobody")
	# 내려와 복도로 → 104호 앞 녹음
	await walkw(Aw(25.55, 4.6), 3.0)
	await walkw(Aw(25.55, 1.4), 5.0)
	await walkw(Aw(23.0, 0.85), 4.0)
	await walkw(Aw(14.6, 0.75), 10.0)
	await lookw(Aw(14.0, -3.0, 0.6), 0.8)
	await wait_started("T01_frag3_recording", 6)
	await t(4.0)
	await shot("t01_recording")
	await wait_ev("T01_frag3_recording", 16)
	await t(1.0)
	await lookw(apt.point("apt_soeun_end") + Vector3(0, 1.0, 0), 1.6)
	await t(0.3)
	await shot("t01_soeun_end")
	await wait_ev("T01_soeun_end", 8)
	await shot("t01_soeun_gone")
	await wait_ev("T01_end", 14)
	await t(0.6)
	await shot("t01_back_in_studio")
	await lookw(lvl.photo.global_position, 0.9)
	await wait_ev("T01_photo_seen", 8)
	await shot("t01_photo_on_keyboard")
	await walkw(lvl.photo.global_position + Vector3(0.05, 0, 0.6), 3.0)
	await inspect_obj(lvl.photo, 1.6)
	await shot("t01_photo_inspect")
	await t(2.4)
	await press("interact")
	await t(0.8)
	# TAPE 01 꺼내기 → TAPE 02 넣기
	await walkw(lvl.recorder.global_position + Vector3(0.1, 0, 0.62), 3.0)
	await interact_at(lvl.recorder.global_position, 1.8)
	await shot("t01_tape_ejected")
	var t2 := lvl.parcel.find_child("prop_tape_2", true, false) as Node3D
	var desk: Transform3D = lvl._desk_place_transform()
	await walkw(desk.origin + Vector3(0.05, 0, 0.72), 4.0)
	await inspect_obj(t2, 1.2)
	await press("interact")
	await t(0.8)
	await walkw(lvl.recorder.global_position + Vector3(0.1, 0, 0.62), 4.0)
	await interact_at(lvl.recorder.global_position, 3.4)
	await shot("t02_inserted")
	await t(3.0)
	await shot("t02_ready_card")
	print("TAPES done=", lvl.tapes_done, " rec=", lvl.recorder_tape_no)
