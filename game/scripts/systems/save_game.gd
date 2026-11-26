extends Node
## 자동 저장 · 이어하기 (autoload: SaveGame)
## 체크포인트마다 user://save_01.json 에 기록한다. 레벨이 get_save_state()/apply_save_state()로 상태를 제공·복원.
## 저장 내용: 체크포인트 ID, 플레이어 위치·방향, 인벤토리, 완료한 스토리 이벤트, 조명 상태, 오브젝트 상태.

signal saved(checkpoint: String)

const PATH := "user://save_01.json"
const VERSION := 1
const LABELS := {
	"game_start": "게임 시작",
	"parcel_obtained": "택배 획득",
	"tape1_played": "첫 번째 테이프 재생",
	"flashlight_obtained": "손전등 획득",
	"apt_entered": "1998년 아파트 진입",
}

## 레벨을 다시 불러올 때 적용할 저장 데이터 (이어하기 / 체크포인트에서 다시 시작)
var pending: Dictionary = {}
var _cache: Dictionary = {}

func has_save() -> bool:
	return FileAccess.file_exists(PATH) and not read().is_empty()

func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or int(d.get("version", 0)) != VERSION:
		return {}
	_cache = d
	return d

func write(checkpoint: String, state: Dictionary) -> void:
	var d := {
		"version": VERSION,
		"checkpoint": checkpoint,
		"label": LABELS.get(checkpoint, checkpoint),
		"time": Time.get_unix_time_from_system(),
		"state": state,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: cannot write " + PATH)
		return
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	_cache = d
	saved.emit(checkpoint)

func delete_save() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	_cache = {}

## 일시정지 메뉴 안내용: {"label", "ago"}
func last_info() -> Dictionary:
	var d := _cache if not _cache.is_empty() else read()
	if d.is_empty():
		return {}
	var sec := int(Time.get_unix_time_from_system() - float(d.get("time", 0)))
	var ago := "방금" if sec < 60 else ("%d분 전" % (sec / 60) if sec < 3600 else "%d시간 전" % (sec / 3600))
	return {"label": d.get("label", ""), "ago": ago, "checkpoint": d.get("checkpoint", "")}
