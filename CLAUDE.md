# CLAUDE.md — 녹음되지 않은 목소리 (The Unrecorded Voice)

이 저장소에서 작업하는 AI 세션은 아래 규칙을 따른다. 사용자는 한국어로 소통하며, 모든 보고는 한국어로 작성한다.

## 먼저 읽을 것
1. `docs/README.md` — 문서 색인
2. `docs/requirements/` — 사용자 원문 요구사항 (**수정 금지, 추가만**)
3. `docs/design/open_questions.md` — 미확정 항목 (임의 확정 금지)
4. `docs/production/dev_log.md` — 현재 진행 상황

## 고정된 기술 결정
- 엔진: **Godot 4.7.2-stable**, Forward+, GDScript. 프로젝트 루트는 `game/`
- 3D: **Blender 5.3**, `tools/blender/*.py` 스크립트로 재현 가능하게 제작 → **.gltf(+.bin)** 로 `game/assets/models/`에 익스포트.
  텍스처는 임베드하지 않고 `game/assets/textures/`의 공유 파일을 참조(중복 VRAM 방지). 정적 메시는 재질별 병합, 상호작용 부품(`tuv_keep`)은 피벗 유지
- 플레이 레벨: `game/scenes/levels/lvl_phase01.tscn` (작업실 + 복도 + 계단실, 로딩 없음). 좌표 변환 Blender (x,y,z) → Godot (x,z,-y)
- 사운드는 `game/data/config/audio.json` 의 ID로만 재생(`Sounds` autoload). 음성은 대사 JSON의 경로로만 참조
- 그래픽 확인은 **실제 Godot 화면**으로: `scenes/tests/capture_phase01.tscn` (lavapipe Vulkan + xvfb). 자동 테스트 통과만으로 품질 판단 금지
- 대사·음성·조명 상태는 `game/data/` JSON으로 관리. 코드에 음성 파일 경로 하드코딩 금지
- 테스트: `tools/ci/run_tests.sh` 가 통과해야 커밋한다 (시스템 39 + 레벨 52 + 스토리 36 + 현지화 14). 입력 변경 시 `tools/ci/input_test_x11.sh`(실제 X11 입력)도 실행

## 절대 규칙
- 실행하지 못한 도구를 사용했다고 보고하지 않는다 (예: Blender MCP는 현재 미연결)
- 스토리 진실(정우가 소은을 가뒀다)은 개발용 설정 — 초반 플레이어 노출 콘텐츠에 넣지 않는다
- 소은은 플레이어를 공격하지 않는다. 소은 음성은 괴물처럼 왜곡하지 않는다
- 1998년 공간에 시대 착오 물건(스마트폰, 디지털 도어락, CCTV 모니터, 평면 TV) 금지
- 카툰·과도한 로우폴리·큐브 가구·플라스틱 재질·보라/네온 조명·과도한 노이즈 금지
- 단서에 빛나는 외곽선·위치 아이콘 금지
- 손전등 배터리 무제한 (구조만 존재)
- 유료 결제·서비스 가입은 사용자 확인 후. API 키·비밀번호는 커밋 금지 (`.env`는 무시됨)
- 출처 미확인 이미지는 `refs_local/`(git 제외)에만. 외부 에셋은 `docs/production/asset_license_log.md`에 기록
- 임시 리소스는 `PH_` 접두사 + 라이선스 로그에 PLACEHOLDER
- 바이너리는 Git LFS(`.gitattributes`). 빌드 결과물은 커밋 금지
- ⚠ 현재 Claude 세션의 LFS 업로드가 거부됨 → .blend/.glb/렌더/WAV는 커밋하지 않고 `tools/build_all.sh`로 재생성 (`docs/tech/environment_setup.md` §5)
- 사용자 승인 전에는 다음 PHASE로 넘어가지 않는다 (현재: PHASE 01)

## 구조 메모 (2차 피드백 이후)
- 마우스 캡처·일시정지 상태는 `GameFlow` autoload만 바꾼다. HUD Control은 항상 `MOUSE_FILTER_IGNORE` (조준점이 마우스 입력을 먹던 버그)
- 스토리 이벤트는 `game/data/events/*.json` + `EventDirector` — 코드에 이벤트 하드코딩 금지
- 1인칭 손: `ViewmodelArms` (Blender `tools/blender/build_arms.py`), 손 포즈는 `game/data/characters/hand_poses.json`
- 저장: `SaveGame` autoload (user://save_01.json), 설정: `GameSettings` (user://settings.cfg)

## 명명 규칙
`snake_case`. 접두사: `stu_` 작업실 · `cor_` 상가 복도 · `apt_` 1998 아파트 · `prop_` 소품 · `chr_` 캐릭터 · `gst_` 귀신 · `PH_` 임시 리소스
