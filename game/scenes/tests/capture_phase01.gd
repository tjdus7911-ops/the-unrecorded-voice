extends Node
## 실제 게임 화면 캡처 (검토용). 레벨을 그대로 띄우고 플레이어를 각 위치에 세워 찍는다.
##   godot --path game --rendering-driver vulkan --resolution 1600x900 res://scenes/tests/capture_phase01.tscn -- <out_dir> [shot,...]

var out_dir := "user://captures"
var only: PackedStringArray = []
var lvl: Node3D
var p: PlayerController

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		only = args[1].split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func shot(name: String, settle := 30) -> void:
	await frames(mini(settle, 28))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	var s := PerfStats.snapshot()
	print("captured %s  draw_calls=%d prims=%d vram=%.0fMB" % [name, s.draw_calls, s.primitives, s.video_mem_mb])

func want(n: String) -> bool:
	return only.is_empty() or only.has(n)

func stand(bpos: Vector3, look_b: Vector3, crouch := false) -> void:
	p.global_position = Vector3(bpos.x, 0.0 if bpos.z < 0.5 else bpos.z, -bpos.y)
	if crouch:
		p.is_crouching = true
		p._height = p.crouch_height
		p._apply_height()
	await frames(2)
	p.look_at_point(Vector3(look_b.x, look_b.z, -look_b.y))

func _run() -> void:
	Inventory.clear()
	lvl = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lvl.enable_thunder = false
	add_child(lvl)
	await frames(10)
	p = lvl.player
	lvl.hud.help.visible = false
	p.input_enabled = false
	await frames(30)          # SDFGI 수렴
	if want("01_studio_overview"):
		await stand(Vector3(0.75, 0.6, 0), Vector3(3.6, 4.4, 0.9))
		await shot("01_studio_overview", 90)
	if want("02_fps_desk"):
		await stand(Vector3(2.85, 3.15, 0), Vector3(2.75, 4.6, 0.85))
		await shot("02_fps_desk", 60)
	if want("03_studio_ceiling_on"):
		lvl.fx["StudioCeiling"].press_switch()
		await stand(Vector3(3.2, 0.7, 0), Vector3(2.0, 4.4, 0.9))
		await shot("03_studio_ceiling_on", 90)
		lvl.fx["StudioCeiling"].press_switch()
	if want("04_lights_off") or want("05_flashlight_on"):
		lvl.fx["DeskLamp"].press_switch()
		lvl.fx["FloorLamp"].press_switch()
		await stand(Vector3(1.6, 1.4, 0), Vector3(3.2, 4.6, 0.3))
		if want("04_lights_off"):
			await shot("04_lights_off", 90)
		Inventory.add(&"flashlight")
		p.flashlight.set_on(true)
		if want("05_flashlight_on"):
			await shot("05_flashlight_on", 40)
		p.input_enabled = true
		Input.action_press("crouch")
		await stand(Vector3(2.7, 3.45, 0), Vector3(2.7, 4.35, 0.0))
		await frames(40)
		p.look_at_point(Vector3(2.7, 0.0, -4.35))
		await shot("06_dark_clue_under_desk", 20)
		Input.action_release("crouch")
		p.input_enabled = false
		await frames(40)
		p.flashlight.set_on(false)
		lvl.fx["DeskLamp"].press_switch()
		lvl.fx["FloorLamp"].press_switch()
	if want("07_corridor"):
		lvl.toggle_door()
		await frames(70)
		await stand(Vector3(0.95, -0.35, 0), Vector3(9.0, -1.2, 1.1))
		await shot("07_corridor", 90)
		await stand(Vector3(11.0, -0.8, 0), Vector3(-4.0, -1.2, 1.0))
		await shot("08_corridor_west", 90)
		await stand(Vector3(2.2, -1.6, 0), Vector3(0.95, 0.1, 0.9))
		await shot("09_door_304_parcel", 60)
	if want("10_stairwell_dark"):
		await stand(Vector3(13.73, -0.8, 0), Vector3(13.73, 2.9, -1.5))
		Inventory.add(&"flashlight")
		p.flashlight.set_on(true)
		await shot("10_stairwell_dark_flashlight", 60)
		p.flashlight.set_on(false)
	if want("11_inspect"):
		await stand(Vector3(2.3, 0.85, 0), Vector3(2.17, 0.24, 0.85))
		p.try_interact()
		await shot("11_inspect_flashlight", 30)
		p.inspect.close(false)
		lvl._parcel_open()
		await frames(200)
		await stand(Vector3(1.0, -0.3, 0), Vector3(1.0, -0.75, 0.1))
		await shot("12_parcel_open", 60)
		var memo: Node3D = lvl.parcel.find_child("prop_memo", true, false)
		var it := memo.get_node("Interact") as Interactable
		p.inspect.open(it)
		await shot("13_inspect_memo", 30)
		p.inspect.close(false)
		var tape: Node3D = lvl.parcel.find_child("prop_tape_1", true, false)
		p.inspect.open(tape.get_node("Interact"))
		await shot("14_inspect_tape", 30)
		p.inspect.close(true)
		await frames(5)
		await stand(Vector3(2.55, 3.75, 0), Vector3(2.45, 4.23, 0.75))
		p.try_interact()
		await frames(130)
		p.try_interact()
		await frames(40)
		await shot("15_recorder_playing", 30)
	print("PERF ", JSON.stringify(PerfStats.snapshot()))
	get_tree().quit()
