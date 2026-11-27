class_name Reticle
extends Control
## 미니멀 조준점 (요구사항 13): 평소 2~3 px 점, 상호작용 가능할 때만 작은 손 아이콘. 코드로 그림 (바이너리 없음).

var hand := false:
	set(v):
		if hand != v:
			hand = v
			queue_redraw()
var dot_visible := true:
	set(v):
		dot_visible = v
		queue_redraw()
const COL := Color(0.94, 0.92, 0.88, 0.85)
const SHADOW := Color(0, 0, 0, 0.55)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(32, 32)
	size = Vector2(32, 32)

func _draw() -> void:
	var c := size * 0.5
	if not hand:
		if dot_visible:
			draw_rect(Rect2(c - Vector2(1.5, 1.5) + Vector2(0.5, 0.5), Vector2(3, 3)), SHADOW)
			draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), COL)
		return
	# 손 아이콘 (약 18 px): 손바닥 + 손가락 4개 + 엄지
	for pass_i in 2:
		var o := Vector2(0.8, 0.8) if pass_i == 0 else Vector2.ZERO
		var col := SHADOW if pass_i == 0 else COL
		var base := c + o + Vector2(-1, 1)
		_round_rect(Rect2(base + Vector2(-5.5, -1.5), Vector2(11, 9)), 3.0, col)
		for f in [[-5.5, -9.0, 2.6], [-2.6, -10.5, 2.6], [0.3, -10.0, 2.6], [3.2, -8.0, 2.4]]:
			_round_rect(Rect2(base + Vector2(f[0], f[1]), Vector2(f[2], 9.5 - (f[1] + 9.0) * 0.0)), 1.3, col)
		var th := PackedVector2Array([base + Vector2(-5.5, 1.0), base + Vector2(-9.5, -2.5), base + Vector2(-8.2, -4.0), base + Vector2(-4.5, -1.0)])
		draw_colored_polygon(th, col)

func _round_rect(r: Rect2, rad: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(ceil(rad)))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
