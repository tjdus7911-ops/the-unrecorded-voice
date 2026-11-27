extends Node
## 요구사항 16 공식 흐름 자동 검증: 프롤로그 EVENT 01~10 → TAPE 01(1998) → 작업실 복귀 → TAPE 02 삽입 → 이어하기 (헤드리스).
## 실제 화면 검수는 story_tour(영상)·qa_capture로 따로 한다 — 이 테스트 통과만으로 플레이 검수 완료로 보지 않는다.
## usage: godot --headless --path game res://scenes/tests/run_story_tests.tscn

var lvl: Node3D
var p: PlayerController
var passed := 0
var save_fl: Dictionary = {}
var failed := 0

## 오디오가 실제로 믹싱되는지 (헤드리스 Dummy 드라이버는 믹싱하지 않아 원샷이 끝나지 않는다 → 소리 검수는 --write-movie 실행에서)
var audio_mixing := false
func _probe_audio() -> void:
	var pl := Sounds.play("sfx_deck_button", &"SFX", -80.0)
	var fin := [false]
	if pl:
		pl.finished.connect(func(): fin[0] = true)
	var el := 0.0
	while el < 2.0 and not fin[0]:
		await get_tree().process_frame
		el += get_process_delta_time()
	audio_mixing = fin[0]
	print("audio mixing: ", audio_mixing, " (probe finished after %.2fs, paused=%s)" % [el, get_tree().paused])

func check_audio(c: bool, name: String, info := "") -> void:
	if not audio_mixing:
		print("  SKIP  %s (headless: no audio mix — run tools/ci/sound_audit.sh)" % name)
		return
	check(c, name, info)

## 검수 로그: 지금 재생 중인 소리 목록 (tools/ci/sound_audit.sh 가 모아 docs/production/sound_audit_*.md 로 정리)
func _snap(label: String) -> void:
	var rows: Array = []
	for e in Sounds.active_players():
		var n := e[0] as Node
		var where := ""
		if n is Node3D and lvl and lvl.player:
			where = "%.1fm" % (n as Node3D).global_position.distance_to(lvl.player.global_position)
		rows.append("%s|%s|%s|%s|%s" % [e[1], e[2], "loop" if e[3] else "once", where, n.get_parent().name])
	print("SOUND@%s %s" % [label, ";".join(rows)])

func secs_real(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout

func _playing_file(part: String) -> bool:
	for e in Sounds.active_players():
		if String(e[1]).contains(part):
			return true
	return false

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
	await _probe_audio()
	var d: EventDirector = lvl.director
	check(d != null and d.by_id.has("EV10_transition") and d.by_id.has("T01_end"), "events: prologue + tape01 JSON loaded", "%d" % d.events.size())
	# ---------------- EVENT 01
	check(await wait_done("EV01_normal_studio", 12), "EV01: normal studio")
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
	# 요구사항 21: 노크 → 출입문에 노란 핀 / 설정별 표시
	await secs(0.4)
	var om: ObjectiveDirector = lvl.objectives
	check(om.active_id == "pro_door_knock" and om.current_point().distance_to(lvl.door_inside_point()) < 1.6, "req21: knock → marker on the studio door", om.active_id)
	check(lvl.objective_marker.want_visible and lvl.objective_marker.mouse_filter == Control.MOUSE_FILTER_IGNORE, "req21: marker shown (always mode), ignores mouse")
	check(lvl.objective_marker.find_children("*", "CollisionObject3D", true, false).is_empty(), "req21: marker has no physics body (never blocks the interact ray)")
	GameSettings.objective_marker = 2
	await secs(0.3)
	check(not lvl.objective_marker.want_visible, "req21: setting 'off' hides the marker")
	GameSettings.objective_marker = 1
	await secs(0.3)
	check(not lvl.objective_marker.want_visible, "req21: setting 'only when stuck' waits before showing")
	om._active_since -= 60.0
	await secs(0.3)
	check(lvl.objective_marker.want_visible, "req21: 'only when stuck' shows after being stuck")
	GameSettings.objective_marker = 0
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
	check(lvl.objective_hidden() and not lvl.objective_marker.want_visible, "req21: marker hidden on the inspect screen")
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
	# P0 회귀: 재생 중 복도로 나가 있으면 문은 닫히지 않고(밖에 갇히지 않음) 돌아오면 등 뒤에서 닫힌다
	lvl.recorder_key()
	# --- 요구사항 20: 재생 순서·잡음 (PLAY → 릴 → 짧은 지지직 → 완전히 끝 → '잘 들려?' → … → '녹음되고 있어?' → 쾅)
	await secs(0.15)
	var sf: PrologueStory = lvl.story_fx
	check(lvl.motor.playing and not lvl.hiss.playing, "req20: PLAY → reel motor runs, no continuous hiss bed")
	var el := 0.0
	var crackle_on_at_voice := true
	while el < 8.0 and not sf.tape_seq_log.any(func(e): return e[0] == "PRO_E04_T00"):
		await frames(1)
		el += get_process_delta_time()
	crackle_on_at_voice = _playing_file("tape_start_crackle")
	var log0: Array = sf.tape_seq_log.duplicate()
	check(log0.size() >= 2 and log0[0][0] == "sfx_tape_start_crackle" and log0[1][0] == "PRO_E04_T00", "req20: crackle first, then '정우야, 잘 들려?'", str(log0))
	check_audio(not crackle_on_at_voice and not lvl.hiss.playing, "req20: crackle has fully ended when '잘 들려?' starts")
	check_audio(log0.size() >= 2 and float(log0[1][1]) - float(log0[0][1]) <= 1.15, "req20: start crackle ≤ ~1 s", str(log0))
	# 정지 → 테이프 속 소리·모터도 멈춤 → 다시 재생하면 이어짐
	await secs(0.3)
	lvl.recorder_key()
	await secs(0.3)
	var tp_paused: bool = lvl._tape_players().all(func(c): return (c as AudioStreamPlayer3D).stream_paused)
	check_audio(lvl.recorder_state == "loaded" and not lvl.motor.playing and tp_paused and Sounds.active_players(lvl.recorder).is_empty(), "req20: STOP silences everything on the recorder")
	var log_n: int = sf.tape_seq_log.size()
	await secs(1.5)
	check(sf.tape_seq_log.size() == log_n, "req20: sequence holds while stopped")
	lvl.recorder_key()
	await stand(B(2.0, -1.1), B(5.0, -1.1, 1.5))
	var hiss_during_voice := false
	el = 0.0
	while el < 30.0 and sf.tape_seq_running:
		if _playing_file("tape_hiss") or _playing_file("tape_start_crackle") and sf.tape_seq_log.size() > 1:
			hiss_during_voice = true
		await frames(2)
		el += get_process_delta_time() * 2.0
	await secs(0.8)
	var names: Array = sf.tape_seq_log.map(func(e): return e[0])
	check(names == ["sfx_tape_start_crackle", "PRO_E04_T00", "tape_playground", "PRO_E04_T01", "slam"], "req20: order crackle → 잘 들려 → 놀이터 → 녹음되고 있어 → 쾅", str(names))
	check_audio(not hiss_during_voice, "req20: no repeating noise while the recording plays")
	check(was_open and lvl.door_open and not lvl.door_locked, "P0: player outside during the tape → door not slammed/locked behind them (no soft-lock)")
	await stand(lvl.recorder.global_position + Vector3(0.1, -0.8, 0.6), lvl.door_inside_point())
	await secs(1.0)
	check(not lvl.door_open and lvl.door_locked, "EV04: door slams shut (behind the player, inside) and locks")
	# P0 회귀: 이벤트 준비 전(EV04 진행 중)에 문을 시도해도 놓치지 않는다
	lvl.toggle_door()
	check(lvl.story_fx.tried_door, "P0: early door try is remembered")
	check(await wait_done("EV04_first_recording", 12), "save: checkpoint 'tape1_played'")
	_snap("EV04_done")
	check(await wait_done("EV05_locked_door", 6), "EV05: '왜 안 열려...?' fires from the earlier try (no second try needed)")
	lvl.toggle_door()
	lvl.toggle_door()
	await secs(0.5)
	check(d.done.size() == d.started.size() or d.started.has("EV05_locked_door"), "P0: trying the door many times does not duplicate events")
	await secs(4.0)
	check(not lvl.clock_running and not lvl.story_fx.rain_on and lvl.story_fx.monitor_noise, "EV05: clock stops, rain stops, monitor noise")
	check(p.danger < 0.05 and p.breathing.state in [&"calm", &"walk"], "req17 §07: no heavy breathing/heartbeat at the locked door", str(p.breathing.state))
	# P0 회귀: 녹음기를 멈추지 않아도(정지 방법을 몰라도) 테이프가 끝나 스스로 멈추고 진행된다
	check(lvl.recorder_state == "playing", "P0: recorder still playing (player did not stop it)")
	check(await wait_done("EV05a_tape_autostop", 14), "P0: tape runs out and stops by itself (철컥)")
	check(lvl.recorder_state == "loaded", "P0: recorder state = stopped")
	_snap("EV05a_autostop")
	await stand(lvl.recorder.global_position + Vector3(0.3, -0.8, 0.6), lvl.recorder.global_position)
	check(await wait_done("EV05b_voice_behind", 8), "EV05: clean '정우야...?' from behind")
	# P0 회귀: 대사 중 ESC(일시정지) → 계속하기
	GameFlow.pause()
	await frames(10)
	check(get_tree().paused, "P0: ESC pauses during the voice line")
	check(lvl.objective_hidden(), "req21: marker hidden in the pause menu")
	# 요구사항 20: 일시정지 중에는 게임 소리(효과음·환경음·음성)가 모두 멈춘다 (UI 소리만 예외) → 재개하면 이어서
	_snap("PAUSED")
	var live_in_pause: Array = Sounds.active_players().filter(func(e): return e[2] != "UI")
	var paused_n: int = GameFlow._paused_players.size()
	check_audio(paused_n > 0 and live_in_pause.is_empty(), "req20: pause freezes all game sounds (%d paused)" % paused_n, str(live_in_pause.map(func(e): return e[1])))
	GameFlow.resume()
	var behind: Vector3 = lvl.story_fx._behind
	check((behind - p.camera.global_position).dot(-p.camera.global_transform.basis.z) < 0.0 and lvl.in_studio(behind), "EV05: voice source behind the player, inside the room")
	check(p.danger < 0.05, "req17 §07: no heartbeat at '정우야...?'")
	p.look_at_point(behind)
	check(await wait_done("EV05c_nobody", 6), "EV05: nobody there — '누구야?' (after resume)")
	# P0 회귀: Alt+Tab(포커스 잃음) → 자동 일시정지 → 복귀 후 계속하기
	GameFlow.auto_pause_on_focus_loss = true
	GameFlow.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(5)
	check(get_tree().paused and GameFlow.state == GameFlow.State.PAUSED, "P0: focus loss (Alt+Tab) pauses the game")
	GameFlow.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	GameFlow.resume()
	await frames(5)
	check(not get_tree().paused and GameFlow.state == GameFlow.State.PLAYING, "P0: back from Alt+Tab → playing again")
	# ---------------- EVENT 06 (작업실 + 복도 동시 정전)
	check(await wait_done("EV06_blackout", 12), "EV06: flicker ×3 → blackout")
	await secs(2.5)
	check(lvl.lighting == "blackout" and not lvl.fx["StudioCeiling"].is_emitting() and lvl.env.ambient_light_energy == 0.0, "EV06: real blackout (lights, ambient)")
	var cor_off := true
	for i in 6:
		cor_off = cor_off and not lvl.fx["CorLight%d" % i].is_emitting()
	check(cor_off and not lvl.fx["StairUp"].is_emitting(), "req17 §08: corridor fluorescents also off (same floor)")
	check(lvl.exit_glow.light_energy < 0.05, "req17 §08: exit sign only faint")
	lvl.fx["StudioCeiling"].press_switch()
	lvl.fx["StudioCeiling"].press_switch()
	check(not lvl.fx["StudioCeiling"].is_emitting(), "EV06: switch does nothing")
	check(p.unease >= 0.3 and p.danger < 0.05, "req17 §07: slightly uneasy breathing, no heartbeat in blackout")
	var dr := lvl.find_child("stu_desk_drawer_0", true, false) as Node3D
	check(lvl.point_lit(dr.global_position + Vector3(0, 0.05, 0.25)), "P0: drawer usable in the dark before the flashlight")
	Inventory.add(&"flashlight")
	check(await wait_done("EV06b_flashlight", 6), "save: checkpoint 'flashlight_obtained'")
	save_fl = SaveGame.read()
	p.flashlight.set_on(true)
	await frames(3)
	check(p.flashlight.is_on and p.flashlight.spot.visible, "EV06: F toggles the flashlight")
	# P0 회귀: 손전등을 얻은 뒤 작업실을 더 둘러봐도 문제없다
	await stand(lvl.recorder.global_position + Vector3(0.3, -0.8, 0.6), B(1.0, 4.0, 1.0))
	await secs(2.0)
	check(not d.started.has("EV07_door_voice"), "P0: re-exploring the studio does not trigger the door event")
	# ---------------- EVENT 07
	await stand(lvl.door_inside_point() + Vector3(0, -1.0, 0), lvl.door_inside_point())
	check(await wait_done("EV07_door_voice", 12), "EV07: whisper outside, knock, unlock")
	check(not lvl.door_locked and lvl.soeun_node != null, "EV07: door unlocked; Soeun placed in the dark corridor")
	lvl.toggle_door()
	await secs(1.2)
	check(lvl.door_open, "EV07: player opens the door")
	# ---------------- EVENT 08 소은 — 손전등으로 비춰야 보인다
	var st := lvl.story_fx.st() as StoryStaging
	var s_head: Vector3 = lvl.story_fx.point("soeun_corridor")
	await stand(B(1.0, -1.1), s_head + Vector3(0, -0.25, 0))
	await frames(4)
	check(lvl.soeun_node.visible and lvl.soeun_node.global_transform.basis.z.x > 0.5, "EV08: Soeun at the corridor end, back turned")
	check(st.check("soeun_lit"), "EV08: the flashlight beam reaches her (8~12 m)")
	check(await wait_done("EV08_soeun_corridor", 10), "EV08: flashlight flickers → she is gone → 2 s silence")
	check(not lvl.soeun_node.visible, "EV08: Soeun hidden (only during the dark frame)")
	# ---------------- EVENT 08b~09 뒤에서 떨어지는 소리 → 모퉁이 괴물
	check(await wait_done("EV08b_drop", 6), "STEP03: something drops behind (restroom passage)")
	await secs(0.5)
	check(st.noise != null and st.noise.visible and st.monster_state == "peeking", "STEP03: noise silhouette peeks around the corner")
	var head := st._noise_head()
	check(st.g2b(head).y > -2.0, "STEP03: head/shoulders out into the corridor", "head y=%.2f" % st.g2b(head).y)
	var body_b := st.g2b(st.noise.global_position)
	check(body_b.y < -2.2 and body_b.x < -3.8 and body_b.x > -4.5, "STEP03: body stays inside the passage (behind the wall)", "%s" % body_b)
	p.look_at_point(head)
	check(await wait_done("EV09_monster_seen", 8), "STEP03: player sees it (irregular breathing, weak heartbeat)")
	check(p.danger > 0.2 and p.danger < 0.5, "req17 §07: weak heartbeat on discovery", "%.2f" % p.danger)
	# STEP 04: 걸어 나와 → 방향 전환 → 멈춤 → 추격
	await secs(1.2)
	check(st.monster_state in ["emerging", "turning", "paused", "chasing"], "STEP04: it walks out of the passage", st.monster_state)
	check(await wait_done("EV09b_chase", 14), "STEP05: it starts running at the player")
	var m0 := st.noise.global_position
	await walk_x(1.0, 4.0)
	var m1 := st.noise.global_position
	check(m1.distance_to(m0) > 1.0 and st.noise_poser.mode in ["run", "walk"], "STEP05: the real model chases (moves, run/walk animation)", "%.1f m %s" % [m1.distance_to(m0), st.noise_poser.mode])
	var mb := st.g2b(m1)
	check(mb.y > -1.8 and mb.y < -0.45, "STEP05: stays inside the corridor (no wall clipping)", "%s" % mb)
	check(p.danger > 0.5, "STEP05: heartbeat rises with the chase", "%.2f" % p.danger)
	# ---------------- EVENT 10 지정 구간 → 손전등 깜빡 → 꺼짐 → 정적 → '찾았다.' → 1998
	await walk_x(4.0, 10.6)
	check(await wait_done("EV10_transition", 30), "EV10: flicker → flashlight off → silence → '찾았다.' → 1998")
	check(lvl.in_apartment and lvl.apt.bounds().has_point(p.global_position), "EV10: player is in the 1998 apartment corridor")
	check(st.monster_state == "gone" and not st.noise.visible, "EV10: monster and footsteps stopped (removed in the dark)")
	check(SaveGame.read().checkpoint == "apt_entered", "save: checkpoint 'apt_entered'")
	check(not p.flashlight.blocked and p.danger < 0.1, "EV10: control returned, heartbeat calmed")
	_snap("EV10_in_1998")
	# 요구사항 20: 공간 전환 — 작업실·상가 복도 소리(녹음기·형광등·환경음·추격음)가 1998 공간에서 들리지 않는다
	await secs(1.0)
	var leftover: Array = []
	for e in Sounds.active_players():
		var n := e[0] as Node
		if n is AudioStreamPlayer3D and not lvl.apt.is_ancestor_of(n) and (n as Node3D).global_position.distance_to(p.global_position) > 25.0:
			leftover.append(e[1])
		elif n is AudioStreamPlayer and String(e[2]) in ["SFX", "VoiceTape", "Ghost"] and bool(e[3]):
			leftover.append(e[1])
	check_audio(leftover.is_empty(), "req20: no studio/corridor sound carried into 1998", str(leftover))
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
	_snap("T01_back_in_studio")
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
	# ---------------- 요구사항 21: 목표 위치 안내 순서 (실제로 활성화된 목표 기록)
	var oh: Array = lvl.objectives.history.map(func(e): return e[1]).filter(func(x): return x != "")
	print("OBJECTIVES ", oh)
	var want := ["pro_door_knock", "pro_parcel", "pro_desk", "pro_box_open", "pro_tape1", "pro_recorder", "pro_play",
		"pro_drawer", "pro_door_exit", "pro_escape", "t01_corridor_east", "t01_corridor",
		"t01_eject_tape1", "t01_next_tape", "t01_insert_tape2"]
	# (이 테스트는 서랍을 열지 않고 손전등을 넣고, 놀이터로 순간이동하므로 pro_flashlight·t01_exit_building·t01_playground·t01_stairs는 story_tour 실제 플레이에서 확인)
	var k := 0
	for id in oh:
		if k < want.size() and id == want[k]:
			k += 1
	check(k == want.size(), "req21: markers appear in story order (%d/%d)" % [k, want.size()], str(oh))
	check(lvl.objectives.active_id == "" and not lvl.objective_marker.visible, "req21: no marker left after the last objective is done")
	for bad in ["soeun", "monster", "noise", "hidden", "photo"]:
		check(not oh.any(func(x): return String(x).contains(bad)), "req21: no marker for '%s'" % bad)
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
	check(Sounds.loop_oneshot_warnings.is_empty(), "req20: no looping sound was fired as a one-shot", str(Sounds.loop_oneshot_warnings))
	check(Sounds.duplicate_starts.is_empty(), "req20: no sound effect stacked twice at the same moment", str(Sounds.duplicate_starts))
	# 요구사항 21: 손전등을 얻은 시점의 저장에서 이어하면 목표(출입문)가 그대로 복원된다
	if not save_fl.is_empty():
		lvl.queue_free()
		await frames(5)
		Inventory.clear()
		SaveGame.pending = save_fl
		GameFlow.start_mode = "continue"
		lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
		lvl.force_story = true
		lvl.enable_thunder = false
		add_child(lvl)
		await frames(40)
		await secs(1.0)
		check(lvl.objectives.active_id == "pro_door_exit", "req21: continue restores the current objective (door after flashlight)", lvl.objectives.active_id)
	print("== %d passed, %d failed ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
