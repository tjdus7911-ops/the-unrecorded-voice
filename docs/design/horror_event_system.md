# 공포 이벤트 · 스토리 트리거 시스템 (요구사항 08)

## 구성
| 파일 | 역할 |
|---|---|
| `game/data/events/prologue_events.json` | 이벤트 데이터 (코드 하드코딩 없음) |
| `game/scripts/story/event_director.gd` | 트리거 평가·실행·중복 방지·저장/복원·디버그 강제 실행 |
| `game/scripts/story/prologue_story.gd` | 액션 실행기 (조명·소리·음성·연출) |
| `game/scripts/ui/debug_menu.gd` | F8 디버그 메뉴 (디버그 빌드 전용 — 릴리스 내보내기에서 생성 안 됨) |
| `game/scenes/tests/run_story_tests.gd` | EVENT 01~08 자동 검증 (34항목) |

## 이벤트 필드
`id`, `chapter_id`, `scene_id`, `trigger`(발생 조건), `requires`(선행 이벤트), `delay`(발생 지연), `lights`(조명 상태),
`characters`(등장 캐릭터·위치·행동·`can_attack`), `actions`(시간 t별: 음성·효과음·환경음·호흡·심장·연출),
`lock_interaction`(상호작용 제한 초), `end`(종료 조건: immediate / {after}), `repeatable`, `checkpoint`, `next`.

## 트리거 종류
- `game_start` · `tutorial_complete`(이동 m·둘러본 각도·조사 횟수·최소 시간 + 조건) · `time`
- `signal`: `door_opened` `door_locked_try` `recorder_play`(테이프 번호) `recorder_stop` `tape_inserted` `flashlight_pickup`
  `flashlight_on/off` `switch` `drawer` `parcel_picked` `parcel_placed` `inspect:<이름>` `item:<아이템>` `interact`
- `look_at`(대상·최대 각도·`fallback_after`) — "특정 방향 바라보기", 시선을 돌린 뒤 발생
- `near`(대상·반경) — 특정 위치 도달 / 공간 진입
- 조건(`conditions`): `player_in_studio`, `door_closed`, `has_flashlight`, `not_tried_door`

## 안정성 규칙
- 같은 이벤트 중복 실행 금지 (started/done), 선행 이벤트 미완료 시 평가 안 함
- 핵심 이벤트는 시간만으로 발생하지 않는다. `fallback_after`는 플레이어가 필요한 행동을 한 **뒤** 뒤돌아보지 않을 때 이야기가 멈추지 않게 하는 장치
- 등 뒤 목소리는 카메라 뒤 2.2 m, 작업실 안으로 위치 제한 (벽 너머·코앞 생성 금지)
- 일시정지 중에는 이벤트 타이머·평가가 멈춘다 (트리 일시정지)
- 저장: 완료 이벤트 목록 + 조명 + 오브젝트 + 인벤토리 + 플레이어 위치. 불러오면 완료 이벤트의 **지속 효과만** 즉시 재적용 (음성·힌트 반복 없음)
- 손전등은 건물 정전의 영향을 받지 않는다. EVENT 08의 손전등 이상은 초자연 연출(`flashlight_glitch`)에서만
- 조명 깜빡임 완화 설정(`reduce_flashes`)은 LightFixture·천둥에 반영

## 귀신 등장 상태 (공통 구조 — 프롤로그는 연출용만)
`absent` · `sound_only` · `shadow_only` · `observe_far` · `patrol` · `detect` · `chase` · `attack` · `search` · `vanish`
- 프롤로그 데이터의 `characters[].presence`는 `sound_only`/`shadow_only`/`observe_far`만 사용, `can_attack: false`
- 공격 가능한 귀신·추격 AI는 P3 (아직 구현하지 않음)
