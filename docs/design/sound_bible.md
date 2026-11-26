# 사운드 바이블 — 구현 기준

원문: `docs/requirements/04_voice_dubbing_sound.md`, `05_breathing_heartbeat_stealth.md`

## 1. 오디오 버스 (game/default_bus_layout.tres)

```
Master
├─ Voice        캐릭터 대사 (실시간 인물)
│  └─ VoiceTape    카세트 음성: 밴드패스(300Hz~3.4kHz) + 미세 디스토션
├─ Breathing    플레이어 호흡 (대사 재생 시 덕킹)
├─ Heartbeat    심장 박동 (발소리·단서 음성을 가리지 않도록 상한 -12dB)
├─ Ghost        귀신 발소리·호흡·음성 (3D)
├─ Ambience     환경음 (빗소리·팬·형광등 등)
├─ SFX          상호작용 효과음 (문·손전등·녹음기)
├─ Music        배경음악 (상시 재생 금지)
└─ UI
```

- 설정 화면의 각 슬라이더는 위 버스 하나에 1:1 대응한다: 전체 음량(Master), 캐릭터 음성(Voice), 환경음(Ambience), 효과음(SFX + Ghost), 배경음악(Music), 호흡 효과음 강도(Breathing + Heartbeat).
- **음량 차이 완화** 옵션: Master에 리미터/컴프레서 활성화.
- 모든 버스에 리미터(-1 dBFS) — 갑작스러운 효과음 과대 음량 방지.

## 2. 캐릭터 · 음성 ID (game/data/config/characters.json)

| character_id | 이름 | voice_id | 음성 성격 |
|---|---|---|---|
| `jungwoo_adult` | 서정우(37) | `vo_jungwoo_adult` | 낮고 차분, 약간 지친 30대 남성 |
| `jungwoo_child` | 서정우(9) | `vo_jungwoo_child` | 자연스럽고 장난기 있는 남자아이 |
| `soeun` | 한소은(9) | `vo_soeun` | 밝고 순수, 호기심 많은 여자아이 |
| `mansu` | 박만수(경비원, 58) | `vo_mansu` | 나이 듦, 거칠고 소극적 |
| `youngsik` | 최영식(관리소장, 46) | `vo_youngsik` | 권위적이고 냉정한 중년 |
| `resident_*` | 주민 | `vo_resident_*` | 연령·성별·성격별 |

승인된 voice_id는 전 챕터에서 바꾸지 않는다. 실제 인물 목소리 복제 금지.

## 3. 대사 데이터 스키마 (game/data/dialogue/*.json)

```json
{
  "line_id": "PRO_S03_001",
  "character_id": "jungwoo_adult",
  "voice_id": "vo_jungwoo_adult",
  "chapter_id": "prologue",
  "scene_id": "S03_knock",
  "text": { "ko": "이 시간에 누구지?" },
  "subtitle": { "ko": "이 시간에 누구지?" },
  "emotion": "uneasy",
  "audio": { "ko": "res://assets/audio/voice/jungwoo_adult/PRO_S03_001.ogg" },
  "playback": {
    "mode": "live",
    "position": "player",
    "volume_db": 0.0,
    "fx": []
  },
  "condition": "flag:knock_1_heard"
}
```

- `playback.mode`: `live`(실제 인물) · `tape`(녹음기 출력: VoiceTape 버스 + 테이프 히스) · `memory`(기억 속: 공간 잔향 + 방향성) · `ghost`
- `playback.position`: `player` / `behind_player` / `node:<NodePath>` / 월드 좌표 — 프롤로그 SCENE 05의 "정우야?"는 `behind_player` (녹음기가 아닌 3D 공간에서 발생)
- 음성 파일이 없으면 자막만 표시하고 경고 로그 — 게임은 멈추지 않는다.
- 감정 값: `neutral, joy, playful, flustered, uneasy, fear, anger, sad, guilt, tearful, whisper, scream, heavy_breath`

## 4. 동적 호흡 (scripts/audio/breathing_system.gd)

| 상태 | 트리거 | 1차 구현 |
|---|---|---|
| `calm` 평상시 | 정지 | ✅ |
| `walk` 걷는 중 | 이동 | ✅ |
| `run` 달리는 중 | 달리기 | ✅ |
| `exhausted` 헐떡임 | 스태미나 소진 | ✅ (달리기 지속 시 진입) |
| `fear` 공포 | 위험도 ≥ 0.5 | ✅ |
| `gasp` 놀람 | 원샷 이벤트 | 원샷 API만 |
| `trembling` 떨림 | 위험도 상승 중 | 2차 |
| `hold` 숨 참기 | 은신 + 키 | 귀신 AI 단계 |
| `relief` 안도 | 위험 해제 원샷 | 원샷 API만 |
| `tearful` 울먹임 | 스토리 이벤트 | 2차 |

- 전환: 두 플레이어 간 **크로스페이드(기본 0.8s)**, 사이클 경계에서 교체.
- 반복 방지: 상태별 음원 풀에서 직전 2개 제외 랜덤, 간격 ±15%, 음량 ±2dB, 피치 ±3% 변화.
- 대사 재생 중: Breathing 버스 -9dB 덕킹(0.3s 어택 / 0.8s 릴리즈).

## 5. 심장 박동 (scripts/audio/heartbeat_system.gd)

| 위험 단계 | danger 값 | BPM | 음량 |
|---|---|---|---|
| 안전 | 0.0 | 65 | 거의 무음 (-40dB) |
| 위험 감지 | ~0.35 | 85 | -26dB |
| 귀신 접근 | ~0.7 | 115 | -18dB |
| 추격 | 1.0 | 135~150, ±8% 불규칙 | -14dB |
| 위험 해제 | 감소 | 지수 감쇠(약 6초)로 복귀 | |

`danger`는 0~1 연속값. 귀신 AI가 생기기 전엔 디버그/스크립트 이벤트로 설정한다.

## 6. 반전 연출 규칙
TAPE 06(왜곡된 기억)과 TAPE 07(실제 녹음)은 같은 공간 잔향·배경음·테이프 질감을 공유하고 대사만 달라야 한다. 플레이어가 "같은 녹음의 다른 버전"으로 인지하게 하는 것이 목적.
