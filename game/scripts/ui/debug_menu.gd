extends CanvasLayer
## 개발용 디버그 메뉴 (F8) — 디버그 빌드에서만 생성된다 (릴리스 내보내기에서는 비활성).
## 이벤트 강제 실행 · 조명 상태 · 호흡/심장 · 음성 · 환경음 · 체크포인트 이동 · 이벤트 로그

var lvl: Node3D
var _panel: PanelContainer
var _log: Label

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		queue_free()
		return
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.85)
	sb.content_margin_left = 12
	sb.content_margin_top = 10
	sb.content_margin_right = 12
	sb.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(16, 16)
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	v.add_child(_lbl("DEBUG (F8)  — 개발 빌드 전용"))
	var d: EventDirector = lvl.director
	if d:
		var row := HFlowContainer.new()
		row.custom_minimum_size = Vector2(760, 0)
		for e in d.events:
			var id: String = e["id"]
			row.add_child(_btn(id.substr(0, 14), func(): d.force(id)))
		v.add_child(_lbl("이벤트 강제 실행"))
		v.add_child(row)
	var l := HFlowContainer.new()
	for st in ["normal", "flicker", "flicker_once", "story_off", "dead"]:
		l.add_child(_btn("천장 " + st, func(): lvl.set_light("StudioCeiling", st)))
	l.add_child(_btn("모든 실내등 끔", func():
		for k in ["StudioCeiling", "DeskLamp", "FloorLamp"]:
			lvl.set_light(k, "story_off")))
	l.add_child(_btn("전력 복구", func():
		for k in ["StudioCeiling", "DeskLamp", "FloorLamp"]:
			lvl.set_light(k, "restore")))
	v.add_child(_lbl("조명"))
	v.add_child(l)
	var b := HFlowContainer.new()
	for st in ["calm", "uneasy", "fear", "exhausted"]:
		b.add_child(_btn("호흡 " + st, func(): lvl.player.breathing.force_state(StringName(st))))
	b.add_child(_btn("숨 들이킴", func(): lvl.player.breathing.play_oneshot(&"gasp")))
	for h in [0.0, 0.5, 1.0]:
		b.add_child(_btn("심장 %.1f" % h, func(): lvl.player.danger = h))
	v.add_child(_lbl("호흡 · 심장"))
	v.add_child(b)
	var a := HFlowContainer.new()
	for line in ["PRO_E01_001", "PRO_E03_TAPE_1", "PRO_E05_001", "PRO_E07_001", "PRO_E08_001"]:
		a.add_child(_btn(line, func(): lvl.play_line_world(line, lvl.player.camera.global_position + Vector3(0, 0, 2), false)))
	a.add_child(_btn("비 끔", func(): lvl.set_rain(false, 1.0)))
	a.add_child(_btn("비 켬", func(): lvl.set_rain(true, 1.0)))
	a.add_child(_btn("노크", lvl.knock))
	a.add_child(_btn("귀신 등장(미구현: 프롤로그는 연출만)", func(): lvl.hud.show_toast("귀신 AI는 P3 단계 — 아직 없음")))
	v.add_child(_lbl("음성 · 환경음"))
	v.add_child(a)
	var c := HFlowContainer.new()
	c.add_child(_btn("마지막 체크포인트 불러오기", func():
		if SaveGame.has_save():
			SaveGame.pending = SaveGame.read()
			GameFlow.restart_level("continue")))
	c.add_child(_btn("1998 복도로 이동", lvl.enter_apartment))
	v.add_child(_lbl("체크포인트 · 챕터"))
	v.add_child(c)
	v.add_child(_lbl("이벤트 로그"))
	_log = _lbl("")
	_log.custom_minimum_size = Vector2(760, 180)
	_log.add_theme_font_size_override("font_size", 12)
	v.add_child(_log)

func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 14)
	return l

func _btn(t: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(f)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_panel.visible = not _panel.visible
		if _panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			GameFlow.set_state(GameFlow.state)
		get_viewport().set_input_as_handled()

func _process(_d: float) -> void:
	if _panel and _panel.visible and lvl.director:
		_log.text = "\n".join(lvl.director.log.slice(maxi(0, lvl.director.log.size() - 12)))
