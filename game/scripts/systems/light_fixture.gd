class_name LightFixture
extends Node3D
## 조명기구 상태 관리. 자식 Light3D 전부와 발광 메시(형광등 튜브·LED 패널·전구)를 함께 제어한다.
## 챕터·스토리 진행에 따라 set_state()로 바꾼다.

enum State {
	NORMAL,         ## 정상 작동
	FLICKER,        ## 간헐적 깜빡임
	DEAD,           ## 스위치를 눌러도 켜지지 않음 (고장)
	NEEDS_POWER,    ## 전력 복구 필요 (차단기 복구 시 restore_power)
	STORY_OFF,      ## 스토리 이벤트로 꺼짐
}

signal state_changed(state: State)
signal flickered(on: bool)

@export var state: State = State.NORMAL
@export var switched_on := true
@export var emissive_mesh: MeshInstance3D
@export var emissive_color := Color(1.0, 0.75, 0.45)
@export var emissive_energy := 4.0
@export var flicker_min_on := 0.05
@export var flicker_max_on := 1.8
@export var hum_sound: AudioStream            ## 형광등 전기 소리

var emissive_nodes: Array = []                ## MeshInstance3D 또는 그 부모 노드
var _lights: Array[Light3D] = []
var _energy: Array[float] = []
var _mats: Array[StandardMaterial3D] = []
var _t := 0.0
var _lit := true
var _hum: AudioStreamPlayer3D
## 요구사항 20: 다른 공간(1998)에 있는 동안 소리를 멈춘다
var muted := false:
	set(v):
		muted = v
		_apply_hum()

func _ready() -> void:
	child_entered_tree.connect(func(_n): _collect.call_deferred())
	if hum_sound:
		var p := AudioStreamPlayer3D.new()
		p.stream = hum_sound
		p.bus = &"Ambience"
		p.unit_size = 2.0
		p.autoplay = true
		add_child(p)
		_hum = p
	_collect()

func _collect() -> void:
	for c in find_children("*", "Light3D", true, false):
		if not _lights.has(c):
			_lights.append(c)
			_energy.append((c as Light3D).light_energy)
	if emissive_mesh and not emissive_nodes.has(emissive_mesh):
		emissive_nodes.append(emissive_mesh)
	if _mats.is_empty() and not emissive_nodes.is_empty():
		for n in emissive_nodes:
			var mis: Array = [n] if n is MeshInstance3D else (n as Node).find_children("*", "MeshInstance3D", true, false)
			for mi in mis:
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.85, 0.85, 0.83)
				m.emission = emissive_color
				m.emission_energy_multiplier = emissive_energy
				m.roughness = 0.4
				(mi as MeshInstance3D).material_override = m
				_mats.append(m)
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

## 요구사항 20: 형광등 웅웅 소리는 불이 켜져 있을 때만 (예전엔 정전 중에도 계속 났다)
func _apply_hum() -> void:
	if _hum:
		_hum.stream_paused = muted or not _lit

func _set_lit(on: bool, k := 1.0) -> void:
	_lit = on
	_apply_hum()
	for i in _lights.size():
		_lights[i].visible = on
		_lights[i].light_energy = _energy[i] * k
	for m in _mats:
		m.emission_enabled = on
		m.emission_energy_multiplier = emissive_energy * k

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
		flickered.emit(_lit)
