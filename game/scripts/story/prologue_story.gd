class_name PrologueStory
extends Node
## 프롤로그 연출 실행기: EventDirector가 JSON 이벤트의 액션을 여기로 보낸다.
## do_action(a, instant): instant=true(불러오기 복원)이면 지속 상태만 바꾸고 소리·자막·연출은 생략한다.

var lvl: Node3D            ## lvl_phase01
var director: EventDirector
var _behind := Vector3.ZERO
var _rain_players: Array = []
var _gap: MeshInstance3D
var _gap_mat: ShaderMaterial
var _gap_light: SpotLight3D
var _guide: OmniLight3D
var _fade: ColorRect
var _card: Control
var _fade_layer: CanvasLayer
var tried_door := false
var clock_stopped := false
var rain_on := true
var door_locked := false
var monitor_noise := false

func _ready() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 30
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)

func point(name: String) -> Vector3:
	match name:
		"player":
			return lvl.player.camera.global_position
		"door_outside":
			return lvl.b2g(Vector3(0.95, -0.4, 1.3))
		"door_inside":
			return lvl.door_hinge.global_position + lvl.door_hinge.global_transform.basis * Vector3(0.45, 1.0, 0.0) + Vector3(0, 0, 0) \
					+ (lvl.b2g(Vector3(0.95, 0.6, 1.0)) - lvl.b2g(Vector3(0.95, -0.4, 1.0))).normalized() * 0.6 if lvl.door_hinge else Vector3.ZERO
		"ceiling":
			return lvl.fx["StudioCeiling"].global_position
		"recorder":
			return lvl.recorder.global_position if lvl.recorder else Vector3.ZERO
		"behind_voice":
			return _behind
		"corridor_end":
			return lvl.b2g(Vector3(12.3, -1.1, 1.1))
		"soeun":
			return lvl.soeun_node.global_position + Vector3(0, 0.9, 0) if lvl.soeun_node else Vector3.ZERO
		"room_dark_corner":
			var best := Vector3.ZERO
			var bd := -1.0
			for c in [Vector3(0.4, 4.5, 1.0), Vector3(5.6, 4.5, 1.0), Vector3(5.6, 0.5, 1.0), Vector3(0.4, 2.5, 1.0)]:
				var g: Vector3 = lvl.b2g(c)
				var d := g.distance_to(lvl.player.global_position)
				if d > bd:
					bd = d
					best = g
			return best
		"apt_light", "apt_spawn":
			return lvl.apt.point(name) if lvl.apt else Vector3.ZERO
	return Vector3.ZERO

func check(cond: String) -> bool:
	match cond:
		"player_in_studio":
			return lvl.in_studio(lvl.player.global_position)
		"door_closed":
			return not lvl.door_open
		"has_flashlight":
			return Inventory.has_flashlight
		"not_tried_door":
			return not tried_door
		"recorder_stopped_after_tape":
			return lvl.recorder_state == "loaded" and lvl.director.is_done("EV03_tape_play") and not lvl.door_ajar
	return true

func do_action(a: Dictionary, instant: bool) -> void:
	var p: PlayerController = lvl.player
	match String(a.get("do", "")):
		"checkpoint":
			lvl.checkpoint(a["id"])
		"hint":
			if not instant:
				lvl.hud.show_toast(a["text"], float(a.get("secs", 3.0)))
		"hint_if":
			if not instant and check(a.get("cond", "")):
				lvl.hud.show_toast(a["text"], float(a.get("secs", 3.0)))
		"spawn":
			if a.get("what", "") == "parcel_at_door":
				lvl.show_parcel_at_door()
		"sound_at":
			if not instant:
				Sounds.play_at(a["id"], point(a.get("at", "player")), &"SFX", float(a.get("db", 0.0)), null, 0.0, a.get("caption", ""))
		"voice":
			if not instant:
				var at := String(a.get("at", "player"))
				if at == "recorder" and lvl.recorder:
					lvl._play_line_at(a["line"], lvl.recorder)
				else:
					lvl.play_line_world(a["line"], point(at), at == "player")
		"voice_behind":
			if not instant:
				# 플레이어 등 뒤 (방 안쪽으로 제한 — 벽 너머·코앞에 생기지 않게)
				var cam := p.camera
				var back := cam.global_transform.basis.z
				back.y = 0
				back = back.normalized()
				var pos := cam.global_position + back * float(a.get("distance", 2.2))
				_behind = lvl.clamp_to_studio(pos)
				lvl.play_line_world(a["line"], _behind, false, "VoiceRoom")
		"tape_audio":
			if not instant and lvl.recorder:
				lvl.play_tape_sound(a["id"], float(a.get("db", -6.0)))
		"breathing":
			if not instant:
				p.breathing.force_state(StringName(a["state"]))
		"breathing_oneshot":
			if not instant:
				p.breathing.play_oneshot(StringName(a["kind"]))
		"heartbeat":
			if not instant:
				p.danger = float(a["level"])
		"tremble":
			if not instant:
				p.flashlight.set_tremble(float(a["amount"]))
		"lock_interaction":
			if not instant:
				p.lock_interaction(float(a["secs"]))
		"lights":
			for k in a["set"]:
				lvl.set_light(k, a["set"][k], instant)
		"clock_stop":
			clock_stopped = true
			lvl.clock_running = false
		"rain":
			rain_on = bool(a.get("on", true))
			lvl.set_rain(rain_on, 0.0 if instant else float(a.get("fade", 1.5)))
		"monitor_noise":
			monitor_noise = bool(a.get("on", true))
			lvl.set_monitor_noise(monitor_noise)
		"monitor_off":
			lvl.set_monitor_off()
		"pc_fan":
			lvl.set_pc_fan(bool(a.get("on", true)))
		"door_lock":
			door_locked = bool(a.get("locked", true))
			if door_locked and lvl.door_open:
				lvl.slam_door(instant)          # 열려 있던 문이 저절로 쾅 닫힌 뒤 잠긴다
			lvl.door_locked = door_locked
			if not instant and door_locked:
				Sounds.play_at("sfx_door_lock", point("door_inside"), &"SFX", -2.0, null, 0.0, "문이 잠기는 소리")
		"guide_light":
			_set_guide(bool(a.get("on", true)) and not instant)
		"door_gap_light":
			if not instant:
				_set_gap(bool(a.get("on", true)))
		"shadow_pass":
			if not instant:
				_shadow_pass()
		"child_steps":
			if not instant:
				_child_steps()
		"flashlight_glitch":
			if not instant:
				_flashlight_glitch(float(a.get("secs", 0.8)))
		"fade":
			if not instant:
				var tw := create_tween()
				tw.tween_property(_fade, "color:a", float(a.get("to", 1.0)), float(a.get("secs", 0.5)))
		"teleport":
			if not instant:
				lvl.enter_apartment()
		"soeun_far":
			if not instant and lvl.apt:
				lvl.apt.show_soeun(float(a.get("secs", 1.2)))
		"intro_seated":
			if not instant:
				lvl.intro_seated()
		"intro_headphones":
			if not instant:
				lvl.intro_headphones()
		"intro_stand_up":
			if not instant:
				lvl.intro_stand_up()
		"figure_far":
			if not instant:
				lvl.show_monster_at("corridor_end", float(a.get("secs", 1.2)))
		"corridor_light_off":
			lvl.set_light("CorLight%d" % int(a.get("index", 5)), "story_off", instant)
		"tape_cut":
			if not instant:
				lvl.tape_cut()
		"door_creep":
			if not instant:
				lvl.door_creep(float(a.get("deg", 12.0)), float(a.get("secs", 4.0)))
		"presence_in_gap":
			if not instant:
				lvl.presence_in_gap(bool(a.get("on", true)))
		"await_look_door":
			if not instant:
				_await_look_door(float(a.get("radius", 2.6)), float(a.get("max_deg", 28.0)), float(a.get("fallback_after", 20.0)))
		"flinch":
			if not instant:
				lvl.player.arms.flinch()
				lvl.player.camera_kick(0.6)
		"flashlight_shake":
			if not instant:
				lvl.player.arms.flinch(1.6, float(a.get("secs", 0.5)))
		"recorder_self_play":
			lvl.recorder_self(true, instant)
		"recorder_self_stop":
			lvl.recorder_self(false, instant)
		"offsight":
			lvl.offsight_change(String(a.get("what", "")), instant)
		"child_steps_room":
			if not instant:
				_child_steps_room()
		"show_under_desk_tape":
			lvl.show_under_desk_tape()
		"soeun_peek":
			if not instant:
				lvl.soeun_peek(float(a.get("secs", 0.8)))
		"monster_breath_door":
			if not instant:
				lvl.monster_breath_door(bool(a.get("on", true)))
		"door_handle_rattle":
			if not instant:
				lvl.door_handle_rattle()
		"door_bang":
			if not instant:
				lvl.door_bang(float(a.get("strength", 1.0)))
		"silence":
			if not instant:
				lvl.sudden_silence(2.8)
		"to_title":
			if not instant and not lvl.get_meta("test_no_title", false):
				GameFlow.restart_level("title")
		"title_card":
			if not instant:
				_title_card(a.get("title", ""), a.get("subtitle", ""), float(a.get("secs", 4.0)))

## EVENT 04: 문틈의 존재를 플레이어가 직접 발견해 다가가면 문이 쾅 닫힌다 (카메라 강제 회전 없음)
func _await_look_door(radius: float, max_deg: float, fallback: float) -> void:
	var el := 0.0
	while el < fallback:
		await get_tree().create_timer(0.1, false).timeout
		el += 0.1
		var cam: Camera3D = lvl.player.camera
		var gap: Vector3 = lvl.door_gap_point()
		var dir := (gap - cam.global_position).normalized()
		var ang := rad_to_deg((-cam.global_transform.basis.z).angle_to(dir))
		if ang < max_deg and cam.global_position.distance_to(gap) < radius + 1.5:
			if cam.global_position.distance_to(gap) < radius:
				break
	lvl.door_slam_presence()
	await get_tree().create_timer(0.5, false).timeout
	lvl.play_line_world("PRO_E04_001", Vector3.ZERO, true)
	lvl.player.danger = maxf(lvl.player.danger, 0.5)

## EVENT 06: 정전 속 어린아이 발소리 — 플레이어 시야 밖(뒤·옆)에서 방을 가로지른다
func _child_steps_room() -> void:
	var p: PlayerController = lvl.player
	var back := p.camera.global_transform.basis.z
	back.y = 0
	back = back.normalized()
	var side := back.cross(Vector3.UP)
	var a: Vector3 = lvl.clamp_to_studio(p.global_position + back * 2.0 - side * 1.6)
	var b: Vector3 = lvl.clamp_to_studio(p.global_position + back * 2.0 + side * 1.6)
	for i in 7:
		var k := i / 6.0
		Sounds.play_at("step_wood", a.lerp(b, k) + Vector3(0, 0.05, 0), &"SFX", -13.0, null, 0.03, "작은 발소리" if i == 0 else "", 2.0)
		await get_tree().create_timer(0.26, false).timeout

## 정전 뒤 서랍 쪽을 찾게 하는 희미한 빛: 창밖 번개/네온 대신 — 책상 아래 멀티탭 대기 LED처럼 작은 붉은 점 + 아주 약한 창빛
func _set_guide(on: bool) -> void:
	if _guide == null:
		_guide = OmniLight3D.new()
		_guide.light_color = Color(0.75, 0.82, 1.0)
		_guide.light_energy = 0.0
		_guide.omni_range = 1.6
		_guide.shadow_enabled = false
		lvl.add_child(_guide)
		var dr := lvl.find_child("stu_desk_drawer_0", true, false) as Node3D
		_guide.global_position = (dr.global_position if dr else lvl.b2g(Vector3(1.6, 4.5, 0.7))) + Vector3(0, 0.45, 0.35)
	var tw := create_tween()
	tw.tween_property(_guide, "light_energy", 0.35 if on else 0.0, 2.0)

func _ensure_gap() -> void:
	if _gap or lvl.door_hinge == null:
		return
	# 문 아래 틈으로 새어 드는 복도 형광등 빛 (그림자가 지나가면 가려진다)
	_gap = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.86, 0.018)
	_gap.mesh = qm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float on = 0.0;
uniform float shadow_x = -2.0;
void fragment() {
	float occl = 1.0 - 0.96 * exp(-pow((UV.x - shadow_x) / 0.09, 2.0));
	ALBEDO = vec3(0.95, 0.97, 1.0) * 1.6 * on * occl * (0.7 + 0.3 * UV.y);
}"""
	_gap_mat = ShaderMaterial.new()
	_gap_mat.shader = sh
	_gap.material_override = _gap_mat
	lvl.door_hinge.add_child(_gap)
	_gap.position = Vector3(0.445, 0.009, 0.03)
	_gap_light = SpotLight3D.new()
	_gap_light.light_color = Color(0.85, 0.92, 1.0)
	_gap_light.light_energy = 0.0
	_gap_light.spot_range = 2.2
	_gap_light.spot_angle = 70
	_gap_light.shadow_enabled = false
	lvl.door_hinge.add_child(_gap_light)
	_gap_light.position = Vector3(0.445, 0.02, -0.05)
	_gap_light.rotation_degrees = Vector3(-80, 180, 0)

func _set_gap(on: bool) -> void:
	_ensure_gap()
	if _gap == null:
		return
	var tw := create_tween().set_parallel()
	tw.tween_method(func(v): _gap_mat.set_shader_parameter("on", v), 0.0 if on else 1.0, 1.0 if on else 0.0, 0.6)
	tw.tween_property(_gap_light, "light_energy", 0.6 if on else 0.0, 0.6)

## 문 너머로 어린아이의 그림자가 지나간다 (문틈 빛이 발 모양으로 가려짐)
func _shadow_pass() -> void:
	_ensure_gap()
	if _gap == null:
		return
	var tw := create_tween()
	tw.tween_method(func(x): _gap_mat.set_shader_parameter("shadow_x", x), -0.3, 1.3, 1.5)
	tw.parallel().tween_property(_gap_light, "light_energy", 0.15, 0.6)
	tw.tween_property(_gap_light, "light_energy", 0.6, 0.5)

func _child_steps() -> void:
	var a := point("door_outside") + Vector3(-1.2, -0.9, 0)
	var b := point("door_outside") + Vector3(1.4, -0.9, 0)
	for i in 6:
		var k := i / 5.0
		Sounds.play_at("step_tile", a.lerp(b, k), &"SFX", -15.0, null, 0.02, "작은 발소리" if i == 0 else "", 2.0)
		var pl: AudioStreamPlayer3D = null
		await get_tree().create_timer(0.27, false).timeout

func _flashlight_glitch(secs: float) -> void:
	var fl: Flashlight = lvl.player.flashlight
	var was := fl.is_on
	if not was:
		return
	var t := 0.0
	while t < secs:
		fl.spot.visible = randf() < 0.35
		var d := randf_range(0.03, 0.12)
		await get_tree().create_timer(d, false).timeout
		t += d
	fl.spot.visible = false
	await get_tree().create_timer(1.2, false).timeout
	fl.spot.visible = fl.is_on

func _title_card(title: String, sub: String, secs: float) -> void:
	_card = VBoxContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.offset_left = -400
	_card.offset_right = 400
	_card.offset_top = -70
	_card.offset_bottom = 70
	(_card as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UIKit.label(title, 22, UIKit.DIM)
	var fv := FontVariation.new()
	fv.base_font = UIKit.font(false)
	fv.spacing_glyph = 9
	t.add_theme_font_override("font", fv)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := UIKit.label(tr(sub), 46, UIKit.TEXT, true)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(t)
	_card.add_child(s)
	_card.modulate.a = 0.0
	_fade_layer.add_child(_card)
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 1.2)
	tw.tween_interval(secs)
	tw.tween_property(_card, "modulate:a", 0.0, 1.5)
	tw.tween_callback(func():
		_card.queue_free()
		lvl.hud.show_toast("PHASE 01 테스트 범위는 여기까지입니다. (TAPE 01 본편은 다음 단계에서 제작)", 8.0))
