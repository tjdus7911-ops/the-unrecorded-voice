class_name PerfStats
extends RefCounted
## 실제 실행 기준 성능 지표 (F3 오버레이·벤치마크 공용)

static func snapshot() -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		"texture_mem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		"buffer_mem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"adapter": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
	}

static func summary() -> String:
	var s := snapshot()
	return "FPS %d   (%.1f ms)\n드로우콜 %d   오브젝트 %d\n폴리곤 %dk\nVRAM %.0f MB (텍스처 %.0f)\nRAM %.0f MB   노드 %d\n%s / %s" % [
		s.fps, 1000.0 / maxf(s.fps, 1.0), s.draw_calls, s.objects, int(s.primitives / 1000.0), s.video_mem_mb,
		s.texture_mem_mb, s.static_mem_mb, s.nodes, s.renderer, s.adapter]
