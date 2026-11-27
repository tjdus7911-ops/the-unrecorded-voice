class_name EventDirector
extends Node
## 공포·스토리 이벤트 디렉터 (요구사항 08). 이벤트는 JSON(data/events/*.json)으로만 정의한다 — 코드에 하드코딩 없음.
##
## 트리거 종류: game_start · tutorial_complete · signal(이름, 인자) · look_at(대상, 각도, los, max_dist, fallback) · near(대상, 반경) · time(초) · condition
##   signal 이름 예: door_opened, door_locked_try, recorder_play, recorder_stop, tape_inserted, flashlight_pickup,
##                  flashlight_on, flashlight_off, switch, inspect:<물건>, item:<아이템>, parcel_picked, parcel_placed
## 안정성:
##  - 같은 이벤트 중복 실행 방지 (started/done 집합), repeatable=false 기본
##  - requires(선행 이벤트)가 모두 끝나야 평가
##  - 일시정지 중에는 타이머·평가 정지 (트리 일시정지를 따름)
##  - 저장/불러오기: done 목록을 저장하고, 불러올 때 지속 효과(조명·잠금·시계 등)만 즉시 재적용 (restore)
##  - fallback_after(+fallback_conditions): 플레이어가 예상과 다르게 행동해도 영구히 멈추지 않게 하는 안전장치 (P0 2026-11-27)
## 실제 연출 동작은 story(액션 실행기: do_action / check / point / play_lights)가 담당한다.

signal event_started(id: String)
signal event_finished(id: String)

var story: Node                  ## do_action(a: Dictionary, instant: bool), check(cond: String) -> bool, point(name) -> Vector3
var player: PlayerController
var events: Array = []
var by_id := {}
var started := {}
var done := {}
var log: Array[String] = []
var _pending_signals: Array = []     ## [name, arg]
var _armed_at := {}                  ## id → requires 충족 시각 (fallback 계산)
var _clock := 0.0
var _tut := {"moved": 0.0, "look": 0.0, "interactions": 0}
var _last_pos := Vector3.ZERO
var _last_yaw := 0.0
var active := false
var _warned := {}
var last_signal := ""
var last_fired := ""
var presences := {}                  ## 캐릭터 id → GhostPresence (연출용은 can_attack=false)

func load_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("EventDirector: missing " + path)
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	# 여러 파일을 이어서 불러올 수 있다 (prologue → tape01 …). 같은 id는 뒤 파일이 대체
	for e in d.get("events", []):
		if by_id.has(e["id"]):
			events.erase(by_id[e["id"]])
		events.append(e)
		by_id[e["id"]] = e

func start_new() -> void:
	active = true
	_last_pos = player.global_position
	_last_yaw = float(player.get("_yaw"))
	_log("start (new game)")

## 저장된 진행으로 복원: 완료한 이벤트의 지속 효과만 즉시 적용 (음성·힌트·연출은 생략)
func restore(done_ids: Array) -> void:
	active = true
	_last_pos = player.global_position
	_last_yaw = float(player.get("_yaw"))
	for e in events:
		if e["id"] in done_ids:
			done[e["id"]] = true
			started[e["id"]] = true
			_apply_lights(e)
			for a in e.get("actions", []):
				story.do_action(a, true)
	_log("restore: %s" % [done_ids])

func notify(sig: String, arg := "") -> void:
	if not active:
		return
	last_signal = "%s %s" % [sig, arg]
	_pending_signals.append([sig, arg])
	if sig.begins_with("interact"):
		_tut.interactions += 1
	_log("signal %s %s" % [sig, arg])

func is_done(id: String) -> bool:
	return done.has(id)

func _process(delta: float) -> void:
	if not active or story == null:
		return
	_clock += delta
	# 튜토리얼 측정 (이동 거리·둘러본 각도)
	var p := player.global_position
	_tut.moved += Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_last_pos = p
	var yaw := float(player.get("_yaw"))
	_tut.look += absf(rad_to_deg(wrapf(yaw - _last_yaw, -PI, PI)))
	_last_yaw = yaw
	for e in events:
		var id: String = e["id"]
		if started.has(id) and not e.get("repeatable", false):
			continue
		if not _requires_met(e):
			continue
		# 필요 없어진 안전장치 이벤트는 건너뛴다 (예: 플레이어가 직접 녹음기를 멈췄으면 자동 정지는 필요 없음)
		var skip := false
		for sid in e.get("skip_if_started", []):
			skip = skip or started.has(sid)
		if skip:
			started[id] = true
			done[id] = true
			_log("SKIP " + id)
			continue
		if not _armed_at.has(id):
			_armed_at[id] = _clock
		if _triggered(e):
			_fire(e)
		elif _clock - float(_armed_at[id]) > 90.0 and not _warned.has(id):
			_warned[id] = true
			_log("WARN 90초 넘게 대기: %s" % id)
	_pending_signals.clear()

func _requires_met(e: Dictionary) -> bool:
	for r in e.get("requires", []):
		if not done.has(r):
			return false
	return true

func _conds(e: Dictionary) -> bool:
	for c in e["trigger"].get("conditions", []):
		if not story.check(c):
			return false
	return true

func _fallback_conds(tr: Dictionary) -> bool:
	for c in tr.get("fallback_conditions", []):
		if not story.check(c):
			return false
	return true

## 디버그·진행 점검용: 선행 조건을 만족해 대기 중인 이벤트와, 아직 충족되지 않은 조건 목록
func pending() -> Array:
	var out: Array = []
	for e in events:
		var id: String = e["id"]
		if started.has(id):
			continue
		var miss: Array = []
		for r in e.get("requires", []):
			if not done.has(r):
				miss.append("선행:" + r)
		if not miss.is_empty():
			continue
		var tr: Dictionary = e["trigger"]
		var what := String(tr.get("type", ""))
		match what:
			"signal":
				miss.append("신호 대기: %s%s" % [tr.get("name", ""), (" (" + str(tr["arg"]) + ")") if tr.has("arg") else ""])
			"look_at":
				miss.append("바라보기: " + String(tr.get("target", "")) + (" (가림 없이)" if tr.get("los", false) else ""))
			"near":
				miss.append("다가가기: %s %.1fm" % [tr.get("target", ""), float(tr.get("radius", 2.0))])
			"condition":
				if not story.check(String(tr.get("cond", ""))):
					miss.append("조건: " + String(tr.get("cond", "")))
			"time":
				miss.append("시간: %.1f/%.1fs" % [_clock - float(_armed_at.get(id, _clock)), float(tr.get("secs", 0.0))])
			"tutorial_complete":
				miss.append("튜토리얼: 이동 %.1f/%sm 시선 %d/%s°" % [_tut.moved, tr.get("moved_m", 3.0), int(_tut.look), tr.get("looked_deg", 90)])
		for c in tr.get("conditions", []):
			if not story.check(c):
				miss.append("조건: " + String(c))
		if tr.has("fallback_after"):
			miss.append("안전장치 %.0fs 뒤" % (float(tr["fallback_after"]) - (_clock - float(_armed_at.get(id, _clock)))))
		out.append({"id": id, "waiting_s": _clock - float(_armed_at.get(id, _clock)), "missing": miss})
	return out

func _triggered(e: Dictionary) -> bool:
	var tr: Dictionary = e["trigger"]
	var since: float = _clock - float(_armed_at.get(e["id"], _clock))
	match tr.get("type", ""):
		"game_start":
			return true
		"tutorial_complete":
			# fallback_after: 조작을 다 하지 않아도 이 시간이 지나면 진행 (튜토리얼 대기로 막히지 않게 — 요구사항 17 §11)
			var tut_ok: bool = _tut.moved >= float(tr.get("moved_m", 3.0)) and _tut.look >= float(tr.get("looked_deg", 90.0)) \
					and _tut.interactions >= int(tr.get("interactions", 1)) and since >= float(tr.get("min_time", 0.0))
			return (tut_ok or (tr.has("fallback_after") and since >= float(tr["fallback_after"]))) and _conds(e)
		"signal":
			for s in _pending_signals:
				if s[0] == tr.get("name", "") and (not tr.has("arg") or str(s[1]) == str(tr["arg"])):
					return _conds(e)
			return tr.has("fallback_after") and since >= float(tr["fallback_after"]) and _fallback_conds(tr)
		"look_at":
			var tgt: Vector3 = story.point(tr.get("target", ""))
			var cam := player.camera
			var dir := (tgt - cam.global_position).normalized()
			var fwd := -cam.global_transform.basis.z
			var near_ok: bool = not tr.has("max_dist") or cam.global_position.distance_to(tgt) <= float(tr["max_dist"])
			# los: 대상이 벽·문에 가려 있지 않아야 '봤다'로 인정
			if rad_to_deg(fwd.angle_to(dir)) <= float(tr.get("max_deg", 40.0)) and near_ok and _conds(e) \
					and (not tr.get("los", false) or story.has_los(tgt)):
				return true
			return tr.has("fallback_after") and since >= float(tr["fallback_after"]) and _fallback_conds(tr)
		"near":
			var tp: Vector3 = story.point(tr.get("target", ""))
			return player.global_position.distance_to(tp) <= float(tr.get("radius", 2.0)) and _conds(e)
		"time":
			return since >= float(tr.get("secs", 0.0)) and _conds(e)
		"condition":
			if story.check(String(tr.get("cond", ""))) and _conds(e):
				return true
			return tr.has("fallback_after") and since >= float(tr["fallback_after"]) and _fallback_conds(tr)
	return false

func _fire(e: Dictionary) -> void:
	var id: String = e["id"]
	started[id] = true
	last_fired = id
	_log("FIRE " + id)
	event_started.emit(id)
	var delay := float(e.get("delay", 0.0))
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
	_apply_lights(e)
	for c in e.get("characters", []):
		var gp := GhostPresence.from_event(c)
		presences[gp.id] = gp
		_log("presence %s = %s (attack=%s)" % [gp.id, GhostPresence.State.keys()[gp.state], gp.can_attack])
	if e.has("breathing"):
		story.do_action({"do": "breathing", "state": e["breathing"]}, false)
	if e.has("lock_interaction"):
		story.do_action({"do": "lock_interaction", "secs": e["lock_interaction"]}, false)
	var last := 0.0
	for a in e.get("actions", []):
		last = maxf(last, float(a.get("t", 0.0)))
		_run_action_at(a)
	var end = e.get("end", "immediate")
	# "immediate" = 마지막 액션이 실행된 뒤 완료 (요구사항 16: 다음 이벤트가 앞 이벤트의 연출 도중에 끼어들지 않게)
	var wait := last
	if typeof(end) == TYPE_DICTIONARY:
		wait = float(end.get("after", last))
	if wait > 0.0:
		await get_tree().create_timer(wait, false).timeout
	done[id] = true
	_log("DONE " + id)
	if str(e.get("checkpoint", "")) != "":
		story.do_action({"do": "checkpoint", "id": e["checkpoint"]}, false)
	event_finished.emit(id)

func _run_action_at(a: Dictionary) -> void:
	var t := float(a.get("t", 0.0))
	if t > 0.0:
		await get_tree().create_timer(t, false).timeout
	story.do_action(a, false)

func _apply_lights(e: Dictionary) -> void:
	if e.has("lights"):
		story.do_action({"do": "lights", "set": e["lights"]}, false)

## 디버그: 이벤트 강제 실행 (선행 조건 무시)
func force(id: String) -> void:
	if by_id.has(id):
		for r in by_id[id].get("requires", []):
			done[r] = true
		_fire(by_id[id])

func _log(s: String) -> void:
	var line := "[%6.1f] %s" % [_clock, s]
	log.append(line)
	if log.size() > 200:
		log.pop_front()
	if OS.is_debug_build():
		print("EVENT ", line)
