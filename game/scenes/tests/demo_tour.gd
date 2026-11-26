extends Node
## 실제 플레이 영상 녹화용 시연 경로 (Godot Movie Maker):
##   godot --path game --write-movie out.avi --fixed-fps 24 --resolution 960x540 res://scenes/tests/demo_tour.tscn
## 실제 플레이어 컨트롤러·상호작용·사운드를 그대로 사용한다 (입력만 스크립트가 대신 누름).

var lvl: Node3D
var p: PlayerController

func _ready() -> void:
	_run.call_deferred()

func t(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout

func look(b: Vector3, dur: float) -> void:
	var d := Vector3(b.x, b.z, -b.y) - p.head.global_position
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var cur: float = p.get("_yaw")
	yaw = cur + wrapf(yaw - cur, -PI, PI)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "_yaw", yaw, dur)
	tw.tween_property(p, "_pitch", pitch, dur)
	await t(dur)

func walk_to(b: Vector3, max_t := 8.0, run := false) -> void:
	var goal := Vector3(b.x, 0, -b.y)
	Input.action_press("move_forward")
	if run:
		Input.action_press("sprint")
	var el := 0.0
	while el < max_t:
		var d := goal - Vector3(p.global_position.x, 0, p.global_position.z)
		if d.length() < 0.25:
			break
		var want := atan2(-d.x, -d.z)
		var cur: float = p.get("_yaw")
		p.set("_yaw", cur + wrapf(want - cur, -PI, PI) * 0.12)
		await get_tree().physics_frame
		el += get_physics_process_delta_time()
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await t(0.3)

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

func _run() -> void:
	Inventory.clear()
	lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	add_child(lvl)
	await t(0.2)
	p = lvl.player
	lvl.hud.help.visible = false
	lvl._thunder_t = 9.0
	p.global_position = Vector3(2.9, 0.05, -3.1)
	p.set("_yaw", 0.0)
	p.set("_pitch", deg_to_rad(8))
	await t(1.5)
	# 1) 비 내리는 창 → 책상
	await look(Vector3(3.6, 5.0, 1.7), 2.2)
	await look(Vector3(2.6, 4.5, 0.85), 2.0)
	# 2) 수납장 위 손전등으로 (나무 바닥 발소리)
	await walk_to(Vector3(2.3, 0.95, 0))
	await look(Vector3(2.17, 0.24, 0.85), 1.0)
	await press("interact")
	await t(0.6)
	var it := p.inspect
	var tw := create_tween()
	tw.tween_method(func(v): it._rot.y = v; it._apply_rot(), it._rot.y, it._rot.y + 2.4, 2.2)
	await t(2.6)
	await press("interact")       # 가져가기
	await t(0.8)
	# 3) 문 옆 스위치로 천장등 켰다 끄기
	await look(Vector3(1.62, 0.0, 1.25), 1.0)
	await walk_to(Vector3(1.7, 0.75, 0), 3.0)
	await look(Vector3(1.62, 0.0, 1.25), 0.6)
	await press("interact")
	await t(0.4)
	await look(Vector3(3.0, 3.5, 1.0), 1.4)
	await t(1.0)
	await look(Vector3(1.62, 0.0, 1.25), 1.0)
	await press("interact")
	# 4) 스탠드·플로어 스탠드도 꺼진다 → 암흑, 손전등
	await look(Vector3(3.0, 4.0, 0.8), 1.2)
	lvl.fx["DeskLamp"].press_switch()
	await t(0.35)
	lvl.fx["FloorLamp"].press_switch()
	p.danger = 0.45
	await t(1.4)
	await press("flashlight")
	await t(0.6)
	await look(Vector3(0.3, 3.5, 1.0), 1.6)
	await look(Vector3(3.5, 4.6, 0.6), 1.8)
	# 5) 책상 아래 — 앉아서 비춰 보기
	await walk_to(Vector3(2.7, 3.55, 0), 4.0)
	Input.action_press("crouch")
	await look(Vector3(2.7, 4.35, 0.0), 1.6)
	await t(0.8)
	await press("interact")
	await t(2.2)
	await press("interact")
	Input.action_release("crouch")
	await t(0.6)
	p.danger = 0.0
	lvl.fx["DeskLamp"].press_switch()
	await t(0.3)
	# 6) 문 열고 복도로
	await walk_to(Vector3(0.95, 1.1, 0), 5.0)
	await look(Vector3(1.2, 0.0, 1.0), 0.8)
	await press("interact")
	await t(1.6)
	await walk_to(Vector3(0.95, 0.35, 0), 3.0)
	await look(Vector3(8.0, -1.2, 1.2), 1.6)
	await look(Vector3(1.0, -0.75, 0.0), 1.2)
	# 7) 택배 상자 열기 → 메모
	await press("interact")
	await t(3.4)
	var memo: Node3D = lvl.parcel.find_child("prop_memo", true, false)
	if memo:
		var mp := memo.global_position
		await look(Vector3(mp.x, -mp.z, mp.y), 0.8)
		await press("interact")
		await t(3.0)
		await press("interact")
		await t(0.6)
	# 8) 복도를 따라 계단실 → 불 꺼진 계단참
	await walk_to(Vector3(1.8, -1.1, 0), 3.0)
	await walk_to(Vector3(12.6, -1.1, 0), 12.0)
	await look(Vector3(13.73, 2.6, -1.4), 1.2)
	await walk_to(Vector3(13.73, 1.9, 0), 6.0)
	await look(Vector3(13.6, 2.85, -1.7), 1.0)
	await t(2.0)
	get_tree().quit()
