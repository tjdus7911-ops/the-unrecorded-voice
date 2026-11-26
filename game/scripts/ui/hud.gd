class_name HUD
extends CanvasLayer
## 미니멀 HUD — 작은 중앙 조준점, 필요할 때만 상호작용 안내, 화면 하단 자막.

var crosshair: ColorRect
var prompt: Label
var subtitle: Label
var _sub_timer := 0.0

func _ready() -> void:
	layer = 10
	crosshair = ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.55)
	crosshair.size = Vector2(3, 3)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(1.5, 1.5)
	add_child(crosshair)

	prompt = Label.new()
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.position += Vector2(-100, 26)
	prompt.size = Vector2(200, 24)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", Color(0.92, 0.9, 0.86, 0.85))
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.visible = false
	add_child(prompt)

	subtitle = Label.new()
	subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle.position += Vector2(-500, -110)
	subtitle.size = Vector2(1000, 60)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	subtitle.add_theme_constant_override("shadow_offset_x", 1)
	subtitle.add_theme_constant_override("shadow_offset_y", 1)
	add_child(subtitle)

	DialogueDB.line_started.connect(_on_line)

func bind_player(p: PlayerController) -> void:
	p.interact_target_changed.connect(_on_target)

func _on_target(t: Interactable) -> void:
	prompt.visible = t != null
	if t:
		prompt.text = "[E] " + t.prompt

func _on_line(line: Dictionary) -> void:
	if not GameSettings.subtitles:
		return
	var id: String = line["line_id"]
	var who := DialogueDB.speaker_name(id)
	subtitle.text = (who + ": " if who != "" else "") + DialogueDB.text_of(id)
	_sub_timer = 0.08 * subtitle.text.length() + 1.6

func _process(delta: float) -> void:
	if _sub_timer > 0.0:
		_sub_timer -= delta
		if _sub_timer <= 0.0:
			subtitle.text = ""
