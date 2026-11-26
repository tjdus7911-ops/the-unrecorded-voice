class_name PlayerController
extends CharacterBody3D
## 1인칭 플레이어 (서정우).
## 이동·달리기·앉기·시점·상호작용 + 호흡/심장 박동/카메라 연동의 기준 상태를 제공한다.

signal interact_target_changed(target: Interactable)

@export_group("Movement")
@export var walk_speed := 1.7        ## m/s — 공포 장르 기준 느린 보행
@export var run_speed := 3.8
@export var crouch_speed := 0.9
@export var acceleration := 9.0
@export var friction := 12.0

@export_group("Body")
@export var stand_height := 1.75
@export var crouch_height := 1.15
@export var eye_below_top := 0.13    ## 눈높이 = 키 - 0.13 → 서 있을 때 1.62 m
@export var radius := 0.28

@export_group("Stamina")
@export var stamina_max := 6.0       ## 연속 달리기 가능 시간(초)
@export var stamina_regen := 0.75    ## 초당 회복량
@export var exhausted_threshold := 2.0  ## 탈진 후 이만큼 회복해야 다시 달릴 수 있음

@export_group("Camera FX")
@export var bob_amount_walk := 0.012
@export var bob_amount_run := 0.028
@export var breath_sway := 0.0035

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var flashlight: Flashlight = $Flashlight
@onready var breathing: BreathingSystem = $BreathingSystem
@onready var heartbeat: HeartbeatSystem = $HeartbeatSystem

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var input_enabled := true
var stamina := 6.0
var is_running := false
var is_crouching := false
var is_exhausted := false
var is_hiding := false
## 0~1 위험도. 귀신 AI·스크립트 이벤트가 설정한다 (심장 박동·호흡·손 떨림에 반영).
var danger := 0.0

var _yaw := 0.0
var _pitch := 0.0
var _height := 1.75
var _bob_t := 0.0
var _breath_t := 0.0
var _interact_target: Interactable

func _ready() -> void:
	stamina = stamina_max
	_height = stand_height
	_yaw = rotation.y
	_apply_height()
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = GameSettings.mouse_sensitivity
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens, deg_to_rad(-85), deg_to_rad(85))
	elif event.is_action_pressed("flashlight"):
		flashlight.toggle()
	elif event.is_action_pressed("interact"):
		try_interact()
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("debug_danger") and OS.is_debug_build():
		danger = 0.0 if danger > 0.5 else 1.0

func _physics_process(delta: float) -> void:
	rotation.y = _yaw
	head.rotation.x = _pitch

	var input_dir := Vector2.ZERO
	var want_run := false
	var want_crouch := false
	if input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		want_run = Input.is_action_pressed("sprint")
		want_crouch = Input.is_action_pressed("crouch")

	_update_crouch(want_crouch, delta)
	_update_stamina(want_run and input_dir.length() > 0.1, delta)

	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_running:
		speed = run_speed

	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	dir.y = 0.0
	dir = dir.normalized() * minf(input_dir.length(), 1.0)
	var target := dir * speed
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if target.length() > 0.01 else friction
	horiz = horiz.move_toward(target, rate * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = maxf(velocity.y, -0.1)
	move_and_slide()

	_update_camera_fx(delta)
	_update_interact_target()
	breathing.update_from_player(self, delta)
	heartbeat.set_danger(danger)
	flashlight.set_tremble(danger)

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

# --- Crouch ---------------------------------------------------------------
func _update_crouch(want: bool, delta: float) -> void:
	if want:
		is_crouching = true
	elif is_crouching and _can_stand():
		is_crouching = false
	var goal := crouch_height if is_crouching else stand_height
	_height = move_toward(_height, goal, delta * 3.0)
	_apply_height()

func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius * 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * (stand_height - radius))
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()

func _apply_height() -> void:
	var cap := collision.shape as CapsuleShape3D
	cap.height = _height
	cap.radius = radius
	collision.position.y = _height * 0.5
	head.position.y = _height - eye_below_top

# --- Stamina --------------------------------------------------------------
func _update_stamina(trying_to_run: bool, delta: float) -> void:
	if is_exhausted and stamina >= exhausted_threshold:
		is_exhausted = false
	is_running = trying_to_run and not is_exhausted and not is_crouching
	if is_running:
		stamina = maxf(stamina - delta, 0.0)
		if stamina <= 0.0:
			is_exhausted = true
			is_running = false
	else:
		var regen := stamina_regen * (1.4 if horizontal_speed() < 0.1 else 1.0)
		stamina = minf(stamina + regen * delta, stamina_max)

# --- Camera ---------------------------------------------------------------
func _update_camera_fx(delta: float) -> void:
	var shake: float = GameSettings.camera_shake
	var spd := horizontal_speed()
	var bob_amt := 0.0
	if is_on_floor() and spd > 0.2:
		var freq := 1.9 if not is_running else 2.6   # 걸음 주기(Hz)
		_bob_t += delta * freq * TAU * 0.5
		bob_amt = bob_amount_run if is_running else bob_amount_walk
	var bob_y := sin(_bob_t * 2.0) * bob_amt
	var bob_x := sin(_bob_t) * bob_amt * 0.5
	# 호흡에 따른 미세한 상하 움직임 — 호흡 시스템의 현재 속도를 따른다
	_breath_t += delta * TAU * breathing.breath_rate_hz()
	var sway := sin(_breath_t) * breath_sway * breathing.breath_depth()
	if is_hiding:
		bob_y *= 0.2
		bob_x *= 0.2
	camera.position = camera.position.lerp(Vector3(bob_x, bob_y + sway, 0.0) * shake, clampf(delta * 12.0, 0.0, 1.0))

# --- Interaction ----------------------------------------------------------
func _update_interact_target() -> void:
	var t: Interactable = null
	if interact_ray.is_colliding():
		var c := interact_ray.get_collider()
		if c is Interactable and (c as Interactable).can_interact(self):
			t = c
	if t != _interact_target:
		_interact_target = t
		interact_target_changed.emit(t)

## 테스트·컷신용: 특정 지점을 바라보게 한다
func look_at_point(pt: Vector3) -> void:
	var d := pt - head.global_position
	_yaw = atan2(-d.x, -d.z)
	_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	rotation.y = _yaw
	head.rotation.x = _pitch

func try_interact() -> bool:
	head.force_update_transform()
	interact_ray.force_raycast_update()
	_update_interact_target()
	if _interact_target:
		_interact_target.interact(self)
		return true
	return false
