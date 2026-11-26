extends Node
## 단서 기록 (autoload: ClueBook) — 필수/숨겨진 단서, 챕터별 회수 현황, 엔딩 판정의 기반.
## 저장 데이터(SaveGame state.clues)와 별도로 user://clues.cfg 에도 누적 기록 → 챕터 재플레이 시 회수 현황 유지.

signal clue_found(id: StringName)

const DATA := "res://data/progress/clues.json"
const META := "user://clues.cfg"
var defs := {}
var found := {}          ## 현재 진행(세이브)에서 찾은 단서
var ever := {}           ## 모든 플레이에서 한 번이라도 찾은 단서 (재플레이·수집 현황)

func _ready() -> void:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f:
		for c in JSON.parse_string(f.get_as_text()).get("clues", []):
			defs[StringName(c["id"])] = c
	var cfg := ConfigFile.new()
	if cfg.load(META) == OK:
		for k in cfg.get_section_keys("ever") if cfg.has_section("ever") else []:
			ever[StringName(k)] = true

func add(id: StringName) -> void:
	if found.has(id):
		return
	found[id] = true
	ever[id] = true
	var cfg := ConfigFile.new()
	cfg.load(META)
	cfg.set_value("ever", String(id), true)
	cfg.save(META)
	clue_found.emit(id)

func restore(ids: Array) -> void:
	found.clear()
	for i in ids:
		found[StringName(i)] = true

func reset() -> void:
	found.clear()

func count(chapter: String, kind: String) -> Vector2i:
	var have := 0
	var total := 0
	for id in defs:
		var c: Dictionary = defs[id]
		if c.get("chapter", "") == chapter and c.get("kind", "") == kind:
			total += 1
			if found.has(id):
				have += 1
	return Vector2i(have, total)

## 일반 엔딩은 필수 단서만으로 도달 가능 (숨겨진 단서는 선택)
func normal_ending_ok() -> bool:
	for id in defs:
		if defs[id].get("kind", "") == "required" and not found.has(id):
			return false
	return true
