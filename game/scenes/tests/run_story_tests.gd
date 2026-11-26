extends Node
## 프롤로그 EVENT 01~08 흐름 자동 검증 (손 동작 포함, 헤드리스). 실제 화면 검토는 story_capture로 따로 한다.
## usage: godot --headless --path game res://scenes/tests/run_story_tests.tscn

var lvl: Node3D
var p: PlayerController
var passed := 0
var failed := 0

func check(c: bool, name: String, info := "") -> void:
	if c:
		passed += 1
		print("  PASS  ", name, ("  (" + info + ")") if info != "" else "")
	else:
		failed += 1
		print("  FAIL  ", name, "  ", info)

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func secs(t: float) -> void:
	await get_tree().create_timer(t).timeout

func wait_done(id: String, timeout := 30.0) -> bool:
	var t := 0.0
	while t < timeout:
		if lvl.director.is_done(id):
			return true
		await secs(0.25)
		t += 0.25
	return false

func _ready() -> void:
	_run()

func _run() -> void:
	print("== PROLOGUE story tests ==")
	Engine.time_scale = 3.0
	SaveGame.delete_save()
	Inventory.clear()
	lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lvl.force_story = true
	lvl.enable_thunder = false
	add_child(lvl)
	await frames(20)
	p = lvl.player
	check(lvl.director != null and lvl.director.events.size() >= 9, "events: loaded from JSON", "%d" % lvl.director.events.size())
	check(await wait_done("EV01_normal_studio", 5), "EV01: normal studio (lights on)")
	check(lvl.fx["StudioCeiling"].is_emitting(), "EV01: ceiling light working")
	check(not lvl.parcel.visible, "EV01: no parcel before knock")
	check(SaveGame.has_save() and SaveGame.read().checkpoint == "game_start", "save: checkpoint 'game_start'")
	# 튜토리얼: 걷기·둘러보기·조사 1회 (시간만으로는 노크가 오지 않는지 먼저 확인)
	await secs(5.0)
	check(not lvl.director.started.has("EV02_knock"), "EV02: knock does NOT fire on time alone")
	for i in 12:
		p.global_position += Vector3(0.35, 0, 0) * (1 if i < 6 else -1)
		p.set("_yaw", float(p.get("_yaw")) + 0.25)
		await frames(2)
	p.interacted_any.emit()
	check(await wait_done("EV02_knock", 20), "EV02: knock after tutorial actions")
	check(lvl.parcel.visible, "EV02: parcel appears at the door")
	# 문 열기 → 택배 들기
	lvl.toggle_door()
	await secs(1.2)
	check(lvl.door_open, "door: opened")
	var pit := lvl.parcel.find_child("ParcelInteract", false, false) as Interactable
	pit.action.call()
	await secs(1.5)
	check(p.carrying == lvl.parcel, "parcel: carried with both hands")
	check(await wait_done("EV02b_parcel", 6), "save: checkpoint 'parcel_obtained'")
	# 책상 앞으로 가서 내려놓기
	var desk_t: Transform3D = lvl._desk_place_transform()
	p.global_position = desk_t.origin + Vector3(0.1, -0.76, 0.75)
	await frames(3)
	p.try_interact()
	await secs(1.5)
	check(lvl.parcel_on_desk and p.carrying == null, "parcel: placed on desk")
	pit.action.call()
	await secs(4.0)
	check(lvl.parcel_open, "parcel: opened on desk (hands)")
	check(lvl.parcel.find_child("prop_tape_7", true, false) != null and lvl.parcel.find_child("prop_memo", true, false) != null,
			"parcel: memo + 7 tapes inside")
	Inventory.add(&"note_prologue")
	Inventory.add(&"tape_1")
	# 녹음기 들기 → R: 테이프 넣기 → R: 재생
	var rit := lvl.recorder.find_child("RecorderInteract", false, false) as Interactable
	rit.action.call()
	await secs(0.5)
	check(p.held_recorder == lvl.recorder, "recorder: held in right hand")
	lvl.recorder_key()
	await secs(3.0)
	check(lvl.recorder_state == "loaded", "recorder: tape 1 inserted by hand", lvl.recorder_state)
	lvl.recorder_key()
	check(await wait_done("EV03_tape_play", 20), "EV03: tape plays (laughter/swing → Soeun)")
	check(SaveGame.read().checkpoint == "tape1_played", "save: checkpoint 'tape1_played'")
	lvl.recorder_key()     # 정지
	check(await wait_done("EV04_voice_behind", 10), "EV04: voice behind the player ~3s after stop")
	var behind: Vector3 = lvl.story_fx._behind
	var to_b := (behind - p.camera.global_position)
	check(to_b.dot(-p.camera.global_transform.basis.z) < 0.0 and lvl.in_studio(behind), "EV04: voice source is behind player, inside the room")
	p.look_at_point(behind)
	check(await wait_done("EV05_anomaly", 8), "EV05: anomaly when player turns around")
	await secs(2.8)
	check(not lvl.clock_running and not lvl.story_fx.rain_on and lvl.door_locked, "EV05: clock stops, rain stops, door locks")
	lvl.toggle_door()
	check(await wait_done("EV06_blackout", 8), "EV06: blackout after trying locked door")
	await secs(0.6)
	check(not lvl.fx["StudioCeiling"].is_emitting() and not lvl.fx["DeskLamp"].is_emitting(), "EV06: all interior lights off")
	lvl.fx["StudioCeiling"].press_switch()
	lvl.fx["StudioCeiling"].press_switch()
	check(not lvl.fx["StudioCeiling"].is_emitting(), "EV06: switch does not turn light back on")
	Inventory.add(&"flashlight")
	check(await wait_done("EV06b_flashlight", 6), "save: checkpoint 'flashlight_obtained'")
	check(p.arms.hand_mode("L") == ViewmodelArms.Mode.HOLD_FLASHLIGHT, "flashlight: held in left hand")
	p.global_position = lvl.door_inside_point() + Vector3(0, -1.0, -0.6)
	check(await wait_done("EV07_silhouette", 15), "EV07: silhouette + voice + knock near door")
	check(not lvl.door_locked, "EV07: door unlocked")
	lvl.toggle_door()
	if not lvl.door_open:
		await secs(1.2)
	check(await wait_done("EV08_transition", 25), "EV08: transition to 1998 apartment corridor")
	check(lvl.apt != null and lvl.apt.bounds().grow(0.5).has_point(p.global_position), "EV08: player is in apartment corridor")
	check(SaveGame.read().checkpoint == "apt_entered", "save: checkpoint 'apt_entered'")
	var st: Dictionary = SaveGame.read().state
	check(st.get("done", []).size() >= 10 and st.has("lights") and st.has("objects") and st.has("items"), "save: contains events, lights, objects, items")
	check(lvl.director.started.size() == lvl.director.done.size(), "events: no event left half-run")
	var any_danger := false
	for k in lvl.director.presences:
		any_danger = any_danger or (lvl.director.presences[k] as GhostPresence).is_dangerous() or lvl.director.presences[k].can_attack
	check(lvl.director.presences.has("soeun_child") and not any_danger, "ghosts: prologue presences are staging-only (cannot attack)")
	var gp := GhostPresence.from_event({"id": "t", "presence": "observe_far", "can_attack": false})
	gp.set_state(GhostPresence.State.CHASE)
	check(gp.state == GhostPresence.State.OBSERVE_FAR, "ghosts: staging ghost refuses CHASE state")
	Engine.time_scale = 1.0
	print("== %d passed, %d failed ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
