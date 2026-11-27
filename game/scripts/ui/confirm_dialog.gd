class_name ConfirmDialogUI
extends Control
## 확인 팝업 (예 / 아니오) — 모든 확인 팝업 공통 (새 게임·다시 시작·메인 메뉴·게임 종료).
## 화면 정중앙의 작은 카드: 제목 · 질문 · (보충 설명) · [예] [아니오]. 간결한 공포게임 스타일 (2026-11-27 P0 디자인 예시).
##
## P0 버그 원인(2026-11-27): 예전 코드는 _ready()에서 set_anchors_preset(FULL_RECT)만 호출했다. Godot 4에서 이 함수는
## 이미 트리에 들어온 컨트롤의 '현재 사각형'을 유지하도록 오프셋을 다시 계산하므로, 크기 0인 상태가 그대로 남아
## 팝업이 (0,0) 좌상단에 0×0 크기로 놓이고 내용이 화면 밖으로 잘렸다(버튼 일부가 음수 좌표 → 클릭 불가).
## → set_anchors_and_offsets_preset 으로 앵커와 오프셋을 함께 지정하고, 내용은 CenterContainer로 정중앙에 둔다.
## 창 크기를 바꿔도 앵커 기준으로 다시 배치되어 중앙을 유지한다.

signal answered(yes: bool)

var title := ""
var message := ""
var detail := ""
var yes_text := "예"
var no_text := "아니오"
var _done := false
static var open_count := 0          ## 열린 팝업 수 (중복 방지·디버그 표시용)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP          # 뒤의 메뉴·게임이 클릭을 받지 않게
	open_count += 1
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.135, 0.135, 0.14, 0.98)
	sb.border_color = Color(0.26, 0.26, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(440, 0)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	if title != "":
		var t := UIKit.label(title, 24, UIKit.TEXT, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
	var m := UIKit.label(message, 18, Color(0.82, 0.81, 0.78))
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.custom_minimum_size = Vector2(380, 0)
	v.add_child(m)
	if detail != "":
		var d := UIKit.label(detail, 14, UIKit.DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(380, 0)
		v.add_child(d)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var y := _button(yes_text, true)
	var n := _button(no_text, false)
	y.pressed.connect(_answer.bind(true))
	n.pressed.connect(_answer.bind(false))
	h.add_child(y)
	h.add_child(n)
	y.focus_neighbor_right = y.get_path_to(n)
	n.focus_neighbor_left = n.get_path_to(y)
	n.grab_focus.call_deferred()      # 실수 방지: 기본 선택은 '아니오'

func _button(text: String, filled: bool) -> Button:
	var b := Button.new()
	b.text = tr(text)
	b.custom_minimum_size = Vector2(170, 50)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.add_theme_font_override("font", UIKit.font(false))
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.9, 0.89, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(6)
		s.set_border_width_all(1)
		var lift := 0.06 if st in ["hover", "focus"] else (0.02 if st == "pressed" else 0.0)
		if filled:
			s.bg_color = Color(0.26 + lift, 0.26 + lift, 0.27 + lift)
			s.border_color = Color(0.32 + lift, 0.32 + lift, 0.34 + lift)
		else:
			s.bg_color = Color(0.13 + lift * 0.6, 0.13 + lift * 0.6, 0.14 + lift * 0.6, 1.0)
			s.border_color = Color(0.45 + lift, 0.45 + lift, 0.47 + lift)
		if st == "focus":
			s.border_color = Color(0.75, 0.74, 0.7)
			s.draw_center = false
		b.add_theme_stylebox_override(st, s)
	return b

func _answer(yes: bool) -> void:
	if _done:
		return
	_done = true
	answered.emit(yes)
	queue_free()

func _exit_tree() -> void:
	open_count = maxi(open_count - 1, 0)

func _input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)

## msg = 질문, det = 보충 설명. title은 선택 (비우면 질문만)
static func ask(parent: Node, msg: String, det := "", yes := "예", no := "아니오", title_text := "") -> Control:
	var c: Control = load("res://scripts/ui/confirm_dialog.gd").new()
	c.title = title_text
	c.message = msg
	c.detail = det
	c.yes_text = yes
	c.no_text = no
	parent.add_child(c)
	return c
