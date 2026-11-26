extends Node
## 렌더링 확인용 스크린샷 캡처 (가상 디스플레이에서 실행):
##   xvfb-run godot --path game --fixed-fps 60 res://scenes/tests/capture_screens.tscn -- <out_dir>

var out_dir := "user://captures"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("captured ", name)

func _run() -> void:
	Inventory.clear()
	Inventory.add(&"flashlight")
	var bed: Node3D = load("res://scenes/tests/dev_testbed.tscn").instantiate()
	add_child(bed)
	var p: PlayerController = bed.player
	await _frames(30)
	await _shot("01_room_a_lit")
	# 어두운 방 B — 손전등 끔
	p.global_position = Vector3(7.6, 0.05, -0.6)
	p.look_at_point(Vector3(10.4, 0.4, 1.4))
	await _frames(20)
	await _shot("02_room_b_dark_flashlight_off")
	p.flashlight.set_on(true)
	await _frames(40)
	await _shot("03_room_b_flashlight_on")
	p.look_at_point(bed.clue_cassette.global_position)
	await _frames(40)
	await _shot("04_flashlight_on_clue")
	get_tree().quit()
