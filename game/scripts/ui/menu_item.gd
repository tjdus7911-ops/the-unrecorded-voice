extends Button
## 메뉴 항목: 마우스 호버와 키보드 선택이 같은 '선택'을 공유한다 (호버 → 포커스).

var style := "bar"

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func(): if not disabled: grab_focus())
	focus_entered.connect(func():
		queue_redraw()
		UIKit.click(self, "sfx_deck_button", -26.0))
	focus_exited.connect(queue_redraw)
	pressed.connect(func(): UIKit.click(self, "sfx_deck_button", -14.0))

func _draw() -> void:
	if style == "bar" and has_focus() and not disabled:
		var h := size.y * 0.62
		draw_rect(Rect2(Vector2(0, (size.y - h) * 0.5), Vector2(4, h)), UIKit.ACCENT)
