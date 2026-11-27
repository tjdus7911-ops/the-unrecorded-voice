class_name ObjectiveMarker
extends Control
## 요구사항 21 — 목표 위치 마커 (노란 위치 핀, 가운데 작은 구멍).
## 3D 목표 지점(핀 끝) → 화면 좌표로 투영. 크기는 거리와 무관하게 1920×1080 기준 약 26 px로 일정.
## 글자·거리 숫자·테두리·깜빡임·발광 없음. 입력(마우스)과 물리 RayCast에 관여하지 않는 순수 UI.

const PIN_H := 26.0            ## 핀 전체 높이 (1920×1080 기준 px)
const COLOR := Color(0.96, 0.82, 0.24)
const HOLE := Color(0.13, 0.12, 0.1)

var world_point := Vector3.INF     ## 목표 지점 (핀 끝). INF = 표시할 목표 없음
var want_visible := false          ## 표시 조건(설정·상태)이 맞는가 — ObjectiveDirector가 정한다
var occlusion_mask := 1
var exclude: Array[RID] = []
var _alpha := 0.0
var _occluded_t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_NONE

func _process(delta: float) -> void:
	var show := false
	var cam := get_viewport().get_camera_3d()
	var pos := Vector2.ZERO
	if want_visible and world_point != Vector3.INF and cam:
		if not cam.is_position_behind(world_point):
			pos = cam.unproject_position(world_point)
			var vr := get_viewport_rect()
			var r := Rect2(Vector2.ZERO, vr.size).grow(-8.0)
			if r.has_point(pos):
				show = true
		# 벽·닫힌 문 너머로 위치를 드러내지 않는다 (짧게 가려지는 건 무시)
		if show and _blocked(cam.global_position, world_point):
			_occluded_t += delta
		else:
			_occluded_t = 0.0
		if _occluded_t > 0.25:
			show = false
	var a := 1.0 if show else 0.0
	# 조준점·손 아이콘을 가리지 않게: 화면 중앙 가까이 오면 옅게
	if show:
		var c := get_viewport_rect().size * 0.5
		if pos.distance_to(c) < 40.0:
			a = 0.35
	_alpha = move_toward(_alpha, a, delta * 5.0)        # 0.2초 페이드 (깜빡임 아님)
	visible = _alpha > 0.01
	if visible:
		_pin_pos = pos
		queue_redraw()

var _pin_pos := Vector2.ZERO

func _blocked(from: Vector3, to: Vector3) -> bool:
	var space := get_viewport().world_3d.direct_space_state if get_viewport().world_3d else null
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, occlusion_mask)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and (hit.position as Vector3).distance_to(to) > 0.35

func _draw() -> void:
	var tip := _pin_pos
	var r := PIN_H * 0.36
	var cy := tip.y - PIN_H + r
	var center := Vector2(tip.x, cy)
	# 원(머리) + 아래로 모이는 끝 — 하나의 다각형
	var pts := PackedVector2Array()
	var a0 := deg_to_rad(-48.0)
	var a1 := deg_to_rad(228.0)
	var n := 28
	for i in n + 1:
		var ang := lerpf(a0, a1, float(i) / n)
		pts.append(center + Vector2(cos(ang), -sin(ang)) * r)
	pts.append(tip)
	var col := COLOR
	col.a *= _alpha
	draw_colored_polygon(pts, col)
	draw_polyline(pts, col, 1.0, true)           # 가장자리 계단 현상만 부드럽게 (같은 색)
	var hole := HOLE
	hole.a *= _alpha
	draw_circle(center, r * 0.38, hole, true, -1.0, true)

## 검수용: 지금 화면에 보이는 핀 끝 위치 (보이지 않으면 null)
func screen_tip():
	return _pin_pos if visible and _alpha > 0.2 else null
