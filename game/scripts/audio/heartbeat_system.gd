class_name HeartbeatSystem
extends Node
## 심장 박동 — 위험도(0~1)에 따라 BPM·음량을 연속적으로 바꾼다.
## 위험 상승은 빠르게(약 1.5초), 해제는 천천히(약 6초) 따라간다.

const CONFIG_PATH := "res://data/config/heartbeat.json"

@export var bpm_safe := 65.0
@export var bpm_max := 140.0
@export var db_safe := -40.0
@export var db_max := -14.0          ## 상한 — 발소리·단서 음성을 가리지 않도록
@export var rise_time := 1.5
@export var fall_time := 6.0

var danger_target := 0.0
var level := 0.0                      ## 평활화된 위험도
var beats_played := 0
var _streams: Array = []
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _beat_timer := 0.0

func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Heartbeat"
		add_child(p)
		_players.append(p)
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f:
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		for path in data.get("beats", []):
			if ResourceLoader.exists(path):
				_streams.append(load(path))

func set_danger(d: float) -> void:
	danger_target = clampf(d, 0.0, 1.0)

func current_bpm() -> float:
	return lerpf(bpm_safe, bpm_max, level)

func current_db() -> float:
	return lerpf(db_safe, db_max, sqrt(level))

func _process(delta: float) -> void:
	var t := rise_time if danger_target > level else fall_time
	level += (danger_target - level) * clampf(delta * 3.0 / t, 0.0, 1.0)
	if level < 0.03:
		return   # 안전 상태: 사실상 들리지 않음
	_beat_timer -= delta
	if _beat_timer <= 0.0:
		var interval := 60.0 / current_bpm()
		if level > 0.85:
			interval *= randf_range(0.9, 1.1)   # 추격: 불규칙
		_beat_timer = interval
		_beat()

func _beat() -> void:
	beats_played += 1
	if _streams.is_empty():
		return
	var p := _players[_next]
	_next = 1 - _next
	p.stream = _streams.pick_random()
	p.volume_db = current_db() + randf_range(-1.0, 1.0)
	p.pitch_scale = lerpf(0.95, 1.08, level)
	p.play()
