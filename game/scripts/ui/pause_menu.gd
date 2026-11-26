extends CanvasLayer
## 일시정지 메뉴 (ESC). 일시정지 중에는 트리 전체가 멈춘다 → 이동·이벤트 타이머·귀신 AI·추격 정지.
## 계속하기 → 마우스 다시 캡처.

signal restart_checkpoint
signal main_menu

var _root: Control
var _list: VBoxContainer
var _sub: Control

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIKit.control_theme()
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.015, 0.017, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	_list = VBoxContainer.new()
	_list.set_anchors_preset(Control.PRESET_CENTER)
	_list.offset_left = -220
	_list.offset_right = 220
	_list.offset_top = -230
	_list.offset_bottom = 230
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_list.add_theme_constant_override("separation", 4)
	_root.add_child(_list)
	var t := UIKit.label("일시정지", 34, UIKit.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(t)
	var t2 := UIKit.label("PAUSED", 14, UIKit.DIM)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(t2)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 26)
	_list.add_child(sp)
	for pair in [["계속하기", _resume], ["설정", _settings], ["마지막 체크포인트에서 다시 시작", _restart],
			["메인 메뉴로 돌아가기", _to_menu], ["게임 종료", _quit]]:
		var b := UIKit.menu_item(pair[0], 22, "box")
		b.pressed.connect(pair[1])
		b.name = pair[0]
		_list.add_child(b)
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 22)
	_list.add_child(sp2)
	var foot := UIKit.label("ESC · 게임으로 돌아가기", 15, UIKit.DISABLED)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(foot)
	GameFlow.pause_requested.connect(_open)
	GameFlow.resume_requested.connect(_close)

func _open() -> void:
	visible = true
	_list.visible = true
	(_list.get_node("계속하기") as Button).grab_focus.call_deferred()

func _close() -> void:
	if is_instance_valid(_sub):
		_sub.queue_free()
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if GameFlow.state == GameFlow.State.PLAYING:
		get_viewport().set_input_as_handled()
		GameFlow.pause()
	elif GameFlow.state == GameFlow.State.PAUSED and visible and not is_instance_valid(_sub):
		get_viewport().set_input_as_handled()
		GameFlow.resume()

func _resume() -> void:
	GameFlow.resume()

func _settings() -> void:
	_list.visible = false
	_sub = load("res://scripts/ui/settings_menu.gd").new()
	_root.add_child(_sub)
	_sub.closed.connect(func():
		_list.visible = true
		(_list.get_node("설정") as Button).grab_focus.call_deferred())

func _unsaved_note() -> String:
	var info: Dictionary = SaveGame.last_info()
	if info.is_empty():
		return "저장된 진행 내용이 없습니다. 지금까지의 진행은 사라집니다."
	return "마지막 자동 저장: '%s' (%s). 그 이후의 진행은 저장되지 않습니다." % [info.get("label", ""), info.get("ago", "")]

func _confirm(msg: String, then: Callable) -> void:
	_list.visible = false
	_sub = ConfirmDialogUI.ask(_root, msg, _unsaved_note())
	_sub.answered.connect(func(yes):
		_list.visible = true
		if yes:
			then.call()
		else:
			(_list.get_child(3) as Button).grab_focus.call_deferred())

func _restart() -> void:
	_confirm("마지막 체크포인트에서 다시 시작할까요?", func():
		visible = false
		restart_checkpoint.emit())

func _to_menu() -> void:
	_confirm("메인 메뉴로 돌아갈까요?", func():
		visible = false
		main_menu.emit())

func _quit() -> void:
	_confirm("게임을 종료할까요?", GameFlow.quit_game)
