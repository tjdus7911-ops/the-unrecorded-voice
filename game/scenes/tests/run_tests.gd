extends Node
## 자동 시스템 테스트 — 헤드리스로 실행:
##   godot --headless --fixed-fps 60 --path game res://scenes/tests/run_tests.tscn
## 실패 시 종료 코드 1.

var bed: Node3D
var p: PlayerController
var passed := 0
var failed := 0

func _ready() -> void:
	_run.call_deferred()

func check(cond: bool, name: String, detail := "") -> void:
	if cond:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name, "  ", detail)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func hold(action: String, n: int) -> void:
	Input.action_press(action)
	await frames(n)
	Input.action_release(action)

func _run() -> void:
	print("== The Unrecorded Voice — system tests ==")
	Inventory.clear()
	bed = load("res://scenes/tests/dev_testbed.tscn").instantiate()
	add_child(bed)
	await frames(40)
	p = bed.player

	# --- 데이터 ---
	check(DialogueDB.lines.size() == 7, "dialogue: prologue lines loaded", str(DialogueDB.lines.size()))
	check(DialogueDB.text_of("PRO_S05_003") == "정우야?", "dialogue: text lookup")
	check(DialogueDB.get_line("PRO_S05_003")["playback"]["position"] == "behind_player", "dialogue: '정우야?' is spatial behind player")
	check(DialogueDB.speaker_name("PRO_S03_001") == "정우", "dialogue: speaker name")
	check(AudioServer.get_bus_index(&"Breathing") >= 0 and AudioServer.get_bus_index(&"Heartbeat") >= 0 and AudioServer.get_bus_index(&"VoiceTape") >= 0, "audio: bus layout")

	# --- 이동·충돌 ---
	check(p.is_on_floor(), "player: on floor after spawn")
	check(absf(p.head.global_position.y - 1.62 - p.global_position.y) < 0.02, "player: eye height 1.62 m")
	var x0 := p.global_position.x
	await hold("move_forward", 60)
	var walked := p.global_position.x - x0
	check(walked > 1.2 and walked < 2.0, "player: walk ~1.7 m/s", "%.2f m in 1s" % walked)

	p.set("_yaw", PI / 2.0)   # -X 벽 방향
	await hold("move_forward", 300)
	check(p.global_position.x > -2.5 + 0.2, "collision: stopped by wall", "x=%.2f" % p.global_position.x)
	check(p.is_on_floor(), "collision: still on floor")

	# --- 크라우치 ---
	Input.action_press("crouch")
	await frames(40)
	check(p.head.position.y < 1.1, "crouch: eye lowered", "%.2f" % p.head.position.y)
	Input.action_release("crouch")
	await frames(40)
	check(p.head.position.y > 1.6, "crouch: stand back up")

	# --- 손전등 획득 전 ---
	check(not p.flashlight.toggle(), "flashlight: cannot toggle before pickup")
	# 테이블 앞으로 이동 후 바라보고 E
	p.global_position = Vector3(-1.6, 0.05, -0.4)
	await frames(5)
	p.look_at_point(bed.flashlight_pickup.global_position)
	await frames(2)
	check(p.try_interact(), "interact: flashlight pickup in reach")
	await frames(2)
	check(Inventory.has_flashlight, "inventory: flashlight acquired")
	p.flashlight.toggle()
	check(p.flashlight.is_on and p.flashlight.spot.visible, "flashlight: F toggles on")
	check(p.flashlight.spot.shadow_enabled, "flashlight: realtime shadows (no light through walls)")
	p.flashlight.toggle()
	check(not p.flashlight.spot.visible, "flashlight: F toggles off")
	var ev := InputEventAction.new()
	ev.action = "flashlight"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	check(p.flashlight.is_on, "flashlight: input action 'flashlight' (F) works")

	# --- 조명 상태 ---
	check(bed.fixture_a.is_emitting(), "lights: room A normal")
	check(not bed.fixture_b.is_emitting() and not bed.fixture_b.any_light_visible(), "lights: room B dead (Light3D actually hidden)")
	check(bed.fixture_a.any_light_visible(), "lights: room A Light3D visible")
	var changes := 0
	var last: bool = bed.fixture_corridor.is_emitting()
	for i in 240:
		await get_tree().process_frame
		if bed.fixture_corridor.is_emitting() != last:
			changes += 1
			last = not last
	check(changes >= 2, "lights: corridor flickers", "%d changes" % changes)
	# 방 B 스위치 — 눌러도 안 켜짐
	p.global_position = Vector3(7.3, 0.05, 0.3)
	await frames(5)
	p.look_at_point(bed.switch_b.global_position)
	check(p.try_interact(), "interact: room B switch")
	check(not bed.fixture_b.any_light_visible(), "lights: dead light stays off after switch")
	bed.fixture_b.set_state(LightFixture.State.NEEDS_POWER)
	bed.fixture_b.restore_power()
	check(bed.fixture_b.is_emitting() == bed.fixture_b.switched_on, "lights: restore_power API")
	bed.fixture_b.set_state(LightFixture.State.DEAD)

	# --- 어둠 속 단서 ---
	p.global_position = Vector3(9.0, 0.05, 0.4)
	await frames(5)
	p.look_at_point(bed.clue_cassette.global_position)
	await frames(2)
	check(p.try_interact(), "clue: cassette found in dark room")
	await frames(2)
	check(Inventory.has(&"cassette_test"), "clue: cassette in inventory")

	# --- 호흡 ---
	p.danger = 0.0
	await frames(90)
	check(p.breathing.state == &"calm", "breathing: calm when idle", p.breathing.state)
	check(p.breathing.current_stream() != null, "breathing: placeholder stream playing")
	p.set("_yaw", 0.0)
	p.global_position = Vector3(8.5, 0.05, 1.5)
	Input.action_press("move_forward")
	await frames(30)
	check(p.breathing.state == &"walk", "breathing: walk", p.breathing.state)
	Input.action_press("sprint")
	await frames(30)
	check(p.breathing.state == &"run", "breathing: run", p.breathing.state)
	p.global_position = Vector3(8.5, 0.05, 1.5)
	p.stamina = 0.2
	await frames(30)
	check(p.breathing.state == &"exhausted", "breathing: exhausted after stamina drained", p.breathing.state)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	p.stamina = p.stamina_max
	p.is_exhausted = false

	# --- 심장 박동 ---
	var b0: int = p.heartbeat.beats_played
	await frames(120)
	check(p.heartbeat.beats_played - b0 <= 1, "heartbeat: nearly silent when safe")
	p.danger = 1.0
	await frames(300)
	check(p.breathing.state == &"fear", "breathing: fear under danger", p.breathing.state)
	check(p.heartbeat.current_bpm() > 120.0, "heartbeat: fast under chase", "%.0f bpm" % p.heartbeat.current_bpm())
	check(p.heartbeat.current_db() <= p.heartbeat.db_max + 0.01, "heartbeat: volume capped below footsteps/voice")
	var b1: int = p.heartbeat.beats_played
	await frames(120)
	check(p.heartbeat.beats_played - b1 >= 3, "heartbeat: beating", str(p.heartbeat.beats_played - b1))
	p.danger = 0.0
	await frames(600)
	check(p.heartbeat.level < 0.3, "heartbeat: recovers after danger clears", "%.2f" % p.heartbeat.level)

	print("== %d passed, %d failed ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
