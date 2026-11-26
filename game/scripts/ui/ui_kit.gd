class_name UIKit
extends RefCounted
## 메뉴 UI 공통 스타일 — 어둡고 절제된 톤. 카드형 패널·둥근 버튼·그라데이션 없음.

const TEXT := Color(0.90, 0.88, 0.84)
const DIM := Color(0.62, 0.60, 0.57)
const DISABLED := Color(0.36, 0.35, 0.34)
const ACCENT := Color(0.66, 0.17, 0.14)          ## 녹음 표시등 같은 탁한 빨강 (선택 표시)
const PANEL := Color(0.055, 0.055, 0.058, 0.94)
const FONT_REG := "res://assets/fonts/NotoSansKR-Regular-subset.otf"
const FONT_MED := "res://assets/fonts/NotoSansKR-Medium-subset.otf"

static func font(medium := false) -> Font:
	return load(FONT_MED if medium else FONT_REG)

static func label(text: String, size: int, color := TEXT, medium := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(medium))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func flat_box(color := Color(0, 0, 0, 0), margin := Vector2(0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.content_margin_left = margin.x
	s.content_margin_right = margin.x
	s.content_margin_top = margin.y
	s.content_margin_bottom = margin.y
	return s

## 메뉴 항목. style: "bar"(타이틀: 왼쪽 붉은 세로 막대) / "box"(일시정지: 옅은 사각 배경)
static func menu_item(text: String, size: int, style := "bar") -> Button:
	var b := Button.new()
	b.set_script(load("res://scripts/ui/menu_item.gd"))
	b.text = text
	b.set("style", style)
	b.add_theme_font_override("font", font(false))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_hover_pressed_color", TEXT)
	b.add_theme_color_override("font_disabled_color", DISABLED)
	var empty := flat_box(Color(0, 0, 0, 0), Vector2(22 if style == "bar" else 36, 6))
	var sel := flat_box(Color(1, 1, 1, 0.075) if style == "box" else Color(0, 0, 0, 0), Vector2(22 if style == "bar" else 36, 6))
	for st in ["normal", "disabled", "pressed"]:
		b.add_theme_stylebox_override(st, empty)
	for st in ["hover", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, sel)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if style == "bar" else HORIZONTAL_ALIGNMENT_CENTER
	return b

## 설정 화면 등에서 쓰는 작은 컨트롤 테마
static func control_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = 19
	t.set_color("font_color", "Label", TEXT)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_color("font_color", cls, DIM)
		t.set_color("font_hover_color", cls, TEXT)
		t.set_color("font_focus_color", cls, TEXT)
		t.set_color("font_pressed_color", cls, TEXT)
		t.set_stylebox("normal", cls, flat_box(Color(1, 1, 1, 0.035), Vector2(12, 5)))
		t.set_stylebox("hover", cls, flat_box(Color(1, 1, 1, 0.08), Vector2(12, 5)))
		t.set_stylebox("pressed", cls, flat_box(Color(1, 1, 1, 0.08), Vector2(12, 5)))
		t.set_stylebox("focus", cls, flat_box(Color(1, 1, 1, 0.08), Vector2(12, 5)))
	var track := flat_box(Color(1, 1, 1, 0.14))
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	var fill := flat_box(Color(0.75, 0.73, 0.69, 0.8))
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var pop := flat_box(Color(0.08, 0.08, 0.085, 0.98), Vector2(10, 6))
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_color("font_color", "PopupMenu", DIM)
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_stylebox("hover", "PopupMenu", flat_box(Color(1, 1, 1, 0.08)))
	return t

## UI 효과음 (일시정지 중에도 들리도록 자체 플레이어 사용)
static func click(owner: Node, id := "sfx_deck_button", db := -20.0) -> void:
	var s: AudioStream = Sounds.pick(id)
	if s == null or owner == null or not owner.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = db
	p.bus = &"SFX"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
