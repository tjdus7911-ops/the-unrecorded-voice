extends Node
## 대사 데이터베이스 (autoload: DialogueDB)
## res://data/dialogue/*.json 을 읽어 line_id로 조회한다. 음성 파일은 경로로만 참조한다.

signal line_started(line: Dictionary)
signal line_finished(line_id: String)

const DIR := "res://data/dialogue"

var lines := {}        ## line_id -> Dictionary
var characters := {}   ## character_id -> Dictionary
var locale := "ko"          ## 자막(텍스트) 언어 — GameSettings.text_language
var voice_locale := "ko"    ## 음성 언어 — GameSettings.voice_language (자막과 독립)

func _ready() -> void:
	_load_characters()
	_load_lines()

func _load_characters() -> void:
	var f := FileAccess.open("res://data/config/characters.json", FileAccess.READ)
	if f:
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		for c in data.get("characters", []):
			characters[c["character_id"]] = c

func _load_lines() -> void:
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".json"):
			continue
		var f := FileAccess.open(DIR.path_join(file), FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		if typeof(data) != TYPE_DICTIONARY:
			push_error("DialogueDB: invalid JSON %s" % file)
			continue
		for line in data.get("lines", []):
			lines[line["line_id"]] = line

func get_line(id: String) -> Dictionary:
	return lines.get(id, {})

func text_of(id: String) -> String:
	var l := get_line(id)
	var d: Dictionary = l.get("subtitle", l.get("text", {}))
	return d.get(locale, d.get("ko", ""))

func speaker_name(id: String) -> String:
	var l := get_line(id)
	var d: Dictionary = characters.get(l.get("character_id", ""), {}).get("display_name", {})
	return d.get(locale, d.get("ko", ""))

## ---- 음성 정책 (요구사항 15)
## voice: "subtitle" = 자막만 (현재 시점 정우 독백·일반 대화) / "voiced" = 실제 음성 (녹음기 대사·초자연적 목소리)
## 최종 음성은 코드 수정 없이 파일만 넣으면 재생된다:  res://assets/audio/voice/final/<언어>/<대사ID>.ogg (또는 .wav/.mp3)
## 최종 음성이 없으면 임시 자막만 — 무료 TTS는 재생하지 않는다 (개발용 미리듣기: placeholder_tts, 디버그 빌드 전용)
const FINAL_DIR := "res://assets/audio/voice/final"
var placeholder_tts := false

func voice_policy(id: String) -> String:
	var l := get_line(id)
	if l.has("voice"):
		return String(l["voice"])
	if l.get("playback", {}).get("mode", "") == "tape":
		return "voiced"
	return "subtitle"

func final_voice_path(id: String, lang := "") -> String:
	for lg in ([lang] if lang != "" else [voice_locale, "ko"]):
		for ext in ["ogg", "wav", "mp3"]:
			var p := "%s/%s/%s.%s" % [FINAL_DIR, lg, id, ext]
			if ResourceLoader.exists(p) or FileAccess.file_exists(p):
				return p
	return ""

func audio_of(id: String) -> AudioStream:
	if voice_policy(id) != "voiced":
		return null
	var path := final_voice_path(id)
	if path != "":
		return load(path)
	if placeholder_tts and OS.is_debug_build():
		var a: Dictionary = get_line(id).get("audio", {})
		var tp: String = a.get(voice_locale, a.get("ko", ""))
		if tp != "" and ResourceLoader.exists(tp):
			return load(tp)
	return null

## 자막 표시 시간: 음성이 있으면 음성 길이에 맞추고, 없으면 읽는 속도로 (임시 자막)
func duration_of(id: String) -> float:
	var st := audio_of(id)
	if st:
		return st.get_length() + 0.35
	var n := text_of(id).length()
	return clampf(0.075 * n + 1.3, 1.8, 7.0)

## 대사 재생. 음성 파일이 없으면 자막만 표시한다 (게임은 멈추지 않음).
func play_line(id: String, listener: Node3D = null) -> float:
	var line := get_line(id)
	if line.is_empty():
		push_warning("DialogueDB: unknown line %s" % id)
		return 0.0
	line_started.emit(line)
	var stream := audio_of(id)
	var dur := duration_of(id)
	if stream:
		var pb: Dictionary = line.get("playback", {})
		var mode: String = pb.get("mode", "live")
		var bus := &"VoiceTape" if mode == "tape" else &"Voice"
		if pb.get("position", "player") == "behind_player" and listener:
			# 녹음기가 아닌 실제 공간(플레이어 뒤쪽)에서 들리는 목소리
			var p3 := AudioStreamPlayer3D.new()
			p3.stream = stream
			p3.bus = bus
			p3.volume_db = pb.get("volume_db", 0.0)
			listener.get_tree().current_scene.add_child(p3)
			p3.global_position = listener.global_position + listener.global_transform.basis.z * 1.6 + Vector3.UP * 1.1
			p3.play()
			p3.finished.connect(p3.queue_free)
		else:
			var p := AudioStreamPlayer.new()
			p.stream = stream
			p.bus = bus
			p.volume_db = pb.get("volume_db", 0.0)
			add_child(p)
			p.play()
			p.finished.connect(p.queue_free)
	get_tree().create_timer(dur).timeout.connect(func(): line_finished.emit(id))
	return dur
