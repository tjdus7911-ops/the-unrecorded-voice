extends Node
## 사용자 설정 (autoload: GameSettings)
## 설정 메뉴의 모든 항목을 한곳에서 관리하고 user://settings.cfg 에 저장한다.

signal changed(key: StringName)

const SAVE_PATH := "user://settings.cfg"

## 오디오 버스별 음량 (0.0 ~ 1.0 선형)
var volumes := {
	&"Master": 1.0,
	&"Voice": 1.0,
	&"Ambience": 1.0,
	&"SFX": 1.0,
	&"Music": 1.0,
}
var mouse_sensitivity := 0.0022   ## rad / px
var camera_shake := 1.0           ## 카메라 흔들림 강도 0~1 (0이면 완전히 끔)
var breathing_intensity := 1.0    ## 호흡·심장 박동 효과음 강도 0~1
var subtitles := true
var sound_captions := false       ## 주요 효과음 방향·설명 자막 (접근성)
var reduce_flashes := false       ## 섬광 효과 완화
var dynamic_range_compression := false  ## 음량 차이 완화
var brightness := 1.0
## 그래픽 품질: 0 낮음 / 1 보통 / 2 높음(기본). 높음 = 실시간 GI(SDFGI)·SSIL·SSR
var graphics_quality := 2

func _ready() -> void:
	load_settings()
	apply_all()

func set_value(key: StringName, value: Variant) -> void:
	if key in volumes:
		volumes[key] = clampf(value, 0.0, 1.0)
	else:
		set(key, value)
	apply_all()
	changed.emit(key)

func apply_all() -> void:
	for bus_name in volumes:
		_set_bus_linear(bus_name, volumes[bus_name])
	# 귀신 소리는 효과음 슬라이더를 따른다
	_set_bus_linear(&"Ghost", volumes[&"SFX"])
	# 호흡·심장 박동 강도
	_set_bus_linear(&"Breathing", breathing_intensity, -4.0)
	_set_bus_linear(&"Heartbeat", breathing_intensity, -6.0)

func _set_bus_linear(bus_name: StringName, linear: float, base_db := 0.0) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, base_db + linear_to_db(maxf(linear, 0.001)))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in volumes:
		cfg.set_value("audio", String(k), volumes[k])
	for k in ["mouse_sensitivity", "camera_shake", "breathing_intensity", "subtitles",
			"sound_captions", "reduce_flashes", "dynamic_range_compression", "brightness", "graphics_quality"]:
		cfg.set_value("game", k, get(k))
	cfg.save(SAVE_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for k in volumes.keys():
		volumes[k] = cfg.get_value("audio", String(k), volumes[k])
	for k in ["mouse_sensitivity", "camera_shake", "breathing_intensity", "subtitles",
			"sound_captions", "reduce_flashes", "dynamic_range_compression", "brightness", "graphics_quality"]:
		set(k, cfg.get_value("game", k, get(k)))

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
