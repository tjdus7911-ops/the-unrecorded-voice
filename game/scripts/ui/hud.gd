class_name HUD
extends CanvasLayer
## 미니멀 HUD — 작은 중앙 조준점, 바라볼 때만 상호작용 안내, 화면 하단 자막, 조사 화면 설명,
## F1 조작 안내, F3 성능 표시(FPS·드로우콜·메모리), 주요 효과음 자막(접근성).

var crosshair: Reticle
var prompt: Label
var subtitle: Label
var caption: Label
var inspect_panel: PanelContainer
var inspect_status: Label
var inspect_title: Label
var inspect_body: Label
var inspect_hint: Label
var help: Label
var perf: Label
var toast: Label
var objective: Label
var objective_text := ""
static var _inspect_tutorial_done := false
var _sub_timer := 0.0
var _sub_bg: Panel             ## 자막 배경(설정에서 켤 때만): 글자 크기에 맞춘 작은 상자
var _cap_timer := 0.0
var _toast_timer := 0.0
var _help_timer := 0.0
var _player: PlayerController
var _target: Interactable

const HELP_TEXT := "WASD 이동   Shift 달리기   Ctrl/C 앉기   마우스 시점\nE 조사·조작   F 손전등   R 녹음기 재생·정지   Q 숨 참기\nF1 조작 안내   F3 성능 표시   Esc 일시정지"

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
	# 미니멀 조준점 (요구사항 13): 평소 작은 점, 상호작용 가능할 때만 손 아이콘
	crosshair = Reticle.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(16, 16)
	add_child(crosshair)

	prompt = _label(15, Color(0.85, 0.83, 0.78, 0.75))     # 설정 '상호작용 힌트'를 켰을 때만 물건 이름
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.position += Vector2(-160, 26)
	prompt.size = Vector2(320, 26)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.visible = false
	add_child(prompt)

	# 요구사항 17 §01: 영화 자막 — 1080p 기준 24px, 배경 없음, 부드러운 그림자, 하단 중앙(아래 여백 약 7%), 최대 2줄.
	# 프로젝트가 1920×1080 기준 canvas_items 스케일이라 해상도가 바뀌면 비례해서 커지고 작아진다.
	subtitle = _label(24, Color(0.95, 0.94, 0.91))
	subtitle.anchor_left = 0.2
	subtitle.anchor_right = 0.8
	subtitle.anchor_top = 1.0
	subtitle.anchor_bottom = 1.0
	subtitle.offset_top = -78.0 - 70.0
	subtitle.offset_bottom = -78.0
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.max_lines_visible = 2
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.add_theme_constant_override("outline_size", 0)
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	subtitle.add_theme_constant_override("shadow_offset_x", 0)
	subtitle.add_theme_constant_override("shadow_offset_y", 2)
	subtitle.add_theme_constant_override("shadow_outline_size", 7)      # 번진 그림자 (글자 주변만, 띠 배경 없음)
	subtitle.add_theme_constant_override("line_spacing", 2)
	_sub_bg = Panel.new()
	_sub_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_bg.visible = false
	add_child(_sub_bg)
	move_child(_sub_bg, subtitle.get_index())        # 글자 뒤에 그린다
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(subtitle)

	caption = _label(19, Color(0.8, 0.85, 0.9, 0.9))
	caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	caption.position += Vector2(-400, -168)
	caption.size = Vector2(800, 30)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(caption)

	# 조사 설명: 화면 왼쪽 아래 어두운 띠 (물체와 겹치지 않게, 글자 크기는 접근성 설정)
	inspect_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.025, 0.82)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	inspect_panel.add_theme_stylebox_override("panel", sb)
	inspect_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	inspect_panel.offset_left = 56
	inspect_panel.offset_bottom = -56
	inspect_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	inspect_panel.custom_minimum_size = Vector2(560, 0)
	inspect_panel.visible = false
	add_child(inspect_panel)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 10)
	inspect_panel.add_child(iv)
	inspect_title = _label(30, Color(0.97, 0.95, 0.9))
	inspect_title.add_theme_font_override("font", UIKit.font(true))
	inspect_body = _label(21, Color(0.9, 0.89, 0.86))
	inspect_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_body.custom_minimum_size = Vector2(500, 0)
	inspect_status = _label(17, Color(0.75, 0.72, 0.66))
	inspect_hint = _label(16, Color(0.62, 0.61, 0.58))
	iv.add_child(inspect_title)
	iv.add_child(inspect_body)
	iv.add_child(inspect_status)
	iv.add_child(inspect_hint)

	help = _label(16, Color(0.85, 0.85, 0.82, 0.85))
	help.position = Vector2(28, 24)
	help.text = HELP_TEXT
	help.visible = false          # 조작 안내는 F1 (처음 안내는 튜토리얼 힌트로만)
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
	# 현재 목표 (요구사항 12 §4): 오른쪽 위 작은 글씨, 진행에 따라 갱신되고 완료되면 사라짐
	objective = _label(18, Color(0.88, 0.86, 0.8, 0.95))
	objective.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	objective.position += Vector2(-560, 26)
	objective.size = Vector2(530, 60)
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.modulate.a = 0.0
	add_child(objective)
	# HUD는 마우스 입력을 절대 가로채지 않는다 (조준점이 화면 중앙에 있어 캡처 모드의 마우스 이동을 소비하던 버그)
	for c in find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	DialogueDB.line_started.connect(_on_line)
	Sounds.caption.connect(_on_caption)
	Inventory.item_added.connect(_on_item)

func bind_player(p: PlayerController) -> void:
	_player = p
	p.interact_target_changed.connect(func(t): _target = t)
	p.inspect.opened.connect(_on_inspect_open)
	p.inspect.flipped.connect(func(t, back):
		if t and t.inspect_text_back != "":
			inspect_body.text = tr(t.inspect_text_back) if back else tr(t.inspect_text))
	p.inspect.closed.connect(func(_t, _p): inspect_panel.visible = false; crosshair.visible = true)

## 짧은 안내 문구. 미니멀 UI(요구사항 13): 최초 조작 튜토리얼·시스템 알림(always)만 기본 표시, 나머지는 '상호작용 힌트' 설정 시에만
func show_toast(text: String, secs := 2.5, always := false) -> void:
	if not always and not GameSettings.interaction_hints:
		return
	toast.text = tr(text)
	_toast_timer = secs

func _on_item(id: StringName) -> void:
	if not GameSettings.interaction_hints:
		return          # 획득 문구는 기본 표시하지 않는다 (요구사항 13)
	var names := {&"flashlight": "손전등을 챙겼다.", &"cassette_unlabeled": "라벨 없는 카세트테이프를 주웠다.",
			&"keys_stairwell": "열쇠 꾸러미를 주웠다.", &"note_prologue": "메모를 챙겼다."}
	if names.has(id):
		show_toast(names[id])
	elif String(id).begins_with("tape_"):
		show_toast(tr("테이프 %s번을 챙겼다.") % String(id).substr(5))

func _on_inspect_open(t: Interactable) -> void:
	var sizes := [18, 21, 25, 29]
	inspect_body.add_theme_font_size_override("font_size", sizes[clampi(GameSettings.inspect_text_size, 0, 3)])
	inspect_title.add_theme_font_size_override("font_size", sizes[clampi(GameSettings.inspect_text_size, 0, 3)] + 9)
	# 미니멀: 물건 이름·획득 문구 없이, 읽을 글(메모·라벨 뒷면 등)만. 조작 안내는 처음 한 번만.
	var can := t.pickup_item != &""
	inspect_title.text = tr(t.inspect_title)
	inspect_title.visible = GameSettings.interaction_hints
	inspect_body.text = tr(t.inspect_text)
	inspect_status.text = tr("● 가져갈 수 있다") if can else tr("○ 살펴보기만 할 수 있다")
	inspect_status.visible = GameSettings.interaction_hints
	inspect_hint.text = tr("마우스 돌려 보기 · 우클릭 뒤집기 · 휠 가까이/멀리\n") + (tr("E 가져가기 · ") if can else tr("E 내려놓기 · ")) + tr("Esc 내려놓기")
	inspect_hint.visible = not _inspect_tutorial_done or GameSettings.interaction_hints
	_inspect_tutorial_done = true
	inspect_panel.visible = inspect_title.visible or inspect_body.text.strip_edges() != "" or inspect_hint.visible
	crosshair.visible = false
	prompt.visible = false

func _style_subtitle() -> void:
	var sizes := [20, 24, 28, 34]          # 작게 / 보통(기본, 1080p 24px) / 크게 / 아주 크게
	subtitle.add_theme_font_size_override("font_size", sizes[clampi(GameSettings.subtitle_size, 0, 3)])
	subtitle.remove_theme_stylebox_override("normal")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(4)
	_sub_bg.add_theme_stylebox_override("panel", sb)

## 배경 상자를 실제 글자 영역에만 맞춘다 (화면을 가로지르는 띠 금지 — 요구사항 17 §01)
func _fit_sub_bg() -> void:
	if not GameSettings.subtitle_bg or subtitle.text == "" or not subtitle.visible:
		_sub_bg.visible = false
		return
	var font := subtitle.get_theme_font("font")
	var fs := subtitle.get_theme_font_size("font_size")
	var w := subtitle.size.x
	var sz := font.get_multiline_string_size(subtitle.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 2, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	sz.x = minf(sz.x, w)
	var lines := mini(subtitle.get_line_count(), 2)
	var h := float(lines) * (font.get_height(fs) + 2.0)
	var c := subtitle.global_position + Vector2(subtitle.size.x / 2.0, subtitle.size.y - h / 2.0)
	_sub_bg.position = c - Vector2(sz.x / 2.0 + 12.0, h / 2.0 + 4.0)
	_sub_bg.size = Vector2(sz.x + 24.0, h + 8.0)
	_sub_bg.visible = true

func _on_line(line: Dictionary) -> void:
	if not GameSettings.subtitles:
		return
	_style_subtitle()
	# 요구사항 15: 영화 자막처럼 — 이름·말풍선 없이, 음성 길이에 맞춰 (음성이 없으면 읽는 속도)
	var id: String = line.get("line_id", "")
	if id == "":
		return
	subtitle.text = DialogueDB.text_of(id)
	_sub_timer = DialogueDB.duration_of(id)

func _on_caption(text: String, dir: String) -> void:
	caption.text = "[%s%s]" % [tr(text), (" · " + tr(dir)) if dir != "" else ""]
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
		var has := t != null and is_instance_valid(t)
		crosshair.hand = has
		crosshair.dot_visible = GameSettings.crosshair_mode == 0
		# 팝업·일시정지·타이틀 중에는 상호작용 아이콘을 숨긴다 (P0 2026-11-27)
		var playing := GameFlow.state == GameFlow.State.PLAYING and ConfirmDialogUI.open_count == 0
		crosshair.visible = playing and (GameSettings.crosshair_mode != 2 or has)
		prompt.visible = playing and has and GameSettings.interaction_hints
		if prompt.visible:
			prompt.text = tr(t.current_prompt())
	if _sub_timer > 0.0:
		_sub_timer -= delta
		if _sub_timer <= 0.0:
			subtitle.text = ""
	subtitle.visible = subtitle.text != ""
	_fit_sub_bg()
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


## 현재 목표 표시 — 빈 문자열이면 사라진다
func set_objective(text: String) -> void:
	if text == objective_text:
		return
	objective_text = text
	var tw := create_tween()
	tw.tween_property(objective, "modulate:a", 0.0, 0.35)
	if text != "" and GameSettings.objective_hints:
		tw.tween_callback(func(): objective.text = tr("현재 목표") + "\n" + tr(text))
		tw.tween_property(objective, "modulate:a", 1.0, 0.6)
