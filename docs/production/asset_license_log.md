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
| `game/assets/audio/breathing/PH_*.wav` | 호흡 음원 | PLACEHOLDER | 자체 생성(포먼트 필터 합성, `tools/audio/make_placeholders.py`) | 실제 성우 호흡으로 교체 필요 |
| `game/assets/audio/{ambience,sfx,footsteps}/PH_*` | 빗소리·천둥·팬·형광등·시계·발소리(4재질)·문·노크·카세트·상자·정전·데드볼트·형광등 점등·그네 등 42종 | PLACEHOLDER | 자체 DSP 합성 (`tools/audio/make_sfx.py`) — 외부 녹음 없음 | 최종 사운드 디자인(폴리 녹음 또는 라이선스 라이브러리)으로 교체 권장 |
| `game/assets/audio/voice/*/PH_*.wav` | 캐릭터 한국어 음성 16개(프롤로그 대사 7 + 샘플 7 + 테이프 웃음 2) | PLACEHOLDER · **비상업** | sherpa-onnx(Apache-2.0) + Mimic3 `ko_KO-kss_low` 음성 (KSS 데이터셋 기반: **CC BY-NC-SA 4.0**) — 캐릭터별 음정·포먼트 처리 | ⚠ 상업 빌드 포함 금지. 대사 타이밍·자막 동기화 테스트 전용. 최종 더빙으로 교체 |
| `game/assets/fonts/NotoSansKR-*-subset.otf` | UI 한글 폰트 (한글 11,172자 + 라틴 서브셋) | THIRD_PARTY | Noto Sans CJK — **SIL Open Font License 1.1** (상업 이용·임베딩 가능). 원문 `game/assets/fonts/LICENSE_NotoSansCJK.txt` | |
| `game/assets/textures/pbr/*` · `decals/*` · `fx/*` | PBR 타일 텍스처 37종 · 데칼 5종 · 손전등 패턴 | ORIGINAL | 자체 생성 (`tools/textures/gen_pbr.py`, `gen_fx_textures.py`) — 주기적 FFT 노이즈 | |
| `game/assets/textures/{stu,props,cor}/*` | 모니터 UI·시계·라벨·운송장·메모 손글씨·표지판 | ORIGINAL | 자체 생성 (Noto Sans CJK OFL 폰트로 글자 렌더) | 실존 택배사·제품 디자인 사용 없음 |
| `game/assets/models/**` · `art/blender/**` | 작업실·복도·주요 오브젝트 7종 | ORIGINAL | 자체 제작 (`tools/blender/build_*.py`) | 외부 모델 사용 없음 |
| `game/assets/audio/heartbeat/PH_*.wav` | 심장 박동 | PLACEHOLDER | 자체 생성(합성) | 교체 필요 |
| `game/assets/audio/sfx/PH_*.wav` | 손전등 스위치 등 | PLACEHOLDER | 자체 생성(합성) | 교체 필요 |

## 레퍼런스 이미지
REF 01~21 시트 이미지는 웹 출처가 섞여 있어 `refs_local/`(git 제외)에만 보관한다. 텍스트 지시사항은 `docs/requirements/06_reference_sheets_transcript.md`.
| `art/textures_source/stu/*.png` | 모니터 UI·시계 문자판·카세트 인서트·달력·보관함 라벨 | ORIGINAL | 자체 생성 (`tools/blender/gen_studio_textures.py`, Noto Sans CJK 폰트 — SIL OFL 1.1) | 가상의 소프트웨어 UI, 실제 제품 복제 아님 |
| `art/blender/environments/studio/stu_studio.blend` / `game/assets/models/environments/stu_studio.glb` | 작업실 3D | ORIGINAL | 자체 제작 (`tools/blender/build_studio.py`) | 외부 에셋 사용 없음 |

| `art/third_party/makehuman/*` (base.obj, default.mhskel, default_weights.mhw) | 1인칭 손·팔 베이스 메시·뼈대·웨이트 | THIRD_PARTY | MakeHuman 1.x 기본 에셋 — **CC0** (원문 `art/third_party/makehuman/LICENSE.md`). 상업 이용·수정 자유, 표기 의무 없음 | `tools/blender/build_arms.py`가 손 부분만 잘라 리그·텍스처 제작 |
| `game/assets/models/characters/chr_jungwoo_arms.gltf` | 서정우 1인칭 손·팔(좌우)·카디건 소매·리그·포즈 11종 | ORIGINAL (CC0 베이스 가공) | `tools/blender/build_arms.py` | 손톱·마디 주름·손금·핏줄·모공은 절차적 셰이더 → 2048 베이크 |
| `game/assets/textures/chr/chr_skin_*`, `chr_knit_*`, `chr_rib_*` | 피부(베이크) · 니트 저지 · 2x2 고무단 | ORIGINAL | `build_arms.py` 베이크, `tools/textures/gen_knit_textures.py` | |
| `game/assets/models/characters/PH_chr_soeun_silhouette.gltf` | 소은 역광 실루엣 (1998 복도 끝) | PLACEHOLDER | MakeHuman CC0 메시를 아이 비율로 변형 (`tools/blender/build_silhouette.py`) | 얼굴·디테일 없음. 정식 캐릭터 모델로 교체 |
| `game/scripts/levels/apt_corridor.gd` (1998 아파트 복도) | EVENT 08 도착 공간 | PLACEHOLDER (블록아웃) | 기존 자체 PBR 텍스처로 코드 생성 | PHASE 02 승인 후 Blender로 정식 제작 |
| `game/assets/audio/sfx/PH_tape_playground.wav` | 테이프 01 도입부 (놀이터 공기·그네·아이 웃음) | PLACEHOLDER · **비상업** | 합성 + 위 TTS 웃음 (CC BY-NC-SA 4.0 영향) | 최종 녹음으로 교체 |
