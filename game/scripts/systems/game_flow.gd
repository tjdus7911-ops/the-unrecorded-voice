extends Node
## 게임 진행 상태·마우스 입력 상태의 단일 관리자 (autoload: GameFlow)
##
## 마우스 캡처는 이 노드만 바꾼다. (다른 스크립트가 Input.mouse_mode를 직접 바꾸지 않음)
##  - PLAYING / INSPECT : 커서 숨김 + 화면 중앙 고정(CAPTURED)
##  - TITLE / PAUSED / CUTSCENE_UI : 커서 보임
## 창이 포커스를 잃으면(Alt+Tab 등) 플레이 중이면 자동 일시정지 → 돌아와 '계속하기'를 누르면 다시 캡처.
## 캡처가 풀린 채 플레이 중인데 화면을 클릭하면 다시 캡처한다 (Windows에서 시작 직후 포커스가 늦게 오는 경우 대비).

signal state_changed(new_state: int, old_state: int)
signal pause_requested
signal resume_requested

enum State { BOOT, TITLE, PLAYING, INSPECT, PAUSED, LOADING }

var state: int = State.BOOT
var _before_pause: int = State.PLAYING
var _focused := true
## 자동 테스트·벤치마크용: 타이틀을 건너뛰고 바로 플레이
var skip_title := false
var auto_pause_on_focus_loss := true   ## 자동 캡처·녹화 도구는 끈다 (가상 X 서버에서 포커스 이벤트가 오지 않음)
## 레벨 시작 방식: "title"(타이틀 화면) / "new"(새 게임) / "continue"(저장 불러오기)
var start_mode := "title"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	skip_title = args.has("--no-title") or args.has("--benchmark") or DisplayServer.get_name() == "headless"

func set_state(s: int) -> void:
	if s == state:
		_apply_mouse()
		return
	var old := state
	state = s
	if s == State.PAUSED:
		_pause_sounds(true)           # 트리를 멈추기 전에 (멈춘 뒤엔 재생 상태가 보이지 않는다)
	get_tree().paused = (s == State.PAUSED)
	if s != State.PAUSED and old == State.PAUSED:
		_pause_sounds(false)
	_apply_mouse()
	state_changed.emit(s, old)

## 요구사항 20: 일시정지 동안 게임 소리를 확실히 멈춘다 (UI 소리 제외) — 재개하면 멈췄던 것만 이어서 재생
var _paused_players: Array = []
func _pause_sounds(on: bool) -> void:
	if on:
		_paused_players.clear()
		var root := get_tree().root
		for c in root.find_children("*", "AudioStreamPlayer", true, false) + root.find_children("*", "AudioStreamPlayer3D", true, false):
			if (c.playing or c.has_stream_playback()) and not c.stream_paused and c.bus != &"UI" and c.process_mode != Node.PROCESS_MODE_ALWAYS:
				c.stream_paused = true
				_paused_players.append(c)
	else:
		for c in _paused_players:
			if is_instance_valid(c):
				c.stream_paused = false
		_paused_players.clear()

func is_playing() -> bool:
	return state == State.PLAYING

## 마우스 시점 조작이 가능한 상태인가
func wants_look() -> bool:
	return state == State.PLAYING and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless")

func _apply_mouse() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var capture := (state == State.PLAYING or state == State.INSPECT) and _focused
	var want := Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want

func pause() -> void:
	if state != State.PLAYING and state != State.INSPECT:
		return
	_before_pause = state
	set_state(State.PAUSED)
	pause_requested.emit()

func resume() -> void:
	if state != State.PAUSED:
		return
	set_state(_before_pause)
	resume_requested.emit()
	# Windows: 메뉴 버튼 클릭 직후 같은 프레임에 캡처하면 무시되는 경우가 있어 한 번 더
	_apply_mouse.call_deferred()

## 레벨을 다시 불러와 지정한 방식으로 시작 (새 게임 / 이어하기 / 메인 메뉴)
func restart_level(mode: String) -> void:
	start_mode = mode
	get_tree().paused = false
	state = State.LOADING
	_apply_mouse()
	get_tree().reload_current_scene.call_deferred()

func quit_game() -> void:
	GameSettings.save_settings()
	get_tree().paused = false
	get_tree().quit()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			if (state == State.PLAYING or state == State.INSPECT) and auto_pause_on_focus_loss:
				pause()
			else:
				_apply_mouse()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			_apply_mouse()
		NOTIFICATION_WM_CLOSE_REQUEST:
			GameSettings.save_settings()

func _input(event: InputEvent) -> void:
	# 플레이 중인데 캡처가 풀려 있으면 (시작 직후 포커스 지연 등) 클릭으로 복구
	if event is InputEventMouseButton and event.pressed and (state == State.PLAYING or state == State.INSPECT) \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_focused = true
		_apply_mouse()
		get_viewport().set_input_as_handled()
