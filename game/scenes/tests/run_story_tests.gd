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
	check(p.seated, "EV01: starts seated at the desk (11:47 PM)")
	await secs(7.0)
	check(not p.seated and p.global_position.distance_to(lvl.find_child("stu_chair", true, false).global_position) > 0.3, "EV01: headphones off, stands up, chair pushed back")
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
	check(await wait_done("EV02c_parcel", 6), "save: checkpoint 'parcel_obtained'")
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
	check(await wait_done("EV03_tape_play", 30), "EV03: tape 1 plays (소은 → 어린 정우 → 소은) then cuts off")
	check(SaveGame.read().checkpoint == "tape1_played", "save: checkpoint 'tape1_played'")
	check(ClueBook.found.has(&"clue_pro_tape01") and ClueBook.found.has(&"clue_pro_memo"), "clues: required prologue clues recorded")
	# EVENT 04: 녹음기 근처 → 문이 천천히 열리고 문틈에 존재
	p.global_position = lvl.recorder.global_position + Vector3(0.3, -0.8, 0.6)
	check(await wait_done("EV04_door_gap", 8), "EV04: door creeps open while player is at the recorder")
	await secs(2.5)
	check(lvl.door_ajar and lvl.monster_node != null and lvl.monster_node.visible, "EV04: presence visible in the door gap")
	check(not lvl.director.is_done("EV05_voice_behind"), "EV05: does not fire while door is still ajar")
	# 플레이어가 직접 문틈을 보고 다가간다 (카메라 강제 회전 없음 — 테스트가 시선을 옮김)
	var gap: Vector3 = lvl.door_gap_point()
	p.global_position = Vector3(gap.x - 0.2, 0.02, gap.z - 1.6)
	p.look_at_point(gap)
	await secs(1.5)
	check(not lvl.door_ajar and not lvl.monster_node.visible and not lvl.door_open, "EV04: door slams shut, nobody there")
	lvl.toggle_door()
	await secs(1.0)
	check(lvl.door_open and not lvl.monster_node.visible, "EV04: reopening the door shows nobody")
	lvl.toggle_door()
	await secs(1.0)
	# EVENT 05: 녹음기를 멈추면 약 3초 뒤 등 뒤에서 '정우야?'
	p.global_position = lvl.recorder.global_position + Vector3(0.3, -0.8, 0.6)
	p.look_at_point(lvl.recorder.global_position)
	lvl.recorder_key()
	check(await wait_done("EV05_voice_behind", 10), "EV05: '정우야?' behind the player after stop")
	var behind: Vector3 = lvl.story_fx._behind
	var to_b := (behind - p.camera.global_position)
	check(to_b.dot(-p.camera.global_transform.basis.z) < 0.0 and lvl.in_studio(behind), "EV05: voice source is behind player, inside the room")
	p.look_at_point(behind)
	check(await wait_done("EV05b_anomalies", 8), "EV05: anomalies when player turns around")
	await secs(3.0)
	check(lvl._self_play and p.held_recorder == null and lvl.recorder.global_position.distance_to(lvl._rec_home.origin) < 0.01, "EV05: recorder is back on the desk, spinning by itself")
	await secs(3.5)
	check(not lvl.clock_running and not lvl.story_fx.rain_on and lvl.door_locked, "EV05: clock 11:47 stop, rain stops, door locks",
			"clock=%s rain=%s locked=%s" % [lvl.clock_running, lvl.story_fx.rain_on, lvl.door_locked])
	# 시야 밖 변화: 녹음기 쪽을 보고 있는 동안 의자·테이프가 바뀐다
	p.look_at_point(lvl.recorder.global_position)
	await secs(3.0)
	var t4 := lvl.parcel.find_child("prop_tape_4", true, false) as Node3D
	check(t4 != null and not t4.visible, "EV05: one tape vanished from the box (off-sight)")
	lvl.toggle_door()
	check(await wait_done("EV06_blackout", 8), "EV06: blackout after trying locked door")
	await secs(0.6)
	check(not lvl.fx["StudioCeiling"].is_emitting() and not lvl.fx["DeskLamp"].is_emitting(), "EV06: all interior lights off")
	lvl.fx["StudioCeiling"].press_switch()
	lvl.fx["StudioCeiling"].press_switch()
	check(not lvl.fx["StudioCeiling"].is_emitting(), "EV06: switch does not turn light back on")
	check(not lvl.clue_tape.visible, "EV06: under-desk tape not there before flashlight")
	Inventory.add(&"flashlight")
	check(await wait_done("EV06b_flashlight", 6), "save: checkpoint 'flashlight_obtained'")
	check(p.arms.hand_mode("L") == ViewmodelArms.Mode.HOLD_FLASHLIGHT, "flashlight: held in left hand")
	await secs(1.3)
	check(lvl.clue_tape.visible, "EV07: missing tape now lies under the desk")
	# EVENT 07: 테이프를 집어 살펴보면 책상 너머에 소은의 얼굴
	p.global_position = lvl.clue_tape.global_position + Vector3(0, 0, 0.9)
	p.global_position.y = 0.02
	p.look_at_point(lvl.clue_tape.global_position)
	await frames(3)
	var cit := lvl.clue_tape.find_child("Interact", true, false) as Interactable
	p.inspect.open(cit)
	await secs(0.5)
	check(lvl.soeun_node != null and lvl.soeun_node.visible, "EV07: Soeun's face appears across the desk (3D model)")
	var dsx: Vector3 = lvl.soeun_node.global_position - p.global_position
	check(dsx.length() < 2.5, "EV07: Soeun is close, across the desk", "%.2f m" % dsx.length())
	p.inspect.flip()
	check(ClueBook.found.has(&"clue_pro_tape_back"), "clues: hidden clue on the tape's back side (flip)")
	await secs(2.0)
	check(not lvl.soeun_node.visible, "EV07: Soeun vanishes (no attack)")
	p.inspect.close(true)
	check(Inventory.has(&"cassette_unlabeled"), "EV07: tape taken")
	# EVENT 08: 문 밖 괴물 — 숨소리·노크→쾅쾅·손잡이 → 정적 → 잠금 해제
	check(await wait_done("EV08_monster_door", 30), "EV08: monster at the door, sudden silence, door unlocks")
	check(not lvl.door_locked, "EV08: door unlocked")
	lvl.set_meta("test_no_title", true)
	lvl.toggle_door()
	check(await wait_done("EV09_next_phase", 15), "EV09: opening the door ends this build (EVENT 09~12 next phase)")
	var st: Dictionary = SaveGame.read().state
	check(st.get("done", []).size() >= 10 and st.has("lights") and st.has("objects") and st.has("items") and st.has("clues"), "save: contains events, lights, objects, items, clues")
	check(lvl.director.started.size() == lvl.director.done.size(), "events: no event left half-run")
	var any_danger := false
	for k in lvl.director.presences:
		any_danger = any_danger or (lvl.director.presences[k] as GhostPresence).is_dangerous() or lvl.director.presences[k].can_attack
	check(lvl.director.presences.has("soeun") and lvl.director.presences.has("prologue_monster") and not any_danger, "ghosts: prologue presences are staging-only (cannot attack)")
	var gp := GhostPresence.from_event({"id": "t", "presence": "observe_far", "can_attack": false})
	gp.set_state(GhostPresence.State.CHASE)
	check(gp.state == GhostPresence.State.OBSERVE_FAR, "ghosts: staging ghost refuses CHASE state")
	Engine.time_scale = 1.0
	print("== %d passed, %d failed ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
