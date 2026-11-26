extends Node
## PHASE 01 플레이 레벨 자동 테스트 (헤드리스):
##   godot --headless --fixed-fps 60 --path game res://scenes/tests/run_phase01_tests.tscn
## 자동 테스트는 기능 회귀 확인용이다. 그래픽·플레이 품질은 실제 화면 캡처로 따로 검토한다.

var lvl: Node3D
var p: PlayerController
var passed := 0
var failed := 0

func _ready() -> void:
	_run.call_deferred()

func check(cond: bool, name: String, detail := "") -> void:
	if cond:
		passed += 1
		print("  PASS  ", name, ("  (" + detail + ")") if detail != "" else "")
	else:
		failed += 1
		print("  FAIL  ", name, "  ", detail)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func bpos() -> Vector3:
	var g := p.global_position
	return Vector3(g.x, -g.z, g.y)

func place(b: Vector3, yaw_deg: float) -> void:
	p.global_position = Vector3(b.x, b.z + 0.05, -b.y)
	p.velocity = Vector3.ZERO
	p.set("_yaw", deg_to_rad(yaw_deg))
	await frames(4)

func walk(n: int, run := false) -> void:
	Input.action_press("move_forward")
	if run:
		Input.action_press("sprint")
	await frames(n)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await frames(8)

func look_b(b: Vector3) -> void:
	p.look_at_point(Vector3(b.x, b.z, -b.y))
	await frames(2)

func _run() -> void:
	print("== PHASE 01 level tests ==")
	Inventory.clear()
	lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lvl.enable_thunder = false
	add_child(lvl)
	await frames(30)
	p = lvl.player
	p.hands_animate = false        # 손 동작 없이 즉시 실행 (손 동작은 별도 테스트)

	# --- 입력 (P0: 마우스 시점) — GUI를 거치는 실제 입력 경로(push_input)로 검사 ---
	check(GameFlow.state == GameFlow.State.PLAYING, "input: game state PLAYING after level start")
	var hud_stops := 0
	for c in lvl.hud.find_children("*", "Control", true, false):
		if (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			hud_stops += 1
	check(hud_stops == 0, "input: HUD controls never intercept mouse", "%d blocking" % hud_stops)
	var yaw0: float = p.get("_yaw")
	var pitch0: float = p.get("_pitch")
	var mm_ev := InputEventMouseMotion.new()
	mm_ev.position = get_viewport().get_visible_rect().size * 0.5      # 캡처 모드처럼 화면 중앙 (조준점 위치)
	mm_ev.relative = Vector2(180, -60)
	mm_ev.screen_relative = Vector2(180, -60)
	get_viewport().push_input(mm_ev)
	await frames(2)
	check(absf(float(p.get("_yaw")) - yaw0) > 0.2 and absf(float(p.get("_pitch")) - pitch0) > 0.05,
			"input: mouse motion at screen center rotates camera (yaw+pitch)",
			"dyaw %.3f dpitch %.3f" % [float(p.get("_yaw")) - yaw0, float(p.get("_pitch")) - pitch0])
	GameFlow.pause()
	await frames(2)
	check(get_tree().paused and lvl.pause_menu.visible, "pause: ESC menu pauses tree and shows menu")
	var yaw1: float = p.get("_yaw")
	get_viewport().push_input(mm_ev)
	await frames(1)
	check(is_equal_approx(float(p.get("_yaw")), yaw1), "pause: mouse does not move camera while paused")
	GameFlow.resume()
	await frames(2)
	check(not get_tree().paused and GameFlow.state == GameFlow.State.PLAYING and not lvl.pause_menu.visible, "pause: resume returns to play")
	p.set("_yaw", yaw0)
	p.set("_pitch", pitch0)

	# --- 구성 ---
	check(lvl.stu != null and lvl.cor != null, "level: studio + corridor loaded in one scene (no loading)")
	var mm := lvl.find_children("Cassettes_*", "MultiMeshInstance3D", true, false)
	check(mm.size() == 2 and (mm[0] as MultiMeshInstance3D).multimesh.instance_count > 700, "optimization: shelf cassettes as MultiMesh (2 draws)",
			"%d instances" % ((mm[0] as MultiMeshInstance3D).multimesh.instance_count if mm.size() > 0 else 0))
	var meshes := lvl.find_children("*", "MeshInstance3D", true, false).size()
	check(meshes < 400, "optimization: mesh instances in level", "%d" % meshes)
	var emitters := lvl.find_children("*", "AudioStreamPlayer3D", true, false)
	var playing := 0
	for e in emitters:
		if (e as AudioStreamPlayer3D).playing:
			playing += 1
	check(playing >= 8, "sound: 3D ambient emitters playing", "%d playing" % playing)
	check(Sounds.has("step_wood") and Sounds.has("step_tile") and Sounds.has("sfx_door_open") and Sounds.has("amb_rain_window"),
			"sound: library loaded from audio.json")
	check(AudioServer.get_bus_index(&"RoomCorridor") >= 0, "sound: per-room reverb buses")
	check(DialogueDB.audio_of("PRO_S05_001") != null, "voice: sample attached to PRO_S05_001 via data")

	# --- 작업실 이동·발소리(나무) ---
	await place(Vector3(2.4, 2.0, 0), 0.0)
	check(p.is_on_floor(), "studio: player on floor")
	await walk(60)
	check(p.footsteps.steps_played > 0 and p.footsteps.last_surface == "wood", "footsteps: wood (decotile) in studio",
			p.footsteps.last_surface)
	await place(Vector3(4.6, 0.95, 0), 90.0)
	await walk(30)
	check(p.footsteps.last_surface == "rug", "footsteps: rug zone", p.footsteps.last_surface)

	# --- 작업실 충돌 (벽·가구) ---
	await place(Vector3(1.0, 1.0, 0), 0.0)
	await walk(300)
	check(bpos().y < 5.0 - 0.27 and bpos().y > 4.5, "collision: north wall", "y=%.2f" % bpos().y)
	await place(Vector3(3.0, 2.6, 0), 0.0)
	await walk(300)
	check(bpos().y < 4.055 - 0.25, "collision: desk", "y=%.2f" % bpos().y)
	await place(Vector3(3.0, 3.0, 0), 90.0)
	await walk(400)
	check(bpos().x > 0.32 + 0.25, "collision: cassette shelf", "x=%.2f" % bpos().x)
	await place(Vector3(3.6, 2.0, 0), -90.0)
	await walk(400)
	check(bpos().x < 4.2, "collision: coffee table", "x=%.2f" % bpos().x)

	# --- 문 닫힘: 복도로 못 나감 + 복도 소리 차폐 ---
	await place(Vector3(0.95, 1.2, 0), 180.0)
	await walk(200)
	check(bpos().y > -0.05, "door closed: blocks exit", "y=%.2f" % bpos().y)
	var hum: AmbientEmitter = null
	for e in lvl.find_children("*", "AmbientEmitter", true, false):
		if (e as AmbientEmitter).sound_id == "amb_fluorescent_hum" and e.global_position.x > 2.0 and e.global_position.x < 3.0:
			hum = e
	await frames(20)
	var occ_closed: float = hum.occlusion if hum else -1.0
	check(hum != null and occ_closed >= 0.75, "occlusion: corridor hum muffled while door closed", "%.2f" % occ_closed)
	# --- 문 열기 → 복도로 이동 (로딩 없음) ---
	await place(Vector3(0.95, 0.35, 0), 180.0)
	await look_b(Vector3(1.2, 0.0, 1.0))
	check(p.try_interact() or lvl.door_open, "interact: door")
	await frames(90)
	check(lvl.door_open, "door: opened (hinge animation)")
	await place(Vector3(0.95, 0.3, 0), 180.0)     # 문이 열리며 밀려난 플레이어를 문간에 다시 세움
	await frames(30)
	check(hum != null and hum.occlusion < occ_closed, "occlusion: less muffled with door open",
			"closed %.2f -> open %.2f, player at %s, hum at %s" % [occ_closed, hum.occlusion if hum else -1.0, bpos(), hum.global_position if hum else Vector3.ZERO])
	await place(Vector3(0.95, 0.7, 0), 180.0)
	await walk(150)
	check(bpos().y < -0.25, "walk: studio → corridor through doorway (past wall plane)", "y=%.2f" % bpos().y)
	await place(Vector3(4.0, -1.1, 0), -90.0)
	await walk(60)
	check(p.footsteps.last_surface == "tile", "footsteps: corridor tile", p.footsteps.last_surface)
	await place(Vector3(13.73, -0.6, 0), 0.0)
	await walk(150)
	check(bpos().z < -0.4, "stairs: walk down the stair flight", "z=%.2f" % bpos().z)
	check(p.footsteps.last_surface == "concrete", "footsteps: terrazzo stairs", p.footsteps.last_surface)
	check(not lvl.fx["StairDown"].any_light_visible(), "lights: lower landing light is dead (dark area)")

	# --- 계단참 어둠 속 열쇠 ---
	await place(Vector3(13.7, 2.4, -1.7), 0.0)
	var keys := lvl.find_child("prop_keys", true, false) as Node3D
	if keys:
		await look_b(Vector3(keys.global_position.x, -keys.global_position.z, keys.global_position.y))
	check(p.try_interact() and p.inspect.is_open(), "dark clue: keys inspectable on dark landing")
	p.inspect.close(true)
	await frames(3)
	check(Inventory.has(&"keys_stairwell"), "dark clue: keys picked up")

	# --- 스위치·스탠드 ---
	await place(Vector3(1.62, 0.8, 0), 180.0)
	await look_b(Vector3(1.62, 0.0, 1.25))
	var before: bool = lvl.fx["StudioCeiling"].switched_on
	p.try_interact()
	await frames(3)
	check(lvl.fx["StudioCeiling"].switched_on != before and lvl.fx["StudioCeiling"].any_light_visible(), "light switch: ceiling panels on")
	p.try_interact()
	await frames(3)
	check(not lvl.fx["StudioCeiling"].any_light_visible(), "light switch: ceiling panels off")
	lvl.fx["DeskLamp"].press_switch()
	check(not lvl.fx["DeskLamp"].any_light_visible(), "desk lamp: toggle off")
	lvl.fx["DeskLamp"].press_switch()

	# --- 손전등 획득: 책상 맨 위 서랍 안 (서랍을 열어야 집을 수 있다) ---
	var flp: Node3D = lvl.flashlight_prop
	check(flp != null and flp.get_parent().name == "stu_desk_drawer_0", "flashlight: stored in desk drawer")
	var fit := flp.find_child("FlashlightInteract", false, false) as Interactable
	await frames(2)
	check(fit != null and not fit.enabled, "flashlight: not reachable while drawer closed")
	var dr_it := lvl.find_child("stu_desk_drawer_0", true, false).find_child("Interact", true, false) as Interactable
	dr_it.interact(p)
	await frames(40)
	check(lvl.drawer_open[0] and fit.enabled, "flashlight: drawer opened → reachable")
	var fg := flp.global_position
	await place(Vector3(fg.x, -fg.z - 0.75, 0), 0.0)
	await look_b(Vector3(fg.x, -fg.z, fg.y))
	check(p.try_interact() and p.inspect.is_open(), "flashlight: inspect view opens")
	p.inspect.close(true)
	await frames(3)
	check(Inventory.has_flashlight, "flashlight: acquired")
	check(p.flashlight.toggle() and p.flashlight.is_on, "flashlight: F on (after pickup)")
	check(p.flashlight.spot.light_projector != null, "flashlight: projector pattern applied")
	p.flashlight.toggle()

	# --- 택배 상자 열기 → 테이프·메모 ---
	lvl._parcel_open()
	await frames(260)
	check(lvl.parcel_open, "parcel: opened (flaps animated)")
	var seal := lvl.parcel.find_child("prop_parcel_seal_tape", true, false) as Node3D
	check(seal != null and not seal.visible, "parcel: seal tape removed")
	var tape := lvl.parcel.find_child("prop_tape_3", true, false) as Node3D
	var tit := tape.get_node_or_null("Interact") as Interactable
	check(tit != null and tit.inspectable, "parcel: tapes become inspectable after opening")
	p.inspect.open(tit)
	p.inspect.close(true)
	await frames(3)
	check(Inventory.has(&"tape_3"), "tape 3 picked up")

	# --- 녹음기: 테이프 삽입 → 재생 → 정지 ---
	await place(Vector3(2.55, 3.75, 0), 0.0)
	lvl._recorder_use()
	await frames(150)
	check(lvl.recorder_state == "loaded", "recorder: tape inserted (door/insert animation)", lvl.recorder_state)
	lvl._recorder_use()
	await frames(10)
	check(lvl.recorder_state == "playing" and lvl.motor.playing, "recorder: playing with motor sound")
	await frames(140)
	check(lvl._reels.size() == 2, "recorder: tape reels spinning")
	lvl._recorder_use()
	await frames(5)
	check(lvl.recorder_state == "loaded" and not lvl.motor.playing, "recorder: stop")

	# --- 데크 도어 ---
	lvl._deck_toggle()
	await frames(30)
	check(lvl.deck_open, "tape deck: door opens")

	# --- 호흡·심장 박동 (레벨 안에서) ---
	p.danger = 1.0
	await frames(300)
	check(p.breathing.state == &"fear" and p.heartbeat.current_bpm() > 110.0, "breathing/heartbeat: fear state in level")
	p.danger = 0.0

	print("== %d passed, %d failed ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
