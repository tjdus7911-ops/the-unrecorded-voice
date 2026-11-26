class_name LightSwitch
extends Interactable
## 벽 스위치. 연결된 LightFixture의 상태가 DEAD/NEEDS_POWER면 눌러도 켜지지 않는다.

@export var fixtures: Array[NodePath] = []
@export var click_sound: AudioStream

func _ready() -> void:
	super._ready()
	prompt = "스위치 누르기"

func _on_interact(_by: Node) -> void:
	for path in fixtures:
		var f := get_node_or_null(path) as LightFixture
		if f:
			f.press_switch()
	if click_sound:
		var p := AudioStreamPlayer3D.new()
		p.stream = click_sound
		p.bus = &"SFX"
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
