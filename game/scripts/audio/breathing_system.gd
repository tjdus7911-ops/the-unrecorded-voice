class_name BreathingSystem
extends Node
## 동적 호흡 시스템 — 플레이어 행동·위험도에 따라 상태를 고르고, 두 플레이어로 크로스페이드한다.
## 음원 목록은 res://data/config/breathing.json (코드에 파일명 하드코딩 없음).

signal state_changed(new_state: StringName)

const CONFIG_PATH := "res://data/config/breathing.json"

## 상태별 호흡 속도(Hz)와 깊이(카메라 흔들림 배율)
const STATE_PARAMS := {
	&"calm":      {"rate": 0.22, "depth": 0.6},
	&"walk":      {"rate": 0.30, "depth": 0.8},
	&"run":       {"rate": 0.75, "depth": 1.6},
	&"exhausted": {"rate": 0.95, "depth": 2.2},
	&"fear":      {"rate": 0.55, "depth": 1.3},
	&"trembling": {"rate": 0.45, "depth": 1.1},
	&"hold":      {"rate": 0.0,  "depth": 0.0},
	&"tearful":   {"rate": 0.35, "depth": 1.2},
	&"uneasy":    {"rate": 0.30, "depth": 0.8},   ## 정전·탐색: 약간 불안 (요구사항 17 §07) — walk 음원 사용
	&"irregular": {"rate": 0.42, "depth": 1.0},   ## 괴물 발견: 불규칙해지기 시작 — fear 음원 사용
}
## 음원이 따로 없는 상태는 가까운 음원 풀을 쓴다
const POOL_ALIAS := {&"uneasy": &"walk", &"irregular": &"fear", &"trembling": &"walk"}

@export var crossfade_time := 0.8
@export var duck_db := -9.0

var state: StringName = &"calm"
var pools := {}          ## state -> Array[AudioStream]
var oneshots := {}       ## gasp / relief / exhale_hard -> Array[AudioStream]
var _history: Array[AudioStream] = []
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _gap_timer := 0.0
var _waiting := false
var _ducked := false
var _forced: StringName = &""   ## 스토리 이벤트가 강제한 상태 (예: tearful)

func _ready() -> void:
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = &"Breathing"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_players[0].finished.connect(_on_finished.bind(0))
	_players[1].finished.connect(_on_finished.bind(1))
	_load_config()
	_start_next(false)

func _load_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_warning("BreathingSystem: config missing")
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for key in data.get("loops", {}):
		pools[StringName(key)] = _load_list(data["loops"][key])
	for key in data.get("oneshots", {}):
		oneshots[StringName(key)] = _load_list(data["oneshots"][key])

func _load_list(paths: Array) -> Array:
	var out: Array = []
	for p in paths:
		if ResourceLoader.exists(p):
			out.append(load(p))
	return out

## 매 물리 프레임 플레이어 상태에서 목표 호흡 상태 결정
func update_from_player(player: PlayerController, delta: float) -> void:
	var target: StringName
	if _forced != &"":
		target = _forced
	elif player.is_hiding and Input.is_action_pressed("hold_breath"):
		target = &"hold"   # 숨 참기 — 지속시간·한계 처리는 귀신 AI 단계에서 연결 (Q-08)
	elif player.is_exhausted:
		target = &"exhausted"
	elif player.is_running and player.danger >= 0.5:
		target = &"run"                  # 추격 중 달리기: 거친 호흡
	elif player.danger >= 0.5:
		target = &"fear"
	elif player.danger >= 0.25:
		target = &"irregular"
	elif player.is_running:
		target = &"run"
	elif player.horizontal_speed() > 0.3:
		target = &"walk"
	elif player.unease >= 0.3:
		target = &"uneasy"
	else:
		target = &"calm"
	set_state(target)
	if _waiting:
		_gap_timer -= delta
		if _gap_timer <= 0.0:
			_waiting = false
			_start_next(false)

func set_state(s: StringName) -> void:
	if s == state:
		return
	var prev := state
	state = s
	state_changed.emit(s)
	# run→walk 등 강도가 낮아질 땐 현재 호흡이 끝난 후 넘어가고, 강해질 땐 바로 크로스페이드
	if _intensity(s) > _intensity(prev) or s == &"hold":
		_start_next(true)

func force_state(s: StringName) -> void:
	_forced = s
	set_state(s if s != &"" else &"calm")

func play_oneshot(kind: StringName) -> void:
	## gasp(놀람) / relief(안도의 한숨) / exhale_hard(숨 참기 한계)
	var list: Array = oneshots.get(kind, [])
	if list.is_empty():
		return
	var p := _players[2]
	p.stream = list.pick_random()
	p.volume_db = 0.0
	p.play()

func duck(on: bool) -> void:
	## 대사 재생 중 호흡 음량을 자연스럽게 낮춘다
	if on == _ducked:
		return
	_ducked = on
	var idx := AudioServer.get_bus_index(&"Breathing")
	var from := AudioServer.get_bus_volume_db(idx)
	var to := from + (duck_db if on else -duck_db)
	var tw := create_tween()
	tw.tween_method(func(v: float): AudioServer.set_bus_volume_db(idx, v), from, to, 0.3 if on else 0.8)

func breath_rate_hz() -> float:
	return STATE_PARAMS.get(state, STATE_PARAMS[&"calm"])["rate"]

func breath_depth() -> float:
	return STATE_PARAMS.get(state, STATE_PARAMS[&"calm"])["depth"]

func current_stream() -> AudioStream:
	return _players[_active].stream

func _intensity(s: StringName) -> int:
	return [&"hold", &"calm", &"uneasy", &"walk", &"trembling", &"irregular", &"tearful", &"fear", &"run", &"exhausted"].find(s)

func _pick(s: StringName) -> AudioStream:
	var list: Array = pools.get(s, pools.get(POOL_ALIAS.get(s, s), []))
	if list.is_empty():
		return null
	var candidates := list.filter(func(a): return not _history.has(a))
	if candidates.is_empty():
		candidates = list
	var chosen: AudioStream = candidates.pick_random()
	_history.append(chosen)
	if _history.size() > 2:
		_history.pop_front()
	return chosen

func _start_next(crossfade: bool) -> void:
	_waiting = false
	var stream := _pick(state)
	var old := _players[_active]
	if crossfade:
		_active = 1 - _active
	var p := _players[_active]
	if stream == null:
		# 숨 참기 등 음원이 없는 상태 → 현재 호흡만 페이드아웃
		_fade(old, -80.0, crossfade_time, true)
		return
	p.stream = stream
	p.pitch_scale = randf_range(0.97, 1.03)
	var target_db := randf_range(-2.0, 0.0)
	if crossfade:
		p.volume_db = -30.0
		p.play()
		_fade(p, target_db, crossfade_time, false)
		_fade(old, -80.0, crossfade_time, true)
	else:
		p.volume_db = target_db
		p.play()

func _fade(p: AudioStreamPlayer, to_db: float, t: float, stop_after: bool) -> void:
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, t)
	if stop_after:
		tw.tween_callback(p.stop)

func _on_finished(idx: int) -> void:
	if idx != _active:
		return
	# 호흡 사이 간격을 자연스럽게 변화 (±15%)
	var base_gap := 0.35 if state == &"calm" else 0.05
	_gap_timer = base_gap * randf_range(0.85, 1.15)
	_waiting = true
