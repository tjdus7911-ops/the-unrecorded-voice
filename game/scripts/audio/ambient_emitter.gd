class_name AmbientEmitter
extends AudioStreamPlayer3D
## 반복 환경음 3D 음원 + 간이 차폐(occlusion).
## 청취자와 음원 사이에 벽·닫힌 문이 있으면 고음을 깎고 볼륨을 낮춘다 (문을 열면 자연스럽게 열린 소리로).

@export var sound_id := ""
@export var base_volume_db := 0.0
@export var occluded_cutoff_hz := 700.0
@export var occluded_db := -9.0
@export var occlusion_mask := 1
@export var check_interval := 0.12

var occluded := false
## 페이드용 추가 이득 (요구사항 20: 예전엔 volume_db 트윈이 매 프레임 덮어써져 페이드가 되지 않았다)
var gain_db := 0.0
var occlusion := 0.0           ## 0 = 트임, 1 = 완전히 막힘 (여러 경로 중 막힌 비율 — 문틈·모서리 회절 근사)
var _occl := 0.0
const PROBES := [Vector3.ZERO, Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0), Vector3(0, -0.7, 0)]
var _t := 0.0

func _ready() -> void:
	if sound_id != "" and stream == null:
		stream = Sounds.pick(sound_id)
	volume_db = base_volume_db
	if stream:
		play(randf() * maxf(stream.get_length() - 0.1, 0.0))

func _physics_process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = check_interval
		var cam := get_viewport().get_camera_3d()
		if cam:
			var blocked := 0
			var space := get_world_3d().direct_space_state
			for off in PROBES:
				var target: Vector3 = global_position + off
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, target, occlusion_mask)
				q.hit_back_faces = true
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and (hit.position as Vector3).distance_to(target) > 0.25:
					blocked += 1
			occlusion = float(blocked) / PROBES.size()
			occluded = occlusion > 0.5
	_occl = move_toward(_occl, occlusion, delta * 3.0)
	attenuation_filter_cutoff_hz = lerpf(20500.0, occluded_cutoff_hz, _occl)
	volume_db = base_volume_db + occluded_db * _occl + gain_db
