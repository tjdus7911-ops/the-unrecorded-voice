class_name Flashlight
extends Node3D
## 손전등 — F키 토글, 시점 추종(관성 흔들림), 실시간 그림자, 공포 시 손 떨림.
## 1인칭 손·손전등 모델은 `view_model_scene`(Blender GLB)으로 교체한다.
## 배터리: 기본 무제한. `battery_enabled`는 난이도 옵션용 구조만 존재.

signal toggled(on: bool)

@export var view_model_scene: PackedScene     ## 1인칭 손전등 모델 (prop_flashlight.glb)
@export var follow_stiffness := 14.0          ## 높을수록 카메라에 빠르게 붙음
@export var hold_offset := Vector3(0.2, -0.235, -0.44)
@export var light_energy := 6.0
@export var light_range := 20.0
@export var spot_angle := 30.0
@export var click_on_sound: AudioStream       ## 비어 있으면 Sounds 라이브러리의 sfx_flashlight_on/off 사용
@export var click_off_sound: AudioStream

@export_group("Battery (disabled by design)")
@export var battery_enabled := false
@export var battery_seconds := 600.0

var is_on := false
var battery := 1.0
var _tremble := 0.0
var _noise_t := 0.0
var _flicker_override := 1.0   ## 잡음(귀신) 접근 시 외부에서 0~1로 약화

@onready var _camera: Camera3D = get_parent().get_node("Head/Camera3D")
var spot: SpotLight3D
var _rig: Node3D
var _sfx: AudioStreamPlayer
var _model: Node3D
var _switch: Node3D
var _switch_rest := Vector3.ZERO
var _bulb_mat: StandardMaterial3D
var _led_mat: StandardMaterial3D

func _ready() -> void:
	top_level = true
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	if view_model_scene == null and ResourceLoader.exists("res://assets/models/props/prop_flashlight.gltf"):
		view_model_scene = load("res://assets/models/props/prop_flashlight.gltf")
	if view_model_scene:
		_model = view_model_scene.instantiate()
		_rig.add_child(_model)
		_model.position = Vector3(0, 0, 0.13)        # 손잡이 중앙을 쥔 위치로
		for c in _model.find_children("*", "CollisionObject3D", true, false):
			c.queue_free()
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(mi as MeshInstance3D).layers = 2       # 1인칭 모델 전용 레이어 (거울·반사 제외용)
		_switch = _model.find_child("prop_flashlight_switch", true, false) as Node3D
		if _switch:
			_switch_rest = _switch.position
		_bulb_mat = _emissive(_model.find_child("prop_flashlight_bulb", true, false), Color(1, 0.9, 0.75), 8.0)
		_led_mat = _emissive(_model.find_child("prop_flashlight_indicator", true, false), Color(1, 0.1, 0.05), 3.0)
	spot = SpotLight3D.new()
	spot.name = "Spot"
	spot.light_color = Color(1.0, 0.94, 0.84)        # 약 4800K 백열 계열 손전등
	spot.light_energy = light_energy
	spot.spot_range = light_range
	spot.spot_angle = spot_angle
	spot.spot_angle_attenuation = 0.6
	if ResourceLoader.exists("res://assets/textures/fx/flashlight_cookie.png"):
		spot.light_projector = load("res://assets/textures/fx/flashlight_cookie.png")   # 중앙 핫스폿·반사판 링·부드러운 감쇠
	spot.spot_attenuation = 1.2
	spot.shadow_enabled = true                       # 벽·문을 통과하지 않는 빛
	spot.shadow_bias = 0.03
	spot.shadow_blur = 1.2
	spot.shadow_normal_bias = 1.0
	spot.light_size = 0.03
	spot.position = Vector3(0, 0, -0.14)
	spot.visible = false
	_rig.add_child(spot)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = &"SFX"
	add_child(_sfx)
	global_transform = _target_transform()
	_rig.visible = Inventory.has_flashlight       # 손전등을 얻기 전에는 손에 들고 있지 않다
	Inventory.item_added.connect(func(id): if id == &"flashlight": _rig.visible = true)

func toggle() -> bool:
	if not Inventory.has_flashlight:
		return false
	set_on(not is_on)
	return true

func set_on(on: bool) -> void:
	if battery_enabled and battery <= 0.0:
		on = false
	is_on = on
	spot.visible = on
	_sfx.stream = click_on_sound if on else click_off_sound
	if _sfx.stream:
		_sfx.play()
	else:
		Sounds.play("sfx_flashlight_on" if on else "sfx_flashlight_off", &"SFX", -4.0)
	if _bulb_mat:
		_bulb_mat.emission_enabled = on
	if _led_mat:
		_led_mat.emission_enabled = on
	_play_press_anim()
	toggled.emit(on)

func _emissive(node: Node, col: Color, energy: float) -> StandardMaterial3D:
	var mi := node as MeshInstance3D
	if mi == null:
		mi = node.find_child("*", true, false) as MeshInstance3D if node else null
	if mi == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.6)
	m.emission = col
	m.emission_energy_multiplier = energy
	m.emission_enabled = false
	mi.material_override = m
	return m

func set_tremble(amount: float) -> void:
	_tremble = clampf(amount, 0.0, 1.0)

func set_interference(strength01: float) -> void:
	_flicker_override = 1.0 - clampf(strength01, 0.0, 1.0)

func _target_transform() -> Transform3D:
	return _camera.global_transform * Transform3D(Basis(), hold_offset)

func _process(delta: float) -> void:
	# 관성 추종: 시점을 빠르게 돌리거나 달릴 때 자연스럽게 늦게 따라온다.
	var target := _target_transform()
	var w := clampf(delta * follow_stiffness, 0.0, 1.0)
	var q := global_transform.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), w)
	global_transform = Transform3D(Basis(q), global_position.lerp(target.origin, w))

	# 공포 시 손의 미세한 떨림 (카메라 흔들림 설정을 따른다)
	_noise_t += delta
	var amp := _tremble * 0.0035 * float(GameSettings.camera_shake)
	_rig.rotation = Vector3(sin(_noise_t * 23.0) * amp * 3.0, sin(_noise_t * 17.3 + 1.3) * amp * 3.0, 0.0)

	if is_on:
		var e := light_energy * _flicker_override
		if _flicker_override < 0.99 and randf() < 0.15:
			e *= randf_range(0.0, 0.6)
		spot.light_energy = e
		if battery_enabled:
			battery = maxf(battery - delta / battery_seconds, 0.0)
			if battery <= 0.0:
				set_on(false)

func _play_press_anim() -> void:
	# 전원 버튼을 누르는 손의 짧은 움직임 (최종 모델의 버튼 애니메이션으로 교체)
	var tw := create_tween()
	tw.tween_property(_rig, "position", Vector3(0, -0.006, 0.004), 0.05)
	tw.tween_property(_rig, "position", Vector3.ZERO, 0.09)
	if _switch:   # 실제 전원 버튼이 눌렸다 올라옴
		var tw2 := create_tween()
		tw2.tween_property(_switch, "position", _switch_rest + Vector3(0, -0.0015, 0), 0.04)
		tw2.tween_property(_switch, "position", _switch_rest, 0.08)
