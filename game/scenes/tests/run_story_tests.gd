extends Node
## 요구사항 16 공식 흐름 자동 검증: 프롤로그 EVENT 01~10 → TAPE 01(1998) → 작업실 복귀 → TAPE 02 삽입 → 이어하기 (헤드리스).
## 실제 화면 검수는 story_tour(영상)·qa_capture로 따로 한다 — 이 테스트 통과만으로 플레이 검수 완료로 보지 않는다.
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

func B(x: float, y: float, z := 0.0) -> Vector3:
	return lvl.b2g(Vector3(x, y, z))

func stand(at: Vector3, look: Vector3) -> void:
	p.global_position = Vector3(at.x, at.y + 0.02, at.z)
	p.velocity = Vector3.ZERO
	await frames(2)
	p.look_at_point(look)
	await frames(2)

## 복도를 동쪽으로 걸어가는 것처럼 (velocity를 줘서 따라오는 발소리 판정)
func walk_x(from_x: float, to_x: float, y := -1.1, step := 0.35) -> void:
	var x := from_x
	while x < to_x:
		x += step
		p.global_position = B(x, y, 0.02)
		p.velocity = Vector3(3.0, 0, 0)
		p.look_at_point(B(x + 5.0, y, 1.6))
		await secs(0.12)
	p.velocity = Vector3.ZERO

func _run() -> void:
	print("== PROLOGUE + TAPE 01 story tests (req 16) ==")
	Engine.time_scale = 3.0
	SaveGame.delete_save()
	Inventory.clear()
	lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lvl.force_story = true
	lvl.enable_thunder = false
	add_child(lvl)
	await frames(20)
	p = lvl.player
	var d: EventDirector = lvl.director
	check(d != null and d.by_id.has("EV10b_transition") and d.by_id.has("T01_end"), "events: prologue + tape01 JSON loaded", "%d" % d.events.size())
	# ---------------- EVENT 01
	check(await wait_done("EV01_normal_studio", 14), "EV01: normal studio")
	check(lvl.lighting == "normal" and lvl.fx["StudioCeiling"].is_emitting(), "EV01: lighting=normal")
	check(not p.seated, "EV01: no seated intro (req 16 has none)")
	check(SaveGame.read().checkpoint == "game_start", "save: checkpoint 'game_start'")
	check(not d.started.has("EV02_knock"), "EV02: knock does NOT fire before tutorial actions")
	for i in 14:
		p.global_position += Vector3(0.35, 0, 0) * (1 if i < 7 else -1)
		p.set("_yaw", float(p.get("_yaw")) + 0.25)
		await frames(2)
	p.interacted_any.emit()
	# ---------------- EVENT 02
	check(await wait_done("EV02_knock", 25), "EV02: knock ×3 after tutorial")
	check(lvl.parcel.visible and not lvl.door_open, "EV02: parcel outside, door still closed (player opens it)")
	lvl.toggle_door()
	await secs(1.2)
	check(lvl.door_open, "EV02: player opened the door")
	await stand(lvl.door_inside_point() + Vector3(0, -1.0, 0), lvl.parcel.global_position)
	check(await wait_done("EV02b_parcel_seen", 6), "EV02: '이 시간에 택배가...?' when the parcel is seen")
	var pit := lvl.parcel.find_child("ParcelInteract", false, false) as Interactable
	pit.action.call()
	await secs(1.5)
	check(await wait_done("EV02c_parcel", 6), "save: checkpoint 'parcel_obtained'")
	var desk_t: Transform3D = lvl._desk_place_transform()
	p.global_position = desk_t.origin + Vector3(0.1, -0.76, 0.75)
	await frames(3)
	p.try_interact()
	await secs(1.5)
	pit.action.call()
	await secs(4.0)
	check(lvl.parcel_open, "EV03: parcel opened on the desk")
	# ---------------- EVENT 03 편지
	var memo: Node = lvl.parcel.find_child("prop_memo", true, false)
	var mit := memo.find_child("Interact", true, false) as Interactable
	check(mit.inspect_title == "손으로 쓴 편지", "EV03: letter object titled for the event")
	p.inspect.open(mit)
	await secs(0.6)
	check(await wait_done("EV03_letter", 5), "EV03: '잡음을 제거하지 말라고...?' after reading the letter")
	p.inspect.close(true)
	await frames(3)
	var t2it := lvl.parcel.find_child("prop_tape_2", true, false).find_child("Interact", true, false) as Interactable
	check(t2it.pickup_item == &"", "tapes: TAPE 02 cannot be taken before TAPE 01 (order)")
	var t1it := lvl.parcel.find_child("prop_tape_1", true, false).find_child("Interact", true, false) as Interactable
	p.inspect.open(t1it)
	await secs(0.4)
	p.inspect.close(true)
	check(Inventory.has(&"tape_1"), "tapes: TAPE 01 taken from the box")
	# ---------------- EVENT 04
	var rit := lvl.recorder.find_child("RecorderInteract", false, false) as Interactable
	p.global_position = lvl.recorder.global_position + Vector3(0.1, -0.8, 0.6)
	await frames(3)
	rit.action.call()
	await secs(3.0)
	check(lvl.recorder_state == "loaded" and lvl.recorder_tape_no == "1", "recorder: TAPE 01 inserted (object animation)")
	if not lvl.door_open:
		lvl.toggle_door()
	await secs(1.0)
	var was_open: bool = lvl.door_open
	lvl.recorder_key()
	await secs(9.0 + DialogueDB.duration_of("PRO_E04_T01") + 0.6)
	check(was_open and not lvl.door_open and lvl.door_locked, "EV04: door slams shut right after Soeun's line and locks")
	check(await wait_done("EV04_first_recording", 8), "save: checkpoint 'tape1_played'")
	# ---------------- EVENT 05
	lvl.toggle_door()
	check(await wait_done("EV05_locked_door", 5), "EV05: '왜 안 열려...?' at the locked door")
	await secs(4.0)
	check(not lvl.clock_running and not lvl.story_fx.rain_on and lvl.story_fx.monitor_noise, "EV05: clock stops, rain stops, monitor noise")
	check(not d.started.has("EV05b_voice_behind"), "EV05: voice behind waits for the player to stop the recorder")
	await stand(lvl.recorder.global_position + Vector3(0.3, -0.8, 0.6), lvl.recorder.global_position)
	lvl.recorder_key()
	await secs(1.0)
	check(d.started.has("EV05b_voice_behind") and lvl.story_fx._behind == Vector3.ZERO, "EV05: no voice right at the stop (≈3 s later)")
	check(await wait_done("EV05b_voice_behind", 8), "EV05: clean '정우야...?' from behind")
	var behind: Vector3 = lvl.story_fx._behind
	check((behind - p.camera.global_position).dot(-p.camera.global_transform.basis.z) < 0.0 and lvl.in_studio(behind), "EV05: voice source behind the player, inside the room")
	p.look_at_point(behind)
	check(await wait_done("EV05c_nobody", 6), "EV05: nobody there — '누구야?'")
	# ---------------- EVENT 06
	check(await wait_done("EV06_blackout", 10), "EV06: flicker ×3 → blackout")
	await secs(2.5)
	check(lvl.lighting == "blackout" and not lvl.fx["StudioCeiling"].is_emitting() and lvl.env.ambient_light_energy == 0.0, "EV06: real blackout (lights, ambient)")
	lvl.fx["StudioCeiling"].press_switch()
	lvl.fx["StudioCeiling"].press_switch()
	check(not lvl.fx["StudioCeiling"].is_emitting(), "EV06: switch does nothing")
	Inventory.add(&"flashlight")
	check(await wait_done("EV06b_flashlight", 6), "save: checkpoint 'flashlight_obtained'")
	p.flashlight.set_on(true)
	await frames(3)
	check(p.flashlight.is_on and p.flashlight.spot.visible, "EV06: F toggles the flashlight")
	# ---------------- EVENT 07
	await stand(lvl.door_inside_point() + Vector3(0, -1.0, 0), lvl.door_inside_point())
	check(await wait_done("EV07_door_voice", 10), "EV07: whisper outside, knock, unlock")
	check(not lvl.door_locked and lvl.soeun_node != null, "EV07: door unlocked; Soeun placed in corridor")
	lvl.toggle_door()
	await secs(1.2)
	# ---------------- EVENT 08 소은 (복도 끝, 등 돌림)
	var s_head: Vector3 = lvl.story_fx.point("soeun_corridor")
	await stand(B(1.0, -1.1), s_head)
	check(lvl.soeun_node.visible, "EV08: Soeun visible at the corridor end (back turned)")
	check(lvl.soeun_node.global_transform.basis.z.x > 0.5, "EV08: she faces away from the player (east)")
	check(await wait_done("EV08_soeun_corridor", 10), "EV08: light flickers and she is gone")
	check(not lvl.soeun_node.visible, "EV08: Soeun hidden (during the dark frame)")
	# ---------------- EVENT 09 소음 실루엣
	await secs(1.0)
	var st := lvl.story_fx.st() as StoryStaging
	check(st.noise != null and st.noise.visible and st.monster_state == "peeking", "EV09: noise silhouette peeks from the pillar")
	var head := st._noise_head()
	check(st.g2b(head).y < -0.72, "EV09: head/shoulder out past the pillar, body behind it", "head y=%.2f" % st.g2b(head).y)
	var body_b := st.g2b(st.noise.global_position)
	check(body_b.x < -1.58 and body_b.y > -0.75 and body_b.y < -0.2, "EV09: body stays behind the pillar (no wall clipping)", "%s" % body_b)
	await stand(B(0.6, -1.2), head)
	check(await wait_done("EV09_monster_corner", 8), "EV09: player sees it")
	await stand(B(-0.9, -1.2), head)
	await secs(1.5)
	check(st.monster_state == "hiding" or st.monster_state == "gone", "EV09: it hides when approached")
	p.look_at_point(B(10.0, -1.1, 1.5))
	check(await wait_done("EV09b_follower", 12), "EV09: hidden → footsteps start following")
	# ---------------- EVENT 10
	var d0 := st.follow_dist
	await walk_x(1.0, 6.2)
	check(st.follow_dist < d0, "EV09: footsteps get closer while walking", "%.1f → %.1f" % [d0, st.follow_dist])
	check(d.is_done("EV10_lights_chase") and not lvl.fx["CorLight0"].is_emitting() and not lvl.fx["CorLight1"].is_emitting(), "EV10: lights behind go off in order")
	check(lvl.fx["CorLight5"].is_emitting(), "EV10: the light ahead is still on")
	await walk_x(6.2, 11.4)
	check(await wait_done("EV10b_transition", 30), "EV10: last light, flashlight cut, '찾았다.', black, 1998")
	check(lvl.in_apartment and lvl.apt.bounds().has_point(p.global_position), "EV10: player is in the 1998 apartment corridor")
	check(not st.follower_on, "EV10: all footsteps stopped")
	check(SaveGame.read().checkpoint == "apt_entered", "save: checkpoint 'apt_entered'")
	check(not p.flashlight.blocked, "EV10: control returned (flashlight usable again)")
	# ---------------- TAPE 01
	var apt: AptCorridor = lvl.apt
	check(apt.model != null, "T01: apartment model loaded (apt_1998.gltf)")
	await stand(apt.point("apt_swing") + Vector3(3.0, -1.2, 0), apt.point("apt_swing"))
	check(await wait_done("T01_frag1_swing", 10), "T01: fragment 1 — empty swing moves (creak + laughter)")
	check(st.fragments >= 1, "T01: fragment 1 recorded")
	await stand(apt.point("apt_stair_base"), apt.point("apt_frag_2"))
	check(await wait_done("T01_frag2_steps", 6), "T01: fragment 2 — child footsteps upstairs")
	await stand(apt.point("apt_frag_2") + Vector3(0, 0.0, 0), apt.point("apt_steps_up"))
	check(await wait_done("T01_frag2_nobody", 6), "T01: fragment 2 — nobody upstairs")
	await stand(apt.point("apt_frag_3") + Vector3(0, -1.1, -0.6), apt.point("apt_spawn"))
	check(await wait_done("T01_frag3_recording", 20), "T01: fragment 3 — the 1998 recording (3 lines)")
	await secs(1.0)
	check(apt.soeun.visible, "T01: Soeun at the corridor end (placed out of view)")
	p.look_at_point(apt.soeun.global_position + Vector3(0, 1.0, 0))
	check(await wait_done("T01_soeun_end", 10), "T01: she appears and vanishes")
	check(not apt.soeun.visible, "T01: Soeun gone")
	check(await wait_done("T01_end", 12), "T01: auto-stop → black → studio")
	check(not lvl.in_apartment and lvl.in_studio(p.global_position), "T01: back in the studio")
	check(lvl.photo != null and lvl.photo.visible, "T01: childhood photo on the desk")
	check(lvl.tapes_done.has("1") and lvl.next_tape() == 2, "tapes: TAPE 01 finished, next is 02")
	check(SaveGame.read().checkpoint == "tape01_done", "save: checkpoint 'tape01_done'")
	p.look_at_point(lvl.photo.global_position)
	await frames(3)
	var cpos: Vector3 = p.camera.global_position
	print("DBG photo ", lvl.photo.global_position, " cam ", cpos, " dist ", cpos.distance_to(lvl.photo.global_position), " ang ",
		rad_to_deg((-p.camera.global_transform.basis.z).angle_to((lvl.photo.global_position - cpos).normalized())), " los ", lvl.story_fx.has_los(lvl.photo.global_position),
		" started ", d.started.has("T01_photo_seen"), " pt ", lvl.story_fx.point("photo"))
	check(await wait_done("T01_photo_seen", 8), "T01: '이 사진이 왜 여기 있지?'")
	var phit := lvl.photo.find_child("Interact", true, false) as Interactable
	p.inspect.open(phit)
	await secs(0.5)
	check(await wait_done("T01_photo_inspect", 6), "T01: '한소은...' on inspecting the photo")
	p.inspect.close(false)
	await frames(3)
	# 테이프 교체: TAPE 01 꺼내기 → TAPE 02 넣기
	p.global_position = lvl.recorder.global_position + Vector3(0.1, -0.8, 0.6)
	await frames(2)
	rit.action.call()
	await secs(2.0)
	check(lvl.recorder_state == "empty" and lvl.recorder_tape_no == "", "tapes: TAPE 01 ejected")
	check(lvl.parcel.find_child("prop_tape_1", true, false) != null, "tapes: TAPE 01 back in its box slot")
	var t2 := lvl.parcel.find_child("prop_tape_2", true, false).find_child("Interact", true, false) as Interactable
	check(t2.pickup_item == &"tape_2", "tapes: TAPE 02 can be taken now")
	p.inspect.open(t2)
	await secs(0.4)
	p.inspect.close(true)
	rit.action.call()
	await secs(3.0)
	check(lvl.recorder_state == "loaded" and lvl.recorder_tape_no == "2", "tapes: TAPE 02 inserted (insertable state)")
	check(await wait_done("T02_tape_inserted", 6), "save: checkpoint 'tape02_ready'")
	var sv: Dictionary = SaveGame.read().state
	check(sv.objects.get("tapes_done", []) == ["1"] and sv.objects.get("recorder_tape_no", "") == "2", "save: tape order state stored")
	check(d.started.size() == d.done.size(), "events: no event left half-run")
	var any_danger := false
	for k in d.presences:
		any_danger = any_danger or (d.presences[k] as GhostPresence).is_dangerous() or d.presences[k].can_attack
	check(d.presences.has("soeun") and d.presences.has("noise_silhouette") and not any_danger, "ghosts: presences are staging-only (no attack)")
	# ---------------- 이어하기 (저장 → 레벨 재시작 → 복원)
	var saved := SaveGame.read()
	lvl.queue_free()
	await frames(5)
	Inventory.clear()
	SaveGame.pending = saved
	GameFlow.start_mode = "continue"
	lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lvl.force_story = true
	lvl.enable_thunder = false
	add_child(lvl)
	await frames(30)
	p = lvl.player
	check(lvl.director.is_done("T02_tape_inserted") and not lvl.in_apartment, "continue: restored after TAPE 02 insert, in the studio")
	check(lvl.recorder_state == "loaded" and lvl.recorder_tape_no == "2" and lvl.tapes_done.has("1"), "continue: tape order restored (02 in recorder)")
	check(lvl.photo != null and lvl.photo.visible, "continue: photo still on the desk")
	GameFlow.start_mode = "title"
	Engine.time_scale = 1.0
	print("== %d passed, %d failed ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
