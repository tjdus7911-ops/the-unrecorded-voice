class_name InspectSystem
extends Node3D
## 오브젝트 조사 화면: 물체를 눈앞(카메라 앞 0.42 m)에 띄우고 마우스로 돌려 본다.
## 플레이어 이동은 잠시 멈춘다. 어두운 곳에서도 읽을 수 있도록 약한 보조광을 켠다 (손전등이 켜져 있으면 생략).

signal opened(target: Interactable)
signal closed(target: Interactable, picked: bool)

var player: PlayerController
var active: Interactable
var _holder: Node3D
var _copy: Node3D
var _fill: OmniLight3D
var _rot := Vector2.ZERO
var _just_opened := false

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

func open(target: Interactable) -> void:
	if active or target.inspect_visual == null:
		return
	active = target
	_copy = target.inspect_visual.duplicate(0) as Node3D
	for c in _copy.find_children("*", "CollisionObject3D", true, false):
		c.queue_free()
	_holder.add_child(_copy)
	target.inspect_visual.visible = false       # 손에 든 사본만 보이게 (원본은 잠시 숨김)
	_copy.transform = Transform3D.IDENTITY
	# 크기를 시야에 맞추고 중심 정렬
	var aabb := Interactable.local_aabb(target.inspect_visual)
	var size := maxf(aabb.size.length(), 0.01)
	# 종이·테이프처럼 납작한 물건은 앞면이 카메라를 향하게 세워서 (읽을 수 있게) 크게 보여 준다
	var flat := aabb.size.y < 0.25 * maxf(aabb.size.x, aabb.size.z)
	var s := clampf((0.3 if flat else 0.24) / size, 0.2, 4.0)
	_copy.scale = Vector3.ONE * s
	_copy.position = -aabb.get_center() * s
	_rot = Vector2(deg_to_rad(80), 0.0) if flat else Vector2(deg_to_rad(25), deg_to_rad(-20))
	_apply_rot()
	_fill.visible = not player.flashlight.is_on
	player.input_enabled = false
	_just_opened = true
	Sounds.play("sfx_paper_rustle" if target.pickup_item == &"note_prologue" else "sfx_pickup", &"SFX", -6.0)
	opened.emit(target)

func close(pick := false) -> void:
	if active == null:
		return
	var t := active
	if is_instance_valid(t.inspect_visual):
		t.inspect_visual.visible = true
	if pick and t.pickup_item != &"":
		Inventory.add(t.pickup_item)
		Sounds.play("sfx_pickup", &"SFX", -2.0)
		var rm := t.remove_on_pickup if t.remove_on_pickup else t.inspect_visual
		if rm:
			rm.queue_free()
		t.queue_free()
	_copy.queue_free()
	_copy = null
	active = null
	_fill.visible = false
	player.input_enabled = true
	closed.emit(t, pick)

func _apply_rot() -> void:
	_holder.basis = Basis.from_euler(Vector3(_rot.x, _rot.y, 0))

func _unhandled_input(event: InputEvent) -> void:
	if active == null:
		return
	if event is InputEventMouseMotion:
		_rot.y += event.relative.x * 0.008
		_rot.x = clampf(_rot.x + event.relative.y * 0.008, -1.5, 1.5)
		_apply_rot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		if _just_opened:
			return
		close(active.pickup_item != &"")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") or event.is_action_pressed("flashlight") and false:
		close(false)
		get_viewport().set_input_as_handled()

func _process(_d: float) -> void:
	_just_opened = false
