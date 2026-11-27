class_name StoryDebugOverlay
extends CanvasLayer
## 개발 빌드 전용 이벤트 디버그 표시 (P0 2026-11-27 §3) — F9로 켜고 끈다.
## 배포(릴리스) 빌드에서는 만들어지지 않는다: lvl_phase01이 OS.is_debug_build()일 때만 추가.
## 표시: 챕터 · 현재(마지막 실행) 이벤트 · 완료 이벤트 · 대기 중인 이벤트와 충족되지 않은 조건 · 문 잠김 · 녹음기 · 손전등 · 팝업 · 일시정지 · 오류 로그

var lvl: Node3D
var _label: RichTextLabel
var _t := 0.0

func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.72)
	sb.set_content_margin_all(10)
	bg.add_theme_stylebox_override("panel", sb)
	bg.position = Vector2(16, 16)
	bg.custom_minimum_size = Vector2(640, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(620, 0)
	_label.add_theme_font_size_override("normal_font_size", 14)
	_label.add_theme_font_override("normal_font", UIKit.font(false))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_label)
	visible = OS.get_cmdline_user_args().has("--story-debug")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F9:
		visible = not visible

func _process(delta: float) -> void:
	if not visible or lvl == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	_label.text = text()

func text() -> String:
	var d: EventDirector = lvl.director
	var L: PackedStringArray = []
	L.append("[b]STORY DEBUG[/b] (F9)   챕터: %s" % ("TAPE 01 (1998)" if lvl.in_apartment else ("작업실 복귀 후" if lvl.tapes_done.size() > 0 else "프롤로그")))
	if d == null:
		L.append("이벤트 디렉터 없음 (스토리 꺼짐)")
		return "\n".join(L)
	L.append("현재(마지막 실행) 이벤트: [color=#ffd060]%s[/color]   마지막 신호: %s" % [d.last_fired, d.last_signal])
	L.append("완료 %d / 전체 %d: %s" % [d.done.size(), d.events.size(), ", ".join(PackedStringArray(d.done.keys().slice(-6)))])
	var running: PackedStringArray = []
	for id in d.started:
		if not d.done.has(id):
			running.append(id)
	if not running.is_empty():
		L.append("실행 중: " + ", ".join(running))
	L.append("[b]다음 이벤트 대기 / 충족되지 않은 조건[/b]")
	for p in d.pending().slice(0, 4):
		L.append("  · %s  (%.0fs)  %s" % [p["id"], p["waiting_s"], " / ".join(PackedStringArray(p["missing"]))])
	var pl: PlayerController = lvl.player
	L.append("문: %s%s   녹음기: %s (테이프 %s)   손전등: %s%s" % [
		"잠김" if lvl.door_locked else "열 수 있음", " · 열림" if lvl.door_open else "",
		lvl.recorder_state, lvl.recorder_tape_no if lvl.recorder_tape_no != "" else "-",
		"획득" if Inventory.has_flashlight else "없음", (" · 켜짐" if pl.flashlight.is_on else "") + (" · 차단" if pl.flashlight.blocked else "")])
	L.append("팝업: %d   상태: %s   일시정지: %s   조명: %s   위험도 %.2f / 불안 %.2f" % [
		ConfirmDialogUI.open_count, GameFlow.State.keys()[GameFlow.state], str(get_tree().paused), lvl.lighting, pl.danger, pl.unease])
	var errs: PackedStringArray = []
	for line in d.log:
		if line.contains("WARN") or line.contains("ERR"):
			errs.append(line)
	L.append("오류 로그: " + ("없음" if errs.is_empty() else "\n  " + "\n  ".join(errs.slice(-4))))
	return "\n".join(L)
