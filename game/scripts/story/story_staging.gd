class_name StoryStaging
extends Node
## 연출 담당: 요구사항 17 §10 소은 등장 → 실제 괴물 추격 (공격·사망 없음)과 요구사항 16 TAPE 01.
## PrologueStory.do_action 이 여기로 위임한다.
## 원칙: 캐릭터는 플레이어가 보고 있는 동안 생기거나 사라지지 않는다 (빛이 꺼진 순간·시야 밖에서만 바뀐다).
## 괴물은 실제 공간을 따라 움직인다: 남쪽 화장실 통로(모퉁이) → 복도로 걸어 나와 → 몸을 돌리고 → 멈췄다가 → 플레이어를 향해 달린다.

var lvl: Node3D
var story: Node

# --- 복도 (Blender 좌표: 복도 x -5~13, y -2.0~-0.2 / 작업실 문 x 0.95 / 기둥 x -1.58~-1.12, y -0.84~-0.2 / 화장실 통로 x -4.6~-3.6, y -2.0~-4.6)
const SOEUN_COR := Vector3(12.15, -1.25, 0.0)      ## 문에서 약 11 m, 복도 끝
const NOISE_PEEK := Vector3(-3.87, -2.28, 0.0)     ## 화장실 통로 안, 모퉁이(동쪽 벽 끝) 바로 뒤
const NOISE_OUT := Vector3(-4.05, -1.2, 0.0)       ## 복도로 걸어 나온 지점
const NOISE_LEAN := 18.0
const CHASE_END_X := 10.2                         ## '지정된 복도 구간' — 여기 닿으면 과거 전환
const CAUGHT_DIST := 1.35
const MAX_CHASE_SECS := 40.0                      ## 움직이지 않아도 영구히 막히지 않게
var soeun_placed := false
var soeun_gone := false
var monster_state := ""          ## "" → peeking → emerging → turning → paused → chasing → closing → gone
var noise: Node3D
var noise_poser: CharacterPoser
var _noise_tape_mat: ShaderMaterial
var _glitch: ColorRect
var fragments := 0               ## TAPE 01 녹음 조각 (0~3)
var chase_audio_on := false
var _chase_t := 0.0
var _gap_want := 5.0
var _speed := 0.0
var _step_t := 0.0
var _glitch_t := 2.0
var caught := false

func _ready() -> void:
	set_process(true)

func b2g(v: Vector3) -> Vector3:
	return lvl.b2g(v)

## Godot → Blender (복도 판정용)
func g2b(p: Vector3) -> Vector3:
	return Vector3(p.x, -p.z, p.y)

func in_corridor(p: Vector3) -> bool:
	var q := g2b(p)
	return q.x > -5.0 and q.x < 13.2 and q.y > -2.05 and q.y < -0.15

func point(name: String) -> Vector3:
	match name:
		"soeun_corridor":
			return b2g(SOEUN_COR) + Vector3(0, 1.0, 0)
		"monster_corner":
			if noise and noise.visible:
				return _noise_head()
			return b2g(Vector3(-3.7, -1.95, 1.75))
		"monster_drop":
			return b2g(Vector3(-4.1, -3.6, 0.2))       # 화장실 통로 안쪽 (양동이 옆)
		"ear":
			var cam: Camera3D = lvl.player.camera
			return cam.global_position + cam.global_transform.basis.x * 0.22 + cam.global_transform.basis.z * 0.05
		"parcel":
			return lvl.parcel.global_position if lvl.parcel else Vector3.ZERO
		"photo":
			return lvl.photo.global_position if lvl.get("photo") else Vector3.ZERO
		"apt_soeun_end_head":
			if lvl.apt and lvl.apt.soeun:
				return lvl.apt.soeun.global_position + Vector3(0, 1.0, 0)
			return Vector3.ZERO
	if lvl.apt and name.begins_with("apt_"):
		return lvl.apt.point(name)
	return Vector3.INF

func check(cond: String) -> Variant:
	var p: Vector3 = lvl.player.global_position
	match cond:
		"door_open":
			return lvl.door_open
		"player_in_corridor":
			return in_corridor(p)
		"soeun_lit":
			return _lit_by_flashlight(b2g(SOEUN_COR) + Vector3(0, 0.75, 0))
		"monster_chasing":
			return monster_state == "chasing"
		"chase_end":
			return monster_state in ["chasing"] and (caught or (in_corridor(p) and g2b(p).x > CHASE_END_X) or _chase_t > MAX_CHASE_SECS)
		"apt_soeun_visible":
			return lvl.apt != null and lvl.apt.soeun != null and lvl.apt.soeun.visible
		"in_apartment":
			return lvl.apt != null and lvl.apt.bounds().has_point(p)
	return null

## 손전등 빛이 그 지점에 실제로 닿는가 (정전된 복도: 비춰야 보인다)
func _lit_by_flashlight(pt: Vector3) -> bool:
	var fl: Flashlight = lvl.player.flashlight
	if fl == null or not fl.is_on or not fl.spot.visible:
		return false
	var sp := fl.spot.global_position
	var to := pt - sp
	if to.length() > fl.spot.spot_range * 0.95:
		return false
	if rad_to_deg((-fl.spot.global_transform.basis.z).angle_to(to.normalized())) > fl.spot.spot_angle * 0.8:
		return false
	return has_los(pt)

# =========================================================== STEP 02 소은 (복도 끝, 등 돌림, 손전등으로 비춰야 보임)
func place_soeun_corridor(instant: bool) -> void:
	lvl._soeun()
	var s: Node3D = lvl.soeun_node
	if s == null or soeun_gone:
		return
	var at := b2g(SOEUN_COR)
	s.global_position = at
	s.look_at(at + Vector3(1, 0, 0.15), Vector3.UP, true)     # 등을 돌리고 복도 끝(동쪽)을 바라본다
	if lvl.soeun_poser:
		lvl.soeun_poser.mode = "idle"
		lvl.soeun_poser.head_raise = 0.0
	s.visible = not instant
	soeun_placed = true

## 인지 후 손전등이 짧게 깜빡이고, 다시 빛이 들어오면 소은은 없다 (꺼진 프레임에서만 사라짐)
func soeun_vanish_flashlight(instant: bool) -> void:
	var s: Node3D = lvl.soeun_node
	soeun_gone = true
	if instant:
		if s:
			s.visible = false
		return
	var fl: Flashlight = lvl.player.flashlight
	var seq := [[false, 0.07], [true, 0.05], [false, 0.09], [true, 0.04], [false, 0.42]]
	Sounds.play("sfx_flashlight_off", &"SFX", -16.0)
	for step in seq:
		if fl.is_on:
			fl.spot.visible = step[0]
		if not step[0] and step[1] > 0.3 and s:
			s.visible = false
		await get_tree().create_timer(step[1], false).timeout
	if s:
		s.visible = false
	if fl.is_on:
		fl.spot.visible = true

# =========================================================== STEP 03~05 괴물
func _ensure_noise() -> void:
	if noise:
		return
	var path := "res://assets/models/characters/gst_noise_silhouette.gltf"
	if not ResourceLoader.exists(path):
		path = "res://assets/models/characters/gst_prologue_monster.gltf"
	var r: Array = lvl._character(path)
	noise = r[0]
	noise_poser = r[1]
	if noise == null:
		return
	noise.name = "NoiseSilhouette"
	var sh := load("res://shaders/noise_tape.gdshader") as Shader
	for mi in noise.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat == null:
				continue
			if mat.resource_name.contains("noise_tape") and sh:
				_noise_tape_mat = ShaderMaterial.new()
				_noise_tape_mat.shader = sh
				m.set_surface_override_material(i, _noise_tape_mat)
			elif mat.resource_name.contains("noise_body"):
				# 손전등을 비추면 실루엣과 일부 외형(거친 표면·테이프 광택)이 보이도록 완전한 검정은 피한다
				var bm := StandardMaterial3D.new()
				bm.albedo_color = Color(0.028, 0.026, 0.026)
				bm.roughness = 0.72
				bm.metallic_specular = 0.45
				m.set_surface_override_material(i, bm)

func _noise_head() -> Vector3:
	var sk := noise.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		var s := sk[0] as Skeleton3D
		var id := s.find_bone("head")
		if id >= 0:
			return s.global_transform * s.get_bone_global_pose(id).origin
	return noise.global_position + Vector3(0, 1.8, 0)

## 모퉁이 뒤에서 머리와 어깨만 내민다 (몸은 통로 안, 벽 뒤)
func place_monster_corner(instant: bool) -> void:
	if instant:
		monster_state = "gone"
		return
	_ensure_noise()
	if noise == null:
		monster_state = "gone"
		return
	var at := b2g(NOISE_PEEK)
	noise.global_position = at
	noise.scale = Vector3.ONE
	noise.look_at(at + Vector3(1, 0, 0), Vector3.UP, true)
	noise_poser.mode = "peek"
	noise_poser.hunch = 0.5
	noise_poser.head_raise = 0.6
	noise_poser.twitch = 0.6
	noise.visible = true
	monster_state = "peeking"
	await get_tree().process_frame
	var base_t := noise.global_transform
	var best := 0.0
	var best_y := -99.0
	for sgn in [1.0, -1.0]:
		noise.global_transform = base_t
		noise.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(NOISE_LEAN) * sgn)
		await get_tree().process_frame
		var hy := g2b(_noise_head()).y          # 복도 쪽(북쪽, y가 큰 쪽)으로 더 나오는 방향을 고른다
		if hy > best_y:
			best_y = hy
			best = sgn
	noise.global_transform = base_t
	noise.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(NOISE_LEAN) * best)

## STEP 04: 벽 뒤에서 천천히 걸어 나와(걷기) → 플레이어 쪽으로 몸을 돌리고(방향 전환) → 잠시 멈춘다 → STEP 05 추격
func monster_emerge() -> void:
	if noise == null or monster_state != "peeking":
		return
	monster_state = "emerging"
	# 기울인 몸을 바로 세우며 복도 쪽(북)을 향한다
	var from := noise.global_position
	var out := b2g(NOISE_OUT)
	var face_n := Transform3D(Basis(), from).looking_at(from + (out - from).normalized(), Vector3.UP, true).basis
	var tw := create_tween()
	tw.tween_property(noise, "global_transform", Transform3D(face_n, from), 0.5).set_trans(Tween.TRANS_SINE)
	await tw.finished
	noise_poser.mode = "walk"
	noise_poser.speed = 0.55
	var dist := from.distance_to(out)
	var t := 0.0
	var dur := dist / 0.75                     # 느린 걸음
	while t < dur:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := clampf(t / dur, 0, 1)
		noise.global_position = from.lerp(out, k)
		_monster_step_sound(0.75)
	monster_state = "turning"
	noise_poser.mode = "idle"
	var target: Vector3 = lvl.player.global_position
	var face_p := Transform3D(Basis(), out).looking_at(Vector3(target.x, out.y, target.z), Vector3.UP, true).basis
	var tw2 := create_tween()
	tw2.tween_property(noise, "global_transform", Transform3D(face_p, out), 0.7).set_trans(Tween.TRANS_SINE)
	Sounds.play_at("mon_step", out, &"SFX", -8.0, null, 0.05, "", 3.0)
	await tw2.finished
	monster_state = "paused"
	noise_poser.twitch = 1.0
	noise_poser.head_raise = 0.9
	Sounds.play_at("mon_breath", _noise_head(), &"SFX", -6.0, null, 0.03, "", 3.0)
	await get_tree().create_timer(1.3, false).timeout
	# 추격 시작
	noise_poser.twitch = 0.7
	_chase_t = 0.0
	_gap_want = maxf(noise.global_position.distance_to(lvl.player.global_position), 3.5)
	_speed = 0.0
	monster_state = "chasing"

func _process(delta: float) -> void:
	if _noise_tape_mat:
		_noise_tape_mat.set_shader_parameter("t", Time.get_ticks_msec() / 1000.0)
	if monster_state == "chasing" or monster_state == "closing":
		_chase(delta)

## STEP 05: 실제 추격 — 복도 바닥을 따라 플레이어에게 달려온다 (벽·기둥을 통과하지 않게 복도 안으로 제한).
## 간격은 서서히 좁혀지고(5 m → 2.2 m) 플레이어가 멈추면 다가와 '잡힌' 것으로 보고 바로 전환한다 (사망 없음).
func _chase(delta: float) -> void:
	var p: PlayerController = lvl.player
	_chase_t += delta
	var m := noise.global_position
	var goal := Vector3(p.global_position.x, m.y, p.global_position.z)
	var dist := Vector2(goal.x - m.x, goal.z - m.z).length()
	var want := 1.2 if monster_state == "closing" else lerpf(_gap_want, 2.2, clampf(_chase_t / 9.0, 0, 1))
	var pv := Vector2(p.velocity.x, p.velocity.z).length()
	var target_speed := clampf(pv + (dist - want) * 1.6, 0.0, 6.2)
	if monster_state == "closing":
		target_speed = maxf(target_speed, 3.0)
	_speed = move_toward(_speed, target_speed, delta * 9.0)
	var dir := (goal - m)
	dir.y = 0
	if dir.length() > 0.05:
		dir = dir.normalized()
		var nm := m + dir * _speed * delta
		nm = _clamp_corridor(nm)
		noise.global_position = nm
		var want_b := Transform3D(Basis(), nm).looking_at(nm + dir, Vector3.UP, true).basis
		noise.global_basis = noise.global_basis.slerp(want_b, clampf(delta * 6.0, 0, 1)).orthonormalized()
	noise_poser.mode = "run" if _speed > 2.2 else ("walk" if _speed > 0.3 else "idle")
	noise_poser.speed = clampf(_speed / 3.2, 0.5, 1.6)
	_monster_step_sound(_speed)
	caught = dist < CAUGHT_DIST
	# 거리 → 심장·호흡 (가까울수록 빠르게)
	if chase_audio_on:
		p.danger = clampf(0.5 + 0.45 * (1.0 - clampf((dist - 1.5) / 8.0, 0, 1)), 0, 0.98)
		_glitch_t -= delta
		if _glitch_t <= 0.0:
			_glitch_t = randf_range(1.2, 3.2)
			Sounds.play_at("sfx_tape_glitch", _noise_head(), &"SFX", randf_range(-8.0, -3.0), null, 0.06, "", 3.0)

func _monster_step_sound(speed: float) -> void:
	if speed < 0.2:
		return
	_step_t -= get_process_delta_time()
	if _step_t <= 0.0:
		_step_t = clampf(0.95 / maxf(speed, 0.5), 0.22, 0.9)
		Sounds.play_at("mon_step", noise.global_position + Vector3(0, 0.05, 0), &"SFX", -4.0 + minf(speed, 5.0), null, 0.06, "", 3.2)

## 복도 바닥 안으로 제한 (벽·기둥 관통 방지). 화장실 통로에서 나오는 구간도 허용
func _clamp_corridor(g: Vector3) -> Vector3:
	var q := g2b(g)
	if q.y < -1.75 and not (q.x > -4.45 and q.x < -3.85):
		q.y = -1.75
	q.y = clampf(q.y, -4.3, -0.48)
	q.x = clampf(q.x, -4.6, 12.8)
	if q.x > -1.85 and q.x < -0.85:
		q.y = minf(q.y, -1.12)                       # 기둥 옆으로 지나간다
	return b2g(Vector3(q.x, q.y, 0)) + Vector3(0, g.y, 0)

func monster_close_in() -> void:
	if monster_state == "chasing":
		monster_state = "closing"

func set_chase_audio(on: bool) -> void:
	chase_audio_on = on

## 손전등이 꺼진 순간: 괴물·발소리·잡음 모두 멈춘다 (어둠 속에서 치움 — 보는 앞에서 사라지지 않음)
func chase_stop() -> void:
	chase_audio_on = false
	if noise:
		noise.visible = false
	monster_state = "gone"
	lvl.player.danger = 0.0

func flashlight_cut(instant: bool) -> void:
	var fl: Flashlight = lvl.player.flashlight
	if fl == null:
		return
	fl.blocked = true
	if fl.is_on and not instant:
		fl.set_on(false)
	elif fl.is_on:
		fl.is_on = false
		fl.spot.visible = false

## 화면 안에 있고 가려지지 않았는가
func _in_view(pt: Vector3, max_deg: float) -> bool:
	var cam: Camera3D = lvl.player.camera
	var to := pt - cam.global_position
	if rad_to_deg((-cam.global_transform.basis.z).angle_to(to.normalized())) > max_deg:
		return false
	return has_los(pt)

func has_los(pt: Vector3) -> bool:
	var cam: Camera3D = lvl.player.camera
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, pt, 1)
	q.exclude = [lvl.player.get_rid()]
	var hit := lvl.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(pt) < 0.35

func lights_off(names: Array, instant: bool) -> void:
	for n in names:
		lvl.set_light(String(n), "story_off", instant)

# =========================================================== 테이프 잡음 (기억 속 공간이 흔들리는 순간)
func tape_glitch(secs: float) -> void:
	if _glitch == null:
		_glitch = ColorRect.new()
		_glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
		_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/tape_glitch.gdshader")
		_glitch.material = sm
		story._fade_layer.add_child(_glitch)
		_glitch.move_to_front()
	_glitch.visible = true
	Sounds.play("amb_tape_hiss", &"SFX", -10.0)
	var t := 0.0
	while t < secs:
		(_glitch.material as ShaderMaterial).set_shader_parameter("amount", randf_range(0.5, 1.0))
		(_glitch.material as ShaderMaterial).set_shader_parameter("seed", randf() * 100.0)
		await get_tree().process_frame
		t += get_process_delta_time()
	_glitch.visible = false

# =========================================================== TAPE 01 (1998)
func apt_child_steps_up() -> void:
	# 계단 위층에서 아이가 뛰어 올라가는 발소리 (아무도 없다)
	var a: Vector3 = lvl.apt.point("apt_frag_2") + Vector3(0, 1.4, 0)
	var c: Vector3 = lvl.apt.point("apt_steps_up") + Vector3(0, 0.1, 0)
	for i in 9:
		Sounds.play_at("step_concrete", a.lerp(c, i / 8.0), &"SFX", -9.0 - i * 0.6, null, 0.05, "위층에서 들리는 작은 발소리" if i == 0 else "", 2.4)
		await get_tree().create_timer(0.21, false).timeout
	await get_tree().create_timer(0.4, false).timeout
	Sounds.play_at("sfx_child_laugh", c + Vector3(0, 1.0, 0), &"SFX", -18.0)

## 소은이 복도 끝에 서 있다 — 플레이어가 그쪽을 보고 있지 않을 때만 놓는다
func apt_place_soeun() -> void:
	var apt: AptCorridor = lvl.apt
	if apt == null or apt.soeun == null:
		return
	var at := apt.point("apt_soeun_end")
	var waited := 0.0
	while _in_view(at + Vector3(0, 1.0, 0), 60.0) and waited < 20.0:
		await get_tree().create_timer(0.2, false).timeout
		waited += 0.2
	apt.soeun.global_position = at
	apt.soeun.look_at(Vector3(lvl.player.global_position.x, at.y, lvl.player.global_position.z), Vector3.UP, true)
	apt.soeun_poser.mode = "idle"
	apt.soeun.visible = true

func apt_soeun_vanish() -> void:
	var apt: AptCorridor = lvl.apt
	if apt == null or apt.soeun == null:
		return
	await get_tree().create_timer(1.3, false).timeout
	# 테이프가 늘어지는 순간 (화면·소리 잡음) — 잡음이 걷히면 소은은 없다
	tape_glitch(0.45)
	apt.lamps_power(0.2)
	await get_tree().create_timer(0.2, false).timeout
	apt.soeun.visible = false
	await get_tree().create_timer(0.25, false).timeout
	apt.lamps_power(1.0)
