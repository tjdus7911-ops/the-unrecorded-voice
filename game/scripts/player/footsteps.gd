class_name Footsteps
extends Node3D
## 이동 거리 기반 발소리. 발밑 충돌체의 surface 메타데이터로 재질을 판별한다 (wood / tile / concrete / rug).

@export var stride_walk := 0.62
@export var stride_run := 0.95
@export var stride_crouch := 0.45

var player: PlayerController
var _dist := 0.0
var _last_pos := Vector3.ZERO
var _was_on_floor := true
var _ray: RayCast3D
var last_surface := "wood"
var steps_played := 0
## 영역 기반 예외 (러그처럼 별도 충돌체가 없는 바닥 덮개) — 레벨이 등록한다
var surface_zones: Array = []   ## [{aabb: AABB, surface: String}]

func _ready() -> void:
	player = get_parent() as PlayerController
	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, -0.4, 0)
	_ray.position = Vector3(0, 0.2, 0)
	_ray.collision_mask = 1
	add_child(_ray)
	_last_pos = player.global_position

func surface_here() -> String:
	var gp := player.global_position
	for z in surface_zones:
		if (z["aabb"] as AABB).has_point(gp + Vector3(0, 0.05, 0)):
			return z["surface"]
	_ray.force_raycast_update()
	if _ray.is_colliding():
		var c := _ray.get_collider() as Node
		while c:
			if c.has_meta("surface"):
				return c.get_meta("surface")
			c = c.get_parent()
	return "wood"

func _physics_process(_delta: float) -> void:
	var p := player.global_position
	var moved := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_last_pos = p
	if not player.is_on_floor():
		_was_on_floor = false
		return
	if not _was_on_floor:
		_was_on_floor = true
		_step(1.5)            # 착지
		return
	_dist += moved
	var stride := stride_crouch if player.is_crouching else (stride_run if player.is_running else stride_walk)
	if _dist >= stride and player.horizontal_speed() > 0.25:
		_dist = 0.0
		_step(1.0)

func _step(intensity: float) -> void:
	last_surface = surface_here()
	var vol := -6.0
	if player.is_running:
		vol = 0.0
	elif player.is_crouching:
		vol = -16.0
	Sounds.play_at("step_" + last_surface, player.global_position + Vector3(0, 0.05, 0), &"SFX", vol + 4.0 * (intensity - 1.0),
			null, 0.06, "", 2.0)
	steps_played += 1
