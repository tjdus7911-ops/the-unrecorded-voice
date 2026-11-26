extends Node
## 작업실 이동·충돌 테스트 (헤드리스):
##   godot --headless --fixed-fps 60 --path game res://scenes/tests/run_studio_tests.tscn

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

## Blender 좌표로 배치 → 방향(yaw)으로 n 프레임 걷기 → 최종 Blender 좌표 반환
func walk(from_b: Vector3, yaw_deg: float, n: int, run := false) -> Vector3:
	p.global_position = Vector3(from_b.x, 0.05, -from_b.y)
	p.velocity = Vector3.ZERO
	p.set("_yaw", deg_to_rad(yaw_deg))
	await frames(5)
	Input.action_press("move_forward")
	if run:
		Input.action_press("sprint")
	await frames(n)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await frames(10)
	var g := p.global_position
	return Vector3(g.x, -g.z, g.y)

func _run() -> void:
	print("== Studio movement & collision tests ==")
	lvl = load("res://scenes/levels/stu_studio.tscn").instantiate()
	add_child(lvl)
	await frames(30)
	p = lvl.player
	var r := p.radius

	check(p.is_on_floor(), "spawn: on studio floor")
	var b := Vector3(p.global_position.x, -p.global_position.z, p.global_position.y)
	check(absf(b.z) < 0.05, "spawn: floor height ~0", "z=%.3f" % b.z)

	# yaw: 0 = 북(+Y Blender), 90 = 서(-X), -90 = 동(+X), 180 = 남(-Y)
	var e := await walk(Vector3(1.0, 1.0, 0), 0.0, 300)
	check(e.y < 5.0 - r + 0.02 and e.y > 4.5, "north wall stops player (x=1.0)", "y=%.2f" % e.y)

	e = await walk(Vector3(2.2, 2.6, 0), 0.0, 300)
	check(e.y < 4.055 - r + 0.03 and e.y > 3.4, "desk blocks player", "y=%.2f (desk front 4.055)" % e.y)

	e = await walk(Vector3(3.0, 1.0, 0), 90.0, 400, true)
	check(e.x > r - 0.02 and e.x < 0.6, "west wall stops player (y=1.0)", "x=%.2f" % e.x)

	e = await walk(Vector3(3.0, 3.0, 0), 90.0, 400)
	check(e.x > 0.32 + r - 0.03, "cassette shelf blocks player", "x=%.2f (shelf face 0.32)" % e.x)

	e = await walk(Vector3(3.5, 2.0, 0), -90.0, 400)
	check(e.x < 4.17 + 0.05 and e.x > 3.6, "coffee table blocks player", "x=%.2f (table edge 4.175)" % e.x)

	e = await walk(Vector3(2.35, 1.2, 0), 180.0, 300)
	check(e.y > 0.42 + r - 0.03, "south cabinet blocks player", "y=%.2f" % e.y)

	e = await walk(Vector3(0.95, 1.2, 0), 180.0, 300)
	check(e.y > 0.0 and e.y < 0.5, "closed door blocks exit", "y=%.2f" % e.y)

	e = await walk(Vector3(1.0, 2.5, 0), -30.0, 240)
	check(p.is_on_floor(), "open floor walkable, stays grounded")

	# 1인칭 시점 높이
	check(absf(p.head.global_position.y - p.global_position.y - 1.62) < 0.02, "eye height 1.62 m (same as CAM_fps)")

	# 천장 패널 = 스토리 소등 상태, 손전등 F
	check(not lvl.ceiling_panels[0].any_light_visible(), "ceiling panels STORY_OFF in SCENE 02")
	Inventory.add(&"flashlight")
	p.flashlight.toggle()
	check(p.flashlight.is_on, "flashlight usable in studio")

	print("== %d passed, %d failed ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
