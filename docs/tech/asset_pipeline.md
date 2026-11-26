# Blender → Godot 에셋 파이프라인

## 버전 고정
- Blender **5.3** (`.blend`는 5.3에서 저장됨 — 이전 버전에서 열면 데이터 손실 가능)
- Godot **4.7.2-stable**
- 단위: 1 Blender unit = 1 m, Z-up(Blender) → Y-up(Godot, glTF 익스포터가 자동 변환)

## 스크립트 기반 제작
공간과 소품은 `tools/blender/` 의 Python 스크립트로 **재현 가능하게** 생성한다.
스크립트 → `.blend` 저장 → GLB 익스포트 → 렌더 순서. 수작업 수정이 필요하면 `.blend`에서 직접 하고, 그 사실을 개발 로그에 기록한다.

```
python3 tools/blender/build_studio.py        # .blend + GLB + 렌더 생성 (bpy 모듈)
blender -b -P tools/blender/build_studio.py  # Blender 앱 설치 PC에서 동일 실행
```

## 충돌 영역 (Godot 임포트 힌트)
| 메시 이름 접미사 | Godot 결과 |
|---|---|
| `-col` | 메시 + 트라이메시 정적 충돌 |
| `-colonly` | 보이지 않는 충돌 전용 (벽·바닥 단순 박스 권장) |
| `-convcolonly` | 볼록 충돌 전용 (가구) |
| `-noimp` | 임포트 제외 (작업용 보조 메시) |

시각용 고밀도 메시에 직접 충돌을 걸지 않고, **단순화한 `-colonly` 박스**를 별도로 둔다.

## 애니메이션 가능한 오브젝트
- 문·서랍·녹음기 버튼·카세트 덱 뚜껑·손전등 스위치는 **별도 오브젝트**로 분리하고 회전/이동 축에 피벗(원점)을 맞춘다.
  - 문: 원점 = 경첩 축 하단 / 서랍: 원점 = 서랍 전면 중앙, 로컬 +Y로 인출
- 계층: `door_frame` ▸ `door_leaf` ▸ `door_handle` 처럼 부모-자식으로 묶어 GLB에 그대로 보존.

## 재질
- Principled BSDF 기반 PBR (Base Color, Roughness, Metallic, Normal). glTF로 넘어가는 노드만 사용.
- 절차적 텍스처는 게임용으로 **이미지 베이크** 후 사용 (`art/textures_source/` → `game/assets/textures/`).
- 텍셀 밀도 기준: 근접 소품 1024px/m, 건축 512px/m.

## LOD
- 1차: 소품은 Godot 자동 메시 LOD(임포트 시 생성) 사용.
- 2차: 아파트 외관처럼 큰 메시는 Blender에서 `_LOD1`, `_LOD2` 수동 제작.

## 검토용 렌더
- Cycles CPU, 동일 `.blend`의 서로 다른 카메라 (`CAM_plan`, `CAM_top`, `CAM_entry`, `CAM_front`, `CAM_left`, `CAM_right`, `CAM_fps`).
- FPS 카메라: 눈높이 1.62 m, 세로 화각 70°, Godot 플레이어 카메라와 동일 값.
- 출력: `art/renders/<space>/<space>_<view>.png`
