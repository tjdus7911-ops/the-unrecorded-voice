class_name Benchmark
extends Node
## 성능 측정 모드: 실행 인자 `-- --benchmark` (테스트 빌드에서도 동작)
## 고정 시점 6곳을 돌며 각 4초씩 FPS·프레임 시간·드로우콜·VRAM을 기록하고
## 실행 파일 옆에 benchmark_YYYYMMDD_HHMMSS.txt / .json 을 쓴 뒤 종료한다.

const VIEWS := [
	["작업실 전경", Vector3(0.75, 0.6, 0), Vector3(3.6, 4.4, 0.9), {}],
	["책상 1인칭", Vector3(2.85, 3.15, 0), Vector3(2.75, 4.6, 0.85), {}],
	["작업실 소등 + 손전등", Vector3(1.6, 1.4, 0), Vector3(3.2, 4.6, 0.3), {"dark": true}],
	["복도 (문 열림)", Vector3(0.95, -0.35, 0), Vector3(9.0, -1.2, 1.1), {"door": true}],
	["복도 서쪽", Vector3(11.0, -0.8, 0), Vector3(-4.0, -1.2, 1.0), {}],
	["계단실 암흑 + 손전등", Vector3(13.73, -0.8, 0), Vector3(13.73, 2.9, -1.5), {"flash": true}],
]
const SECONDS := 4.0

var lvl: Node3D
var results: Array = []

func run(level: Node3D) -> void:
	lvl = level
	await get_tree().create_timer(2.0).timeout
	var p: PlayerController = lvl.player
	p.input_enabled = false
	lvl.hud.help.visible = false
	lvl.hud.perf.visible = true
	for v in VIEWS:
		var opts: Dictionary = v[3]
		if opts.get("dark", false):
			lvl.fx["DeskLamp"].switched_on = false
			lvl.fx["DeskLamp"]._apply()
			lvl.fx["FloorLamp"].switched_on = false
			lvl.fx["FloorLamp"]._apply()
			Inventory.add(&"flashlight")
			p.flashlight.set_on(true)
		if opts.get("door", false) and not lvl.door_open:
			lvl.toggle_door()
			await get_tree().create_timer(1.2).timeout
		if opts.get("flash", false):
			Inventory.add(&"flashlight")
			p.flashlight.set_on(true)
		var b: Vector3 = v[1]
		p.global_position = Vector3(b.x, 0.05, -b.y)
		await get_tree().physics_frame
		var t: Vector3 = v[2]
		p.look_at_point(Vector3(t.x, t.z, -t.y))
		await get_tree().create_timer(0.8).timeout     # 셰이더·GI 안정화
		var frames: Array[float] = []
		var draws := 0
		var el := 0.0
		while el < SECONDS:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			el += dt
			frames.append(dt * 1000.0)
			draws = max(draws, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		frames.sort()
		var avg := 0.0
		for f in frames:
			avg += f
		avg /= maxf(frames.size(), 1)
		var p99: float = frames[int(frames.size() * 0.99)] if frames.size() > 0 else 0.0
		var s := PerfStats.snapshot()
		results.append({"view": v[0], "avg_fps": 1000.0 / maxf(avg, 0.001), "low1_fps": 1000.0 / maxf(p99, 0.001),
				"avg_ms": avg, "p99_ms": p99, "draw_calls_max": draws, "primitives": s.primitives,
				"vram_mb": s.video_mem_mb, "texture_mb": s.texture_mem_mb, "ram_mb": s.static_mem_mb})
		if opts.get("dark", false):
			p.flashlight.set_on(false)
			lvl.fx["DeskLamp"].switched_on = true
			lvl.fx["DeskLamp"]._apply()
			lvl.fx["FloorLamp"].switched_on = true
			lvl.fx["FloorLamp"]._apply()
		if opts.get("flash", false):
			p.flashlight.set_on(false)
	_write()
	get_tree().quit()

func _write() -> void:
	var info := "GPU: %s | 렌더러: %s | 해상도: %s | 품질: %d | OS: %s" % [RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_method(), str(get_viewport().get_visible_rect().size), GameSettings.graphics_quality,
			OS.get_name()]
	var lines := ["녹음되지 않은 목소리 — PHASE 01 벤치마크", Time.get_datetime_string_from_system(), info, "",
			"%-22s %8s %8s %8s %8s %10s %9s" % ["시점", "평균FPS", "1%저점", "평균ms", "드로우콜", "폴리곤", "VRAM MB"]]
	for r in results:
		lines.append("%-22s %8.1f %8.1f %8.2f %8d %10d %9.0f" % [r.view, r.avg_fps, r.low1_fps, r.avg_ms, r.draw_calls_max,
				r.primitives, r.vram_mb])
	var txt := "\n".join(lines)
	print(txt)
	var dir := OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ProjectSettings.globalize_path("user://")
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var f := FileAccess.open(dir.path_join("benchmark_%s.txt" % stamp), FileAccess.WRITE)
	if f == null:
		f = FileAccess.open("user://benchmark_%s.txt" % stamp, FileAccess.WRITE)
	if f:
		f.store_string(txt)
	var j := FileAccess.open(dir.path_join("benchmark_%s.json" % stamp), FileAccess.WRITE)
	if j:
		j.store_string(JSON.stringify({"info": info, "results": results}, "  "))
