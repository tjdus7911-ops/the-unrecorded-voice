extends Node
## 사운드 라이브러리 (autoload: Sounds)
## res://data/config/audio.json 의 사운드 ID로만 재생한다 — 코드에 파일 경로 없음. 음원 교체는 JSON만 수정.

const CONFIG := "res://data/config/audio.json"

var _lib := {}            ## id -> Array[AudioStream]
var _meta := {}           ## id -> audio.json 항목 (impact_at 등 부가 정보)
var _last := {}           ## id -> 마지막으로 고른 인덱스 (연속 반복 방지)
var captions_enabled := false
## 요구사항 20 사운드 전수 검수: 반복(loop) 음원을 원샷 함수로 틀면 영원히 남던 버그 방지 — 이 시간 뒤 짧게 줄이며 멈춘다
const LOOP_ONESHOT_SECS := 1.2
var loop_oneshot_warnings: Array[String] = []
## 검수: 같은 효과음이 40 ms 안에 같은 자리에서 다시 시작되면 '중복 재생'으로 기록
var duplicate_starts: Array[String] = []
var play_log: Array = []            ## [시각, id, 버스] (최근 400개)
var _last_start := {}               ## id -> [시각, 위치]
var _gt := 0.0                      ## 게임 시간 (일시정지 제외)

func _process(delta: float) -> void:
	_gt += delta

func _note_start(id: String, bus: StringName, pos = null) -> void:
	var now := _gt
	var last = _last_start.get(id)
	if last != null and now - float(last[0]) < 0.04 and (pos == null or last[1] == null or (pos as Vector3).distance_to(last[1]) < 0.5):
		var w := "%s twice within 40 ms" % id
		if not duplicate_starts.has(w):
			duplicate_starts.append(w)
	_last_start[id] = [now, pos]
	play_log.append([now, id, String(bus)])
	if play_log.size() > 400:
		play_log.pop_front()

signal caption(text: String, direction: String)

func _ready() -> void:
	var f := FileAccess.open(CONFIG, FileAccess.READ)
	if f == null:
		push_warning("Sounds: audio.json missing")
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for id in data.get("sounds", {}):
		var entry: Dictionary = data["sounds"][id]
		_meta[id] = entry
		var arr: Array = []
		for p in entry.get("files", []):
			if ResourceLoader.exists(p):
				var s: AudioStream = load(p)
				if entry.get("loop", false):
					if s is AudioStreamOggVorbis:
						(s as AudioStreamOggVorbis).loop = true
					elif s is AudioStreamWAV:
						(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
						(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
				arr.append(s)
		_lib[id] = arr

## audio.json 항목의 부가 정보 (예: sfx_door_slam의 impact_at = 충격 지점 초)
func meta(id: String) -> Dictionary:
	return _meta.get(id, {})

func has(id: String) -> bool:
	return _lib.has(id) and not (_lib[id] as Array).is_empty()

func pick(id: String) -> AudioStream:
	var arr: Array = _lib.get(id, [])
	if arr.is_empty():
		return null
	var i := randi() % arr.size()
	if arr.size() > 1 and _last.get(id, -1) == i:
		i = (i + 1) % arr.size()
	_last[id] = i
	return arr[i]

## 비공간(2D) 재생
func play(id: String, bus := &"SFX", volume_db := 0.0, pitch_var := 0.0, secs := -1.0) -> AudioStreamPlayer:
	var s := pick(id)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	_limit(p, id, secs)
	_note_start(id, bus)
	return p

## 원샷 재생기의 수명 제한: secs > 0 이면 그 시간 뒤 페이드아웃 후 제거. 반복 음원은 secs가 없어도 LOOP_ONESHOT_SECS로 제한
func _limit(p: Node, id: String, secs: float) -> void:
	var looping := is_looping(id)
	if secs <= 0.0 and not looping:
		return
	if secs <= 0.0:
		secs = LOOP_ONESHOT_SECS
		var w := "loop sound '%s' played as one-shot — capped at %.1fs" % [id, secs]
		if not loop_oneshot_warnings.has(w):
			loop_oneshot_warnings.append(w)
			push_warning(w)
	p.set_meta(&"tuv_until", secs)
	get_tree().create_timer(secs, false).timeout.connect(func():
		if not is_instance_valid(p):
			return
		var tw := p.create_tween()
		tw.tween_property(p, "volume_db", -60.0, 0.18)
		tw.tween_callback(p.queue_free))

func is_looping(id: String) -> bool:
	return bool(_meta.get(id, {}).get("loop", false))

## 지금 재생 중인 모든 오디오 재생기 (검수용) — [node, stream 경로, bus, 반복 여부]
func active_players(root: Node = null) -> Array:
	var out: Array = []
	var r := root if root else get_tree().root
	for c in r.find_children("*", "AudioStreamPlayer", true, false) + r.find_children("*", "AudioStreamPlayer3D", true, false):
		if c.playing and not c.stream_paused and c.stream:
			var lp := false
			if c.stream is AudioStreamOggVorbis:
				lp = (c.stream as AudioStreamOggVorbis).loop
			elif c.stream is AudioStreamWAV:
				lp = (c.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
			out.append([c, c.stream.resource_path.get_file(), String(c.bus), lp])
	return out

## 3D 위치 재생 (원샷). caption_text 가 있으면 접근성 자막 신호를 보낸다.
func play_at(id: String, pos: Vector3, bus := &"SFX", volume_db := 0.0, parent: Node = null, pitch_var := 0.04,
		caption_text := "", unit_size := 3.0, secs := -1.0) -> AudioStreamPlayer3D:
	var s := pick(id)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_db = 3.0
	p.attenuation_filter_cutoff_hz = 12000.0
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	var host: Node = parent if parent else (get_tree().current_scene if get_tree().current_scene else get_tree().root)
	host.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	_limit(p, id, secs)
	_note_start(id, bus, pos)
	if caption_text != "" and (captions_enabled or GameSettings.sound_captions):
		caption.emit(caption_text, _direction_to(pos))
	return p

func _direction_to(pos: Vector3) -> String:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return ""
	var local := cam.global_transform.affine_inverse() * pos
	if local.z > 0.5:
		return "뒤쪽"
	if local.x < -0.6:
		return "왼쪽"
	if local.x > 0.6:
		return "오른쪽"
	return "앞쪽"
