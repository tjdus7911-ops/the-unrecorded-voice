class_name GhostPresence
extends RefCounted
## 귀신 등장 상태 (요구사항 08 §5) — 공통 구조. 프롤로그는 연출용(공격 불가)만 사용한다.
## 귀신 AI(순찰·감지·추격·공격)는 P3 단계에서 이 상태를 그대로 쓴다.

enum State { ABSENT, SOUND_ONLY, SHADOW_ONLY, OBSERVE_FAR, PATROL, DETECT, CHASE, ATTACK, SEARCH, VANISH }

const FROM_DATA := {
	"absent": State.ABSENT, "sound_only": State.SOUND_ONLY, "shadow_only": State.SHADOW_ONLY,
	"observe_far": State.OBSERVE_FAR, "patrol": State.PATROL, "detect": State.DETECT, "chase": State.CHASE,
	"attack": State.ATTACK, "search": State.SEARCH, "vanish": State.VANISH,
}

var id := ""
var state: int = State.ABSENT
## 연출용 귀신은 false — 어떤 상태가 되어도 공격·추격 판정을 하지 않는다
var can_attack := false

static func from_event(entry: Dictionary) -> GhostPresence:
	var g := GhostPresence.new()
	g.id = entry.get("id", "")
	g.can_attack = bool(entry.get("can_attack", false))
	g.set_state(FROM_DATA.get(String(entry.get("presence", "absent")), State.ABSENT))
	return g

## 연출용 귀신이 실수로 추격·공격 상태가 되지 않게 막는다
func set_state(s: int) -> void:
	if not can_attack and s in [State.DETECT, State.CHASE, State.ATTACK, State.SEARCH]:
		push_warning("GhostPresence %s: 연출용 귀신은 %s 상태가 될 수 없음" % [id, State.keys()[s]])
		return
	state = s

func is_dangerous() -> bool:
	return can_attack and state in [State.CHASE, State.ATTACK]
