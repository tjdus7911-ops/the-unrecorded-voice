class_name HUD
extends CanvasLayer
## 미니멀 HUD — 작은 중앙 조준점, 바라볼 때만 상호작용 안내, 화면 하단 자막, 조사 화면 설명,
## F1 조작 안내, F3 성능 표시(FPS·드로우콜·메모리), 주요 효과음 자막(접근성).

var crosshair: ColorRect
var prompt: Label
var subtitle: Label
var caption: Label
var inspect_panel: VBoxContainer
var inspect_title: Label
var inspect_body: Label
var inspect_hint: Label
var help: Label
var perf: Label
var toast: Label
var _sub_timer := 0.0
var _cap_timer := 0.0
var _toast_timer := 0.0
var _help_timer := 9.0
var _player: PlayerController
var _target: Interactable

const HELP_TEXT := "WASD 이동   Shift 달리기   Ctrl/C 앉기   마우스 시점\nE 조사·조작   F 손전등   Q 숨 참기(은신 중)\nF1 조작 안내   F3 성능 표시   Esc 마우스 해제"

func _label(size: int, color := Color(0.92, 0.9, 0.86, 0.92)) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

func _ready() -> void:
	layer = 10
	crosshair = ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.5)
	crosshair.size = Vector2(3, 3)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(1.5, 1.5)
	add_child(crosshair)

	prompt = _label(17)
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.position += Vector2(-160, 26)
	prompt.size = Vector2(320, 26)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.visible = false
	add_child(prompt)

	subtitle = _label(26, Color(0.96, 0.95, 0.92))
	subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle.position += Vector2(-560, -120)
	subtitle.size = Vector2(1120, 64)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(subtitle)

	caption = _label(19, Color(0.8, 0.85, 0.9, 0.9))
	caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	caption.position += Vector2(-400, -168)
	caption.size = Vector2(800, 30)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(caption)

	inspect_panel = VBoxContainer.new()
	inspect_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	inspect_panel.position += Vector2(-470, -140)
	inspect_panel.custom_minimum_size = Vector2(420, 0)
	inspect_panel.visible = false
	add_child(inspect_panel)
	inspect_title = _label(24, Color(0.97, 0.95, 0.9))
	inspect_body = _label(19, Color(0.86, 0.85, 0.82))
	inspect_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_body.custom_minimum_size = Vector2(420, 0)
	inspect_hint = _label(15, Color(0.7, 0.7, 0.68, 0.9))
	inspect_panel.add_child(inspect_title)
	inspect_panel.add_child(inspect_body)
	inspect_panel.add_child(inspect_hint)

	help = _label(16, Color(0.85, 0.85, 0.82, 0.85))
	help.position = Vector2(28, 24)
	help.text = HELP_TEXT
	add_child(help)

	perf = _label(15, Color(0.75, 0.95, 0.75))
	perf.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	perf.position += Vector2(-330, 20)
	perf.size = Vector2(310, 200)
	perf.visible = false
	add_child(perf)

	toast = _label(18, Color(0.9, 0.88, 0.82))
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position += Vector2(-300, 70)
	toast.size = Vector2(600, 30)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast)

	DialogueDB.line_started.connect(_on_line)
	Sounds.caption.connect(_on_caption)
	Inventory.item_added.connect(_on_item)

func bind_player(p: PlayerController) -> void:
	_player = p
	p.interact_target_changed.connect(func(t): _target = t)
	p.inspect.opened.connect(_on_inspect_open)
	p.inspect.closed.connect(func(_t, _p): inspect_panel.visible = false; crosshair.visible = true)

func show_toast(text: String, secs := 2.5) -> void:
	toast.text = text
	_toast_timer = secs

func _on_item(id: StringName) -> void:
	var names := {&"flashlight": "손전등을 챙겼다.", &"cassette_unlabeled": "라벨 없는 카세트테이프를 주웠다.",
			&"keys_stairwell": "열쇠 꾸러미를 주웠다.", &"note_prologue": "메모를 챙겼다."}
	if names.has(id):
		show_toast(names[id])
	elif String(id).begins_with("tape_"):
		show_toast("테이프 %s번을 챙겼다." % String(id).substr(5))

func _on_inspect_open(t: Interactable) -> void:
	inspect_title.text = t.inspect_title
	inspect_body.text = t.inspect_text
	inspect_hint.text = "마우스: 돌려 보기     E: " + ("가져가기" if t.pickup_item != &"" else "닫기") + "     Esc: 내려놓기"
	inspect_panel.visible = true
	crosshair.visible = false
	prompt.visible = false

func _on_line(line: Dictionary) -> void:
	if not GameSettings.subtitles:
		return
	var id: String = line["line_id"]
	var who := DialogueDB.speaker_name(id)
	subtitle.text = (who + ": " if who != "" else "") + DialogueDB.text_of(id)
	_sub_timer = 0.08 * subtitle.text.length() + 1.8

func _on_caption(text: String, dir: String) -> void:
	caption.text = "[%s%s]" % [text, (" · " + dir) if dir != "" else ""]
	_cap_timer = 2.5

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		help.visible = not help.visible
		_help_timer = 0.0
	elif event.is_action_pressed("perf_overlay"):
		perf.visible = not perf.visible

func _process(delta: float) -> void:
	if _player and not _player.inspect.is_open():
		var t := _target
		prompt.visible = t != null and is_instance_valid(t)
		if prompt.visible:
			prompt.text = "[E] " + t.current_prompt()
	if _sub_timer > 0.0:
		_sub_timer -= delta
		if _sub_timer <= 0.0:
			subtitle.text = ""
	if _cap_timer > 0.0:
		_cap_timer -= delta
		if _cap_timer <= 0.0:
			caption.text = ""
	if _toast_timer > 0.0:
		_toast_timer -= delta
		toast.modulate.a = clampf(_toast_timer, 0.0, 1.0)
	if _help_timer > 0.0:
		_help_timer -= delta
		if _help_timer <= 0.0:
			help.visible = false
	if perf.visible:
		perf.text = PerfStats.summary()
