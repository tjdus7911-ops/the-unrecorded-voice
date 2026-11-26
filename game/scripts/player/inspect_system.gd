class_name InspectSystem
extends Node3D
## 오브젝트 조사: 오른손으로 물건을 실제 크기 그대로 들고 눈앞으로 가져와 본다.
##  - 마우스 이동: 돌려 보기 (손목이 함께 돌아감) · 우클릭: 뒤집기(앞/뒤) · 휠: 가까이/멀리
##  - E / 좌클릭: 가져가기(가능할 때) · ESC: 내려놓기
## 손 모델이 없으면(테스트 경로) 카메라 앞에 띄우는 방식으로 동작한다.
## 플레이어 이동·시점은 조사 중 멈춘다 (GameFlow.State.INSPECT).

signal opened(target: Interactable)
signal closed(target: Interactable, picked: bool)

const VIEW_POS := Vector3(-0.035, -0.015, -0.29)    ## 손에 든 물체 중심 (카메라 루트 공간) — 화면 중앙 가까이, 설명 패널과 겹치지 않게

var player: PlayerController
var active: Interactable
var _holder: Node3D
var _copy: Node3D
var _fill: OmniLight3D
var _rot := Vector2.ZERO
var _flip := 0.0
var _flip_target := 0.0
var _dist := 0.0
var _just_opened := false
var _hands := false
var _size := Vector3.ONE * 0.1

func _ready() -> void:
	_holder = Node3D.new()
	_holder.position = Vector3(0, -0.02, -0.42)
	add_child(_holder)
	_fill = OmniLight3D.new()
	_fill.position = Vector3(0.15, 0.15, -0.15)
	_fill.light_energy = 0.35
	_fill.omni_range = 1.2
	_fill.light_color = Color(1.0, 0.95, 0.88)
	_fill.visible = false
	add_child(_fill)

func is_open() -> bool:
	return active != null

func can_pick() -> bool:
	return active != null and active.pickup_item != &""

func open(target: Interactable) -> void:
	if active or target.inspect_visual == null:
		return
	active = target
	_copy = target.inspect_visual.duplicate(0) as Node3D
	for c in _copy.find_children("*", "CollisionObject3D", true, false):
		c.queue_free()
	target.inspect_visual.visible = false       # 손에 든 사본만 보이게 (원본은 잠시 숨김)
	var aabb := Interactable.local_aabb(target.inspect_visual)
	_size = aabb.size
	var flat := aabb.size.y < 0.25 * maxf(aabb.size.x, aabb.size.z)
	_flip = 0.0
	_flip_target = 0.0
	_dist = 0.0
	var arms: ViewmodelArms = player.arms if player else null
	_hands = arms != null and arms.enabled and player.hands_animate
	if _hands:
		# 실제 크기로 손에 든다: 물체 중심을 원점으로 옮긴 피벗(_holder)을 오른손이 쥔다
		_holder.top_level = true
		_holder.scale = Vector3.ONE
		_holder.add_child(_copy)
		_copy.transform = Transform3D(Basis(), -aabb.get_center())
		# 납작한 물건(메모·운송장·테이프)은 앞면이 눈을 향하게 세운다
		_rot = Vector2(deg_to_rad(90), 0.0) if flat else Vector2(deg_to_rad(20), deg_to_rad(-25))
		var objT := _obj_transform()
		# 오른손 엄지·검지로 물건의 아래·오른쪽 모서리를 집는 자세
		var F := Vector3(-0.32, 0.93, -0.12).normalized()
		var R := Vector3(0.05, 0.1, 1.0)
		R = (R - F * R.dot(F)).normalized()
		var half_w := minf(_size.x, 0.2) * 0.42
		var half_h := minf(maxf(_size.z, _size.y), 0.22) * 0.38
		var corner := objT.origin + Vector3(half_w, -half_h, 0.0)
		var wrist := corner - F * 0.125 + Vector3(0.0, 0.0, 0.01)
		var rh: ViewmodelArms.Hand = arms.sides["R"]
		if rh.held and rh.mode == ViewmodelArms.Mode.HOLD_RECORDER:
			rh.held.visible = false              # 녹음기는 잠시 주머니에 (조사 후 다시 꺼냄)
		arms.attach_at("R", _holder, objT, wrist, F, R)
		rh.mode = ViewmodelArms.Mode.HOLD_OBJECT
		rh.pose_want = "pinch"
		_holder.global_transform = arms.global_transform * objT
	else:
		_holder.top_level = false
		_holder.transform = Transform3D(Basis(), Vector3(0, -0.02, -0.42))
		_holder.add_child(_copy)
		_copy.transform = Transform3D.IDENTITY
		var size := maxf(aabb.size.length(), 0.01)
		var s := clampf((0.3 if flat else 0.24) / size, 0.2, 4.0)
		_copy.scale = Vector3.ONE * s
		_copy.position = -aabb.get_center() * s
		_rot = Vector2(deg_to_rad(80), 0.0) if flat else Vector2(deg_to_rad(25), deg_to_rad(-20))
		_apply_rot()
	_fill.visible = not player.flashlight.is_on
	player.input_enabled = false
	GameFlow.set_state(GameFlow.State.INSPECT)
	_just_opened = true
	Sounds.play("sfx_paper_rustle" if _is_paper() else "sfx_pickup", &"SFX", -6.0)
	opened.emit(target)

func _is_paper() -> bool:
	return active != null and (active.pickup_item == &"note_prologue" or active.inspect_title.contains("운송장") or active.inspect_title.contains("메모"))

func _obj_transform() -> Transform3D:
	var b := Basis.from_euler(Vector3(_rot.x, _rot.y, 0.0))
	b = Basis(Vector3.UP, _flip) * b
	var extra := clampf(maxf(_size.x, maxf(_size.y, _size.z)) - 0.12, 0.0, 0.25) * 0.8
	return Transform3D(b, VIEW_POS + Vector3(0, 0, -extra - _dist))

func close(pick := false) -> void:
	if active == null:
		return
	var t := active
	if is_instance_valid(t.inspect_visual):
		t.inspect_visual.visible = true
	var arms: ViewmodelArms = player.arms if player else null
	if _hands and arms:
		arms.detach("R")
		var rec: Node3D = player.get("held_recorder")
		if rec:
			rec.visible = true
			arms.hold_recorder(rec)
		else:
			arms.set_mode("R", ViewmodelArms.Mode.HIDDEN)
	if pick and t.pickup_item != &"":
		Inventory.add(t.pickup_item)
		Sounds.play("sfx_pickup", &"SFX", -2.0)
		var rm := t.remove_on_pickup if t.remove_on_pickup else t.inspect_visual
		if rm:
			rm.queue_free()
		t.queue_free()
	_copy.queue_free()
	_copy = null
	_holder.top_level = false
	active = null
	_fill.visible = false
	player.input_enabled = true
	if GameFlow.state == GameFlow.State.INSPECT:
		GameFlow.set_state(GameFlow.State.PLAYING)
	closed.emit(t, pick)

func _apply_rot() -> void:
	_holder.basis = Basis.from_euler(Vector3(_rot.x, _rot.y, 0))

## 조사 중 마우스 이동 = 물체 회전 (GUI보다 먼저 받음). 카메라 시점은 INSPECT 상태라 움직이지 않는다.
func _input(event: InputEvent) -> void:
	if active == null or GameFlow.state != GameFlow.State.INSPECT:
		return
	if event is InputEventMouseMotion:
		var lim := 1.25 if _hands else 3.2
		_rot.y = clampf(_rot.y + event.screen_relative.x * 0.006, -lim, lim)
		_rot.x = clampf(_rot.x + event.screen_relative.y * 0.006, -1.6, 1.9)
		if not _hands:
			_apply_rot()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				flip()
			MOUSE_BUTTON_WHEEL_UP:
				_dist = clampf(_dist - 0.02, -0.08, 0.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = clampf(_dist + 0.02, -0.08, 0.15)
			MOUSE_BUTTON_LEFT:
				if not _just_opened and can_pick():
					close(true)
		get_viewport().set_input_as_handled()

## 앞면 ↔ 뒷면
func flip() -> void:
	_flip_target = PI if _flip_target < 0.5 else 0.0
	Sounds.play("sfx_paper_rustle" if _is_paper() else "sfx_pickup", &"SFX", -12.0)

func _unhandled_input(event: InputEvent) -> void:
	if active == null or GameFlow.state != GameFlow.State.INSPECT:
		return
	if event.is_action_pressed("interact"):
		if _just_opened:
			return
		close(can_pick())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		close(false)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_just_opened = false
	if active == null or not _hands:
		return
	_flip = lerp_angle(_flip, _flip_target, clampf(delta * 8.0, 0.0, 1.0))
	player.arms.hold_object_at("R", _obj_transform(), 16.0)
