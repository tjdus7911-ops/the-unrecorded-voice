# 에셋 출처 · 라이선스 기록

모든 외부 에셋과 임시(Placeholder) 리소스를 여기에 기록한다. 기록되지 않은 외부 에셋은 저장소에 추가하지 않는다.

상태: `ORIGINAL`(자체 제작) · `PLACEHOLDER`(교체 예정 임시) · `THIRD_PARTY`(외부, 라이선스 명시) · `FINAL`

## 도구 / 엔진

| 이름 | 버전 | 라이선스 | 비고 |
|---|---|---|---|
| Godot Engine | 4.7.2-stable | MIT | 상업 이용·로열티 없음 |
| Blender (bpy 모듈) | 5.3.0 | GPL-3.0 (도구) | Blender로 만든 결과물(모델·렌더)은 GPL 적용 대상 아님 |

## 에셋

| 경로 | 종류 | 상태 | 출처 / 라이선스 | 메모 |
|---|---|---|---|---|
| `game/assets/audio/breathing/PH_*.wav` | 호흡 음원 | PLACEHOLDER | 자체 생성(절차적 노이즈 합성, `tools/audio/make_placeholders.py`) | 실제 성우·음성으로 교체 필요 |
| `game/assets/audio/heartbeat/PH_*.wav` | 심장 박동 | PLACEHOLDER | 자체 생성(합성) | 교체 필요 |
| `game/assets/audio/sfx/PH_*.wav` | 손전등 스위치 등 | PLACEHOLDER | 자체 생성(합성) | 교체 필요 |

## 레퍼런스 이미지
REF 01~21 시트 이미지는 웹 출처가 섞여 있어 `refs_local/`(git 제외)에만 보관한다. 텍스트 지시사항은 `docs/requirements/06_reference_sheets_transcript.md`.
| `art/textures_source/stu/*.png` | 모니터 UI·시계 문자판·카세트 인서트·달력·보관함 라벨 | ORIGINAL | 자체 생성 (`tools/blender/gen_studio_textures.py`, Noto Sans CJK 폰트 — SIL OFL 1.1) | 가상의 소프트웨어 UI, 실제 제품 복제 아님 |
| `art/blender/environments/studio/stu_studio.blend` / `game/assets/models/environments/stu_studio.glb` | 작업실 3D | ORIGINAL | 자체 제작 (`tools/blender/build_studio.py`) | 외부 에셋 사용 없음 |
