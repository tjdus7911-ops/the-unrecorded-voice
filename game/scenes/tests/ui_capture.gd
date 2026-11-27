extends Node
## 팝업 실제 화면 캡처: 타이틀 '새 게임' 확인 팝업 · 일시정지 메뉴의 재시작/메인 메뉴/종료 팝업.
## usage: godot --path game --rendering-driver vulkan --resolution WxH res://scenes/tests/ui_capture.tscn -- --out DIR [--tag NAME]
var out := "/tmp/uitest"
var tag := "x"

func _ready() -> void:
	GameFlow.auto_pause_on_focus_loss = false
	var a := OS.get_cmdline_user_args()
	if a.has("--out"):
		out = a[a.find("--out") + 1]
	if a.has("--tag"):
		tag = a[a.find("--tag") + 1]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func t(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, tag, n])
	print("SHOT ", n, " viewport=", get_viewport().get_visible_rect().size, " window=", DisplayServer.window_get_size())

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveGame.write("game_start", {"done": []})
	GameFlow.start_mode = "title"
	var lvl: Node = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lvl.enable_thunder = false
	get_tree().root.add_child(lvl)
	get_tree().current_scene = lvl
	await t(2.0)
	if lvl.get("title_ui") == null:
		lvl._enter_title()
		await t(1.5)
	var title = lvl.get("title_ui")
	if title:
		title._on_new()
		await t(0.6)
		await shot("title_newgame_popup")
		var popup: Control = title._sub
		_report(popup)
		await _click_button(popup, "아니오")
		print("TITLE popup closed by real click: ", not is_instance_valid(popup) or popup.is_queued_for_deletion())
		await t(0.3)
		title._on_settings()
		await t(0.6)
		await shot("title_settings")
		title._sub.queue_free()
		await t(0.3)
	# 게임 중 일시정지 메뉴의 팝업들
	lvl.queue_free()
	await t(0.5)
	GameFlow.start_mode = "new"
	var lv2: Node = load("res://scenes/levels/lvl_phase01.tscn").instantiate()
	lv2.enable_thunder = false
	lv2.force_story = true
	get_tree().root.add_child(lv2)
	await t(2.0)
	GameFlow.set_state(GameFlow.State.PLAYING)
	await t(0.3)
	var dbg := lv2.find_children("*", "StoryDebugOverlay", true, false)
	if not dbg.is_empty():
		dbg[0].visible = true
		await t(1.0)
		await shot("debug_overlay")
		print("DEBUG OVERLAY:\n", dbg[0].text())
		dbg[0].visible = false
	GameFlow.pause()
	await t(0.5)
	await shot("pause_menu")
	var pm = lv2.get("pause_menu")
	for spec in [["_restart", "pause_restart_popup"], ["_to_menu", "pause_menu_popup"], ["_quit", "pause_quit_popup"]]:
		pm.call(spec[0])
		await t(0.5)
		await shot(spec[1])
		_report(pm._sub)
		await _click_button(pm._sub, "아니오")
		await t(0.3)
		print("PAUSE ", spec[1], " closed; state=", GameFlow.state, " paused=", get_tree().paused)
	pm._settings()
	await t(0.6)
	await shot("pause_settings")
	print("UI CAPTURE DONE")
	get_tree().quit()

func _report(c: Control) -> void:
	if c == null:
		print("POPUP null")
		return
	print("POPUP rect=", c.get_global_rect())
	for b in c.find_children("*", "Button", true, false):
		print("  BUTTON ", (b as Button).text, " rect=", (b as Button).get_global_rect())

## 실제 마우스 클릭 이벤트를 버튼이 그려진 화면 위치에 보낸다 (클릭 영역 = 표시 위치 확인)
func _click_button(root: Control, text: String) -> void:
	if root == null:
		return
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			var c := (b as Button).get_global_rect().get_center()
			var vp := get_viewport()
			var xf := vp.get_final_transform()
			var screen := xf * c
			for pressed in [true, false]:
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = pressed
				e.position = screen
				e.global_position = screen
				Input.parse_input_event(e)
				await get_tree().process_frame
				await get_tree().process_frame
			print("  CLICK ", text, " at ", screen)
			return
