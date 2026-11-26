class_name Flashlight
extends Node3D
## 손전등 — F키 토글, 시점 추종(관성 흔들림), 실시간 그림자, 공포 시 손 떨림.
## 1인칭 손·손전등 모델은 `view_model_scene`(Blender GLB)으로 교체한다.
## 배터리: 기본 무제한. `battery_enabled`는 난이도 옵션용 구조만 존재.

signal toggled(on: bool)

@export var view_model_scene: PackedScene     ## art: prop_flashlight.glb (제작 예정)
@export var follow_stiffness := 14.0          ## 높을수록 카메라에 빠르게 붙음
@export var hold_offset := Vector3(0.22, -0.2, -0.38)
@export var light_energy := 4.0
@export var light_range := 20.0
@export var spot_angle := 26.0
@export var click_on_sound: AudioStream
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

func _ready() -> void:
	top_level = true
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	if view_model_scene:
		_rig.add_child(view_model_scene.instantiate())
	spot = SpotLight3D.new()
	spot.name = "Spot"
	spot.light_color = Color(1.0, 0.94, 0.84)        # 약 4800K 백열 계열 손전등
	spot.light_energy = light_energy
	spot.spot_range = light_range
	spot.spot_angle = spot_angle
	spot.spot_angle_attenuation = 1.8                # 중앙이 밝고 가장자리로 어두워짐
	spot.spot_attenuation = 1.2
	spot.shadow_enabled = true                       # 벽·문을 통과하지 않는 빛
	spot.shadow_bias = 0.03
	spot.shadow_normal_bias = 1.0
	spot.light_size = 0.03
	spot.position = Vector3(0, 0, -0.12)
	spot.visible = false
	_rig.add_child(spot)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = &"SFX"
	add_child(_sfx)
	global_transform = _target_transform()

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
	_play_press_anim()
	toggled.emit(on)

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
