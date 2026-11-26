class_name ConfirmDialogUI
extends Control
## 확인 팝업 (예 / 아니오). 어두운 띠 하나로 — 카드형 상자 대신.

signal answered(yes: bool)

var message := ""
var detail := ""
var yes_text := "예"
var no_text := "아니오"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var band := ColorRect.new()
	band.color = Color(0.045, 0.045, 0.048, 0.97)
	band.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	band.offset_top = -120
	band.offset_bottom = 120
	add_child(band)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -380
	v.offset_right = 380
	v.offset_top = -92
	v.offset_bottom = 92
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var m := UIKit.label(message, 24, UIKit.TEXT, true)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(m)
	if detail != "":
		var d := UIKit.label(detail, 17, UIKit.DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	var y := UIKit.menu_item(yes_text, 21, "box")
	var n := UIKit.menu_item(no_text, 21, "box")
	y.pressed.connect(_answer.bind(true))
	n.pressed.connect(_answer.bind(false))
	h.add_child(y)
	h.add_child(n)
	n.grab_focus.call_deferred()      # 실수 방지: 기본 선택은 '아니오'

func _answer(yes: bool) -> void:
	answered.emit(yes)
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)

static func ask(parent: Node, msg: String, det := "", yes := "예", no := "아니오") -> Control:
	var c: Control = load("res://scripts/ui/confirm_dialog.gd").new()
	c.message = msg
	c.detail = det
	c.yes_text = yes
	c.no_text = no
	parent.add_child(c)
	return c
