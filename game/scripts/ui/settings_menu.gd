extends Control
## 설정 화면 (타이틀·일시정지 공용). 값은 바꾸는 즉시 적용·저장 (GameSettings → user://settings.cfg).

signal closed

const TABS := ["화면", "조작", "사운드", "접근성"]

var _tab_buttons: Array[Button] = []
var _content: VBoxContainer
var _waiting_action := ""
var _waiting_btn: Button
var _current := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # P0: set_anchors_preset만 쓰면 트리 안에서 크기 0으로 남는다
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIKit.control_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.022, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 120
	root.offset_top = 96
	root.offset_right = -120
	root.offset_bottom = -80
	root.add_theme_constant_override("separation", 64)
	add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	left.add_child(UIKit.label("설정", 40, UIKit.TEXT, true))
	left.add_child(UIKit.label("SETTINGS", 14, UIKit.DIM))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 28)
	left.add_child(sp)
	for i in TABS.size():
		var b := UIKit.menu_item(TABS[i], 24, "bar")
		b.pressed.connect(_show_tab.bind(i))
		b.focus_entered.connect(_show_tab.bind(i))
		left.add_child(b)
		_tab_buttons.append(b)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp2)
	var back := UIKit.menu_item("돌아가기", 22, "bar")
	back.pressed.connect(close)
	left.add_child(back)
	left.add_child(UIKit.label("ESC · 돌아가기", 14, UIKit.DISABLED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	scroll.add_child(_content)
	_show_tab(0)
	_tab_buttons[0].grab_focus.call_deferred()

func close() -> void:
	GameSettings.save_settings()
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if _waiting_action != "" and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode != KEY_ESCAPE:
			GameSettings.rebind(_waiting_action, event.physical_keycode)
		_waiting_action = ""
		_show_tab(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _show_tab(i: int) -> void:
	_current = i
	for c in _content.get_children():
		c.queue_free()
	_content.add_child(UIKit.label(TABS[i], 30, UIKit.TEXT, true))
	match i:
		0: _display_tab()
		1: _controls_tab()
		2: _sound_tab()
		3: _access_tab()

## ---------------------------------------------------------------- 행 생성
func _row(title: String, ctl: Control, note := "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	var l := UIKit.label(title, 20, UIKit.TEXT)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	ctl.custom_minimum_size = Vector2(360, 34)
	h.add_child(ctl)
	if note != "":
		h.add_child(UIKit.label(note, 15, UIKit.DIM))
	_content.add_child(h)

func _option(key: String, items: Array, value: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(value)
	o.item_selected.connect(func(idx): GameSettings.set_value(StringName(key), idx))
	return o

func _check(key: String) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = GameSettings.get(key)
	c.text = "켬" if c.button_pressed else "끔"
	c.toggled.connect(func(on):
		c.text = "켬" if on else "끔"
		GameSettings.set_value(StringName(key), on))
	return c

func _slider(getter: Callable, setter: Callable, lo: float, hi: float, step: float, fmt := "%d%%", mul := 100.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = getter.call()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := UIKit.label(fmt % (s.value * mul), 17, UIKit.DIM)
	v.custom_minimum_size = Vector2(64, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x):
		v.text = fmt % (x * mul)
		setter.call(x))
	h.add_child(s)
	h.add_child(v)
	return h

func _vol(bus: String) -> HBoxContainer:
	return _slider(func(): return GameSettings.volumes[StringName(bus)],
		func(x): GameSettings.set_value(StringName(bus), x), 0.0, 1.0, 0.05)

func _section(t: String) -> void:
	var l := UIKit.label(t, 15, UIKit.DIM)
	_content.add_child(l)

## ---------------------------------------------------------------- 탭
func _display_tab() -> void:
	var langs := []
	var cur := 0
	for i in GameSettings.LANGUAGES.size():
		langs.append(GameSettings.LANGUAGES[i][1])
		if GameSettings.LANGUAGES[i][0] == GameSettings.text_language:
			cur = i
	var lo := OptionButton.new()
	for l in langs:
		lo.add_item(l)
	lo.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lo.select(cur)
	lo.item_selected.connect(func(i):
		GameSettings.set_value(&"text_language", GameSettings.LANGUAGES[i][0])
		_show_tab(0))
	_row("언어 (화면·자막)", lo)
	var vo := OptionButton.new()
	vo.add_item("한국어")
	vo.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	vo.select(0)
	_row("음성 언어", vo, "다른 언어 음성 준비 중")
	_row("화면 모드", _option("window_mode", ["전체 화면", "창 모드", "테두리 없는 창"], GameSettings.window_mode))
	var res := []
	for r in GameSettings.RESOLUTIONS:
		res.append("%d × %d" % [r.x, r.y])
	_row("해상도", _option("resolution", res, GameSettings.resolution), "창 모드에서 적용")
	_row("밝기", _slider(func(): return GameSettings.brightness,
		func(x): GameSettings.set_value(&"brightness", x), 0.6, 1.5, 0.05))
	_row("그래픽 품질", _option("graphics_quality", ["낮음", "보통", "높음"], GameSettings.graphics_quality), "높음: 실시간 전역 조명")
	_row("수직 동기화", _check("vsync"))
	var fps := []
	for f in GameSettings.FPS_LIMITS:
		fps.append("제한 없음" if f == 0 else "%d" % f)
	_row("FPS 제한", _option("fps_limit", fps, GameSettings.fps_limit))
	_row("시야각 (FOV)", _slider(func(): return GameSettings.fov,
		func(x): GameSettings.set_value(&"fov", x), 60.0, 80.0, 1.0, "%d°", 1.0))

func _controls_tab() -> void:
	_row("마우스 감도", _slider(func(): return GameSettings.mouse_sensitivity / 0.0022,
		func(x): GameSettings.set_value(&"mouse_sensitivity", x * 0.0022), 0.2, 3.0, 0.05, "%.2f", 1.0))
	_row("마우스 상하 반전", _check("invert_y"))
	_section("조작키 (항목을 누른 뒤 새 키를 누르세요 · ESC 취소)")
	for pair in GameSettings.REBINDABLE:
		var b := Button.new()
		b.text = GameSettings.key_for(pair[0])
		b.pressed.connect(func():
			_waiting_action = pair[0]
			b.text = "… 새 키 입력")
		_row(tr(pair[1]), b)
	var fixed := [["마우스", "둘러보기"], ["E / 마우스 왼쪽", "조사 중 가져가기"], ["ESC", "일시정지 / 조사 닫기"], ["F1", "조작 안내"]]
	for p in fixed:
		_row(p[1], UIKit.label(p[0], 18, UIKit.DIM))
	var reset := Button.new()
	reset.text = "기본값으로"
	reset.pressed.connect(func():
		GameSettings.reset_keybinds()
		_show_tab(1))
	_row("", reset)

func _sound_tab() -> void:
	_row("전체 음량", _vol("Master"))
	_row("캐릭터 음성", _vol("Voice"))
	_row("배경음악", _vol("Music"))
	_row("환경음", _vol("Ambience"))
	_row("효과음", _vol("SFX"))
	_row("호흡·심장 박동", _slider(func(): return GameSettings.breathing_intensity,
		func(x): GameSettings.set_value(&"breathing_intensity", x), 0.0, 1.0, 0.05))

func _access_tab() -> void:
	_row("자막 표시", _check("subtitles"))
	_row("자막 크기", _option("subtitle_size", ["작게", "보통", "크게", "아주 크게"], GameSettings.subtitle_size))
	_row("자막 배경", _check("subtitle_bg"))
	_row("주요 효과음 자막", _check("sound_captions"))
	_row("카메라 흔들림", _slider(func(): return GameSettings.camera_shake,
		func(x): GameSettings.set_value(&"camera_shake", x), 0.0, 1.0, 0.05))
	_row("조명 깜빡임 완화", _check("reduce_flashes"))
	_row("조사 글자 크기", _option("inspect_text_size", ["작게", "보통", "크게", "아주 크게"], GameSettings.inspect_text_size))
	_row("조준점", _option("crosshair_mode", ["항상 표시", "상호작용 때만", "끔"], GameSettings.crosshair_mode))
	_row("상호작용 힌트", _check("interaction_hints"))
	_row("현재 목표 표시", _check("objective_hints"))
