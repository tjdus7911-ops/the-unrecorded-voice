extends Node
## 사용자 설정 (autoload: GameSettings)
## 설정 화면의 모든 항목을 한곳에서 관리하고 user://settings.cfg 에 저장한다 (재실행 후에도 유지).

signal changed(key: StringName)

const SAVE_PATH := "user://settings.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const FPS_LIMITS := [0, 30, 60, 120, 144, 165, 240]   ## 0 = 제한 없음
## 조작키 변경 화면에 보여 줄 동작 (표시 이름)
const REBINDABLE := [
	["move_forward", "앞으로"], ["move_back", "뒤로"], ["move_left", "왼쪽"], ["move_right", "오른쪽"],
	["sprint", "달리기"], ["crouch", "앉기"], ["interact", "상호작용 / 조사"], ["flashlight", "손전등"],
	["hold_breath", "숨 참기"], ["recorder_play", "녹음기 재생 / 정지"],
]

## ---- 사운드 (0.0 ~ 1.0 선형)
var volumes := {
	&"Master": 1.0,
	&"Voice": 1.0,
	&"Ambience": 1.0,
	&"SFX": 1.0,
	&"Music": 1.0,
}
var breathing_intensity := 1.0    ## 호흡·심장 박동 음량 0~1
## ---- 언어 (UI·자막과 음성을 따로 고른다)
const LANGUAGES := [["ko", "한국어"], ["en", "English"], ["ja", "日本語"]]
var text_language := "ko"
var voice_language := "ko"        ## 현재 음성은 한국어만 존재 (다른 언어 음성 파일이 생기면 자동 사용)
## ---- 화면
var window_mode := 0              ## 0 전체 화면 / 1 창 모드 / 2 테두리 없는 창
var resolution := 2               ## RESOLUTIONS 인덱스 (창 모드에서 적용)
var vsync := true
var fps_limit := 0                ## FPS_LIMITS 인덱스
var fov := 68.0                   ## 수직 FOV (요구사항 12: 65~75 화면 비교 후 68)
var brightness := 1.0
var graphics_quality := 2         ## 0 낮음 / 1 보통 / 2 높음 (높음 = SDFGI·SSIL·SSR)
## ---- 조작
var mouse_sensitivity := 0.0022   ## rad / 화면 px
var invert_y := false
var keybinds := {}                ## action → physical keycode (변경한 것만)
## ---- 접근성
var subtitles := true
var subtitle_size := 1            ## 0 작게 / 1 보통 / 2 크게 / 3 아주 크게
var subtitle_bg := false          ## 자막 뒤 반투명 배경 (요구사항 15: 기본은 영화 자막처럼 그림자만)
var sound_captions := false       ## 주요 효과음 자막
var camera_shake := 1.0           ## 카메라 흔들림 강도 0~1
var reduce_flashes := false       ## 조명 깜빡임·섬광 완화
var inspect_text_size := 1        ## 조사 설명 글자 크기 0~3
var crosshair_mode := 0           ## 조준점: 0 항상 작은 점 · 1 상호작용 때만(손 아이콘) · 2 끔 (요구사항 13)
var interaction_hints := false    ## 상호작용 힌트: 켜면 손 아이콘 옆에 물건 이름 + 바라보는 물건 은은한 강조
var objective_hints := true       ## 현재 목표 표시 (요구사항 12 §4)
var dynamic_range_compression := false

const SETTINGS_VERSION := 2
const GAME_KEYS := ["text_language", "voice_language", "window_mode", "resolution", "vsync", "fps_limit", "fov", "brightness", "graphics_quality",
	"mouse_sensitivity", "invert_y", "subtitles", "subtitle_size", "subtitle_bg", "sound_captions",
	"camera_shake", "reduce_flashes", "inspect_text_size", "crosshair_mode", "interaction_hints", "objective_hints", "breathing_intensity", "dynamic_range_compression"]

var _headless := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	_ensure_actions()
	_font_fallbacks()
	load_settings()
	apply_all()
	apply_display()
	apply_language()

## 한국어 서브셋 폰트에 일본어 서브셋을 폴백으로 연결 (가나·한자 표시)
func _font_fallbacks() -> void:
	var jp_path := "res://assets/fonts/NotoSansJP-Regular-subset.otf"
	if not ResourceLoader.exists(jp_path):
		return
	var jp: Font = load(jp_path)
	for p in ["res://assets/fonts/NotoSansKR-Regular-subset.otf", "res://assets/fonts/NotoSansKR-Medium-subset.otf"]:
		if ResourceLoader.exists(p):
			var f: Font = load(p)
			if not f.fallbacks.has(jp):
				var fb := f.fallbacks
				fb.append(jp)
				f.fallbacks = fb

func apply_language() -> void:
	TranslationServer.set_locale(text_language)
	var db := get_node_or_null("/root/DialogueDB")
	if db:
		db.locale = text_language
		db.voice_locale = voice_language

func set_value(key: StringName, value: Variant) -> void:
	if key in volumes:
		volumes[key] = clampf(value, 0.0, 1.0)
	else:
		set(key, value)
	apply_all()
	if String(key) in ["window_mode", "resolution", "vsync", "fps_limit"]:
		apply_display()
	if String(key) in ["text_language", "voice_language"]:
		apply_language()
	save_settings()
	changed.emit(key)

func apply_all() -> void:
	for bus_name in volumes:
		_set_bus_linear(bus_name, volumes[bus_name])
	_set_bus_linear(&"Ghost", volumes[&"SFX"])
	_set_bus_linear(&"Breathing", breathing_intensity, -4.0)
	_set_bus_linear(&"Heartbeat", breathing_intensity, -6.0)

func apply_display() -> void:
	Engine.max_fps = FPS_LIMITS[clampi(fps_limit, 0, FPS_LIMITS.size() - 1)]
	if _headless or OS.get_cmdline_user_args().has("--keep-window"):
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	match window_mode:
		0:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		1, 2:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, window_mode == 2)
			var scr := DisplayServer.window_get_current_screen()
			var ss := DisplayServer.screen_get_size(scr)
			var r: Vector2i = RESOLUTIONS[clampi(resolution, 0, RESOLUTIONS.size() - 1)]
			if window_mode == 2:
				r = ss                     # 테두리 없는 창 = 화면 크기
			r = Vector2i(mini(r.x, ss.x), mini(r.y, ss.y))
			DisplayServer.window_set_size(r)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(scr) + (ss - r) / 2)

func _set_bus_linear(bus_name: StringName, linear: float, base_db := 0.0) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, base_db + linear_to_db(maxf(linear, 0.001)))

## ---------------------------------------------------------------- 조작키
func _ensure_actions() -> void:
	# 녹음기 재생/정지 키 (R)
	if not InputMap.has_action("recorder_play"):
		InputMap.add_action("recorder_play")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_R
		InputMap.action_add_event("recorder_play", e)

func key_for(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code) if e.physical_keycode != 0 else code)
		if e is InputEventMouseButton:
			return tr("마우스 %d") % e.button_index
	return "-"

func rebind(action: String, physical: int) -> void:
	var evs := InputMap.action_get_events(action)
	for e in evs:
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
			break
	var k := InputEventKey.new()
	k.physical_keycode = physical as Key
	InputMap.action_add_event(action, k)
	keybinds[action] = physical
	save_settings()
	changed.emit(&"keybinds")

func reset_keybinds() -> void:
	InputMap.load_from_project_settings()
	_ensure_actions()
	keybinds.clear()
	save_settings()
	changed.emit(&"keybinds")

## ---------------------------------------------------------------- 저장
func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in volumes:
		cfg.set_value("audio", String(k), volumes[k])
	for k in GAME_KEYS:
		cfg.set_value("game", k, get(k))
	for a in keybinds:
		cfg.set_value("keys", a, keybinds[a])
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	cfg.save(SAVE_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for k in volumes.keys():
		volumes[k] = cfg.get_value("audio", String(k), volumes[k])
	for k in GAME_KEYS:
		set(k, cfg.get_value("game", k, get(k)))
	# 설정 버전 2 (요구사항 12·13): 이전 기본값 그대로였던 FOV 70은 새 기본값 68로
	if int(cfg.get_value("meta", "version", 1)) < 2 and is_equal_approx(fov, 70.0):
		fov = 68.0
	if cfg.has_section("keys"):
		for a in cfg.get_section_keys("keys"):
			if InputMap.has_action(a):
				var code: int = cfg.get_value("keys", a)
				for e in InputMap.action_get_events(a):
					if e is InputEventKey:
						InputMap.action_erase_event(a, e)
						break
				var k := InputEventKey.new()
				k.physical_keycode = code as Key
				InputMap.action_add_event(a, k)
				keybinds[a] = code

## 환경(Environment)에 품질 프리셋 적용 — 레벨이 호출
func apply_quality(env: Environment, viewport: Viewport) -> void:
	var q := graphics_quality
	if OS.get_cmdline_user_args().has("--quality-low"):
		q = 0
	elif OS.get_cmdline_user_args().has("--quality-medium"):
		q = 1
	env.sdfgi_enabled = q >= 2
	env.ssil_enabled = q >= 1
	env.ssr_enabled = q >= 2
	env.ssao_enabled = q >= 1
	viewport.positional_shadow_atlas_size = 2048 if q >= 1 else 1024
	RenderingServer.positional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if q >= 2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
