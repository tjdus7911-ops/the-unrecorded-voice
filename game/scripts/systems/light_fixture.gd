class_name LightFixture
extends Node3D
## 조명기구 상태 관리. 자식 Light3D 전부와 (선택) 발광 메시를 함께 제어한다.
## 챕터·스토리 진행에 따라 set_state()로 바꾼다.

enum State {
	NORMAL,         ## 정상 작동
	FLICKER,        ## 간헐적 깜빡임
	DEAD,           ## 스위치를 눌러도 켜지지 않음 (고장)
	NEEDS_POWER,    ## 전력 복구 필요 (차단기 복구 시 restore_power)
	STORY_OFF,      ## 스토리 이벤트로 꺼짐
}

signal state_changed(state: State)

@export var state: State = State.NORMAL
@export var switched_on := true
@export var emissive_mesh: MeshInstance3D
@export var flicker_min_on := 0.05
@export var flicker_max_on := 1.8
@export var hum_sound: AudioStream            ## 형광등 전기 소리

var _lights: Array[Light3D] = []
var _energy: Array[float] = []
var _t := 0.0
var _lit := true
var _emissive_mat: StandardMaterial3D
var _emission_energy := 1.0

func _ready() -> void:
	# 자식 조명이 나중에 추가되어도 상태를 적용한다
	child_entered_tree.connect(func(_n): _collect.call_deferred())
	if hum_sound:
		var p := AudioStreamPlayer3D.new()
		p.stream = hum_sound
		p.bus = &"Ambience"
		p.unit_size = 2.0
		p.autoplay = true
		add_child(p)
	_collect()

func _collect() -> void:
	for c in find_children("*", "Light3D", true, false):
		if not _lights.has(c):
			_lights.append(c)
			_energy.append((c as Light3D).light_energy)
	if emissive_mesh and _emissive_mat == null and emissive_mesh.get_active_material(0) is StandardMaterial3D:
		_emissive_mat = emissive_mesh.get_active_material(0).duplicate()
		emissive_mesh.material_override = _emissive_mat
		_emission_energy = _emissive_mat.emission_energy_multiplier
	_apply()

## 실제로 빛을 내는 Light3D가 하나라도 있는가 (테스트용)
func any_light_visible() -> bool:
	for l in _lights:
		if l.visible:
			return true
	return false

func set_state(s: State) -> void:
	state = s
	_apply()
	state_changed.emit(s)

func press_switch() -> void:
	switched_on = not switched_on
	_apply()

func restore_power() -> void:
	if state == State.NEEDS_POWER:
		set_state(State.NORMAL)

func is_emitting() -> bool:
	return _lit

func _powered() -> bool:
	return switched_on and (state == State.NORMAL or state == State.FLICKER)

func _apply() -> void:
	_set_lit(_powered())

func _set_lit(on: bool, k := 1.0) -> void:
	_lit = on
	for i in _lights.size():
		_lights[i].visible = on
		_lights[i].light_energy = _energy[i] * k
	if _emissive_mat:
		_emissive_mat.emission_energy_multiplier = _emission_energy * k if on else 0.0

func _process(delta: float) -> void:
	if state != State.FLICKER or not switched_on:
		return
	_t -= delta
	if _t <= 0.0:
		var reduce: bool = GameSettings.reduce_flashes
		if _lit:
			_set_lit(false)
			_t = randf_range(0.03, 0.12) if randf() < 0.7 else randf_range(0.3, 0.9)
		else:
			_set_lit(true, 0.7 if reduce else 1.0)
			_t = randf_range(flicker_min_on, flicker_max_on) * (3.0 if reduce else 1.0)
