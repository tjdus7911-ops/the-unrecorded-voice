class_name ObjectiveDirector
extends Node
## 요구사항 21 — 목표 위치 안내 (모든 챕터 공용).
## data/objectives/*.json 의 목표 목록을 위에서부터 보고, 조건이 맞는 '첫 번째' 목표 하나만 마커로 보여준다.
## 목표는 이벤트 진행 상태(EventDirector)·레벨 상태로만 계산하므로 저장/이어하기 후에도 그대로 복원되고,
## 마커는 읽기만 한다 — 스토리 진행 조건에 전혀 관여하지 않는다.
##
## 목표 항목:
##   id         : 식별자
##   after      : 모두 '완료'된 뒤에만 (이벤트 id 배열)
##   after_started : 모두 '시작'된 뒤에만
##   until      : 하나라도 완료되면 끝 (이벤트 id 배열)
##   until_started : 하나라도 시작되면 끝
##   when       : 조건들 (모두 참일 때) — "!조건" 은 부정. 조건 이름은 레벨의 objective_cond(name)
##   target     : 마커 위치 이름 — 레벨의 objective_point(name) (Vector3, 없으면 INF → 표시 안 함)
##   stuck_secs : '막힐 때만 표시' 설정에서 이 목표가 이만큼 계속되면 표시 (기본 45초)

const DEFAULT_STUCK := 45.0

var events: EventDirector
var lvl: Node                       ## objective_point(name) / objective_cond(name) / objective_hidden() 를 가진 레벨
var marker: ObjectiveMarker
var objectives: Array = []
var active_id := ""
var active_target := ""
var _active_since := 0.0
var _t := 0.0
var history: Array = []                 ## [게임 시간, 목표 id] — 바뀔 때마다 (검수용)
var _clock := 0.0

func load_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("ObjectiveDirector: missing " + path)
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for o in d.get("objectives", []):
			objectives.append(o)

func _process(delta: float) -> void:
	_clock += delta
	_t -= delta
	if _t <= 0.0:
		_t = 0.15
		_update()
	if marker:
		marker.want_visible = _should_show()
		marker.world_point = _point() if active_id != "" else Vector3.INF

func _update() -> void:
	var id := ""
	var tg := ""
	for o in objectives:
		if _is_active(o):
			id = String(o["id"])
			tg = String(o.get("target", ""))
			break
	if id != active_id:
		active_id = id
		active_target = tg
		_active_since = _clock
		history.append([snappedf(_clock, 0.01), id])

func _is_active(o: Dictionary) -> bool:
	if events == null:
		return false
	for e in o.get("after", []):
		if not events.is_done(String(e)):
			return false
	for e in o.get("after_started", []):
		if not events.started.has(String(e)):
			return false
	for e in o.get("until", []):
		if events.is_done(String(e)):
			return false
	for e in o.get("until_started", []):
		if events.started.has(String(e)):
			return false
	for c in o.get("when", []):
		var cs := String(c)
		var neg := cs.begins_with("!")
		var v: bool = lvl.objective_cond(cs.trim_prefix("!"))
		if v == neg:
			return false
	return true

func _point() -> Vector3:
	if active_target == "":
		return Vector3.INF
	return lvl.objective_point(active_target)

func _stuck_secs() -> float:
	for o in objectives:
		if String(o["id"]) == active_id:
			return float(o.get("stuck_secs", DEFAULT_STUCK))
	return DEFAULT_STUCK

func _should_show() -> bool:
	if active_id == "":
		return false
	match GameSettings.objective_marker:
		2:
			return false
		1:
			if _clock - _active_since < _stuck_secs():
				return false
	return not lvl.objective_hidden()

## 검수용: 지금 활성 목표의 마커 위치
func current_point() -> Vector3:
	return _point() if active_id != "" else Vector3.INF
