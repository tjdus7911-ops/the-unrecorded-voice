extends CanvasLayer
## 메인 타이틀. 배경은 실제 작업실 3D 공간 (레벨의 타이틀 카메라가 천천히 움직임).
## 어둡고 절제된 구성: 왼쪽 제목 · 세로 메뉴(선택 항목 왼쪽 붉은 막대) · 왼쪽 아래 버전.

signal new_game
signal continue_game

const VERSION := "VERSION 0.1.0 · PHASE 01 테스트 빌드"

var _root: Control
var _menu: VBoxContainer
var _sub: Control
var _fade: ColorRect

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIKit.control_theme()
	add_child(_root)
	# 글자가 읽히도록 왼쪽만 살짝 어둡게 (화면 장식용 그라데이션 아님)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.78))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 900
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 110
	col.offset_top = 150
	col.offset_right = 760
	col.offset_bottom = -70
	col.add_theme_constant_override("separation", 0)
	_root.add_child(col)
	for t in ["녹음되지 않은", "목소리"]:
		var l := UIKit.label(t, 78, Color(0.93, 0.91, 0.87), true)
		l.add_theme_constant_override("line_spacing", -8)
		col.add_child(l)
	var en := UIKit.label("THE UNRECORDED VOICE", 19, UIKit.DIM)
	var fv := FontVariation.new()
	fv.base_font = UIKit.font(false)
	fv.spacing_glyph = 7
	en.add_theme_font_override("font", fv)
	col.add_child(en)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 64)
	col.add_child(sp)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 6)
	col.add_child(_menu)
	var items := [["새 게임", _on_new], ["이어하기", _on_continue], ["설정", _on_settings], ["게임 종료", _on_quit]]
	for it in items:
		var b := UIKit.menu_item(it[0], 34, "bar")
		b.name = it[0]
		b.pressed.connect(it[1])
		_menu.add_child(b)
	var cont := _menu.get_node("이어하기") as Button
	cont.disabled = not SaveGame.has_save()
	if cont.disabled:
		cont.tooltip_text = "저장된 진행 내용이 없습니다"
		cont.focus_mode = Control.FOCUS_NONE
		cont.mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		var info := SaveGame.last_info()
		var note := UIKit.label("  %s · %s" % [tr(info.get("label", "")), info.get("ago", "")], 15, UIKit.DISABLED)
		_menu.add_child(note)
		_menu.move_child(note, 2)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	col.add_child(UIKit.label(VERSION, 14, UIKit.DISABLED))
	col.add_child(UIKit.label("헤드폰 사용을 권장합니다", 14, UIKit.DISABLED))
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 2.2).set_trans(Tween.TRANS_SINE)
	_focus_first.call_deferred()

func _focus_first() -> void:
	var c := _menu.get_node("이어하기") as Button
	(c if not c.disabled else _menu.get_node("새 게임") as Button).grab_focus()

func fade_out(then: Callable, t := 1.0) -> void:
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b in _menu.get_children():
		if b is Button:
			b.disabled = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, t)
	tw.tween_callback(then)

func _on_new() -> void:
	if SaveGame.has_save():
		_menu.get_parent().visible = false
		_sub = ConfirmDialogUI.ask(_root, "새 게임을 시작할까요?", "첫 자동 저장 시 기존 저장 데이터를 덮어씁니다.", "새 게임", "취소")
		_sub.answered.connect(func(yes):
			_menu.get_parent().visible = true
			if yes:
				fade_out(func(): new_game.emit())
			else:
				_focus_first())
	else:
		fade_out(func(): new_game.emit())

func _on_continue() -> void:
	fade_out(func(): continue_game.emit())

func _on_settings() -> void:
	_menu.get_parent().visible = false
	_sub = load("res://scripts/ui/settings_menu.gd").new()
	_root.add_child(_sub)
	_sub.closed.connect(func():
		_menu.get_parent().visible = true
		(_menu.get_node("설정") as Button).grab_focus.call_deferred())

func _on_quit() -> void:
	GameFlow.quit_game()
