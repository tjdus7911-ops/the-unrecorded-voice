# 녹음되지 않은 목소리 — The Unrecorded Voice

1인칭 3D 심리 공포 · 미스터리 · 추리 · 탐험 게임 (PC / Steam 목표, 한국어 우선)

1998년, 재개발을 앞둔 복도식 아파트에서 아홉 살 소녀가 실종된다.
28년 후, 음성 복원 전문가 서정우에게 발신인 없는 택배 상자가 도착한다. 상자 안에는 일곱 개의 카세트테이프.

## 현재 단계
**PHASE 01 — 공간 제작** (작업실 · 작업실 외부 복도 · 1998년 아파트 복도/계단 + 손전등·호흡 시스템 기반)

## 기술 스택
- Godot **4.7.2-stable** (Forward+, GDScript) — `game/`
- Blender **5.3** (스크립트 기반 제작) — `art/blender/`, `tools/blender/`
- Git LFS — 모든 바이너리 에셋

## 빠른 시작
```
git lfs install
git clone https://github.com/tjdus7911-ops/the-unrecorded-voice.git
```
Godot 4.7.2로 `game/project.godot`를 열고 F5. 자동 테스트: `tools/ci/run_tests.sh` (Windows: `tools\ci\run_tests.bat`).

자세한 내용: [`docs/README.md`](docs/README.md) · 설치 안내: [`docs/tech/environment_setup.md`](docs/tech/environment_setup.md)

> ⚠ `docs/requirements/`와 `docs/design/`에는 결말을 포함한 개발용 스토리 설정이 있습니다.
