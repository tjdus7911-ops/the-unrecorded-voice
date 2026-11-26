extends Node
## 사운드 라이브러리 (autoload: Sounds)
## res://data/config/audio.json 의 사운드 ID로만 재생한다 — 코드에 파일 경로 없음. 음원 교체는 JSON만 수정.

const CONFIG := "res://data/config/audio.json"

var _lib := {}            ## id -> Array[AudioStream]
var _last := {}           ## id -> 마지막으로 고른 인덱스 (연속 반복 방지)
var captions_enabled := false

signal caption(text: String, direction: String)

func _ready() -> void:
	var f := FileAccess.open(CONFIG, FileAccess.READ)
	if f == null:
		push_warning("Sounds: audio.json missing")
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for id in data.get("sounds", {}):
		var entry: Dictionary = data["sounds"][id]
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
func play(id: String, bus := &"SFX", volume_db := 0.0, pitch_var := 0.0) -> AudioStreamPlayer:
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
	return p

## 3D 위치 재생 (원샷). caption_text 가 있으면 접근성 자막 신호를 보낸다.
func play_at(id: String, pos: Vector3, bus := &"SFX", volume_db := 0.0, parent: Node = null, pitch_var := 0.04,
		caption_text := "", unit_size := 3.0) -> AudioStreamPlayer3D:
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
	var host := parent if parent else get_tree().current_scene
	host.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
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
