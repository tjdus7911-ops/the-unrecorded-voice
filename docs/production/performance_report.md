# 성능 측정 보고 — PHASE 01 (작업실 + 복도 + 계단실)

## 측정 환경 (클라우드)
- 렌더러: Godot 4.7.2 Forward+, Vulkan
- 장치: **llvmpipe (lavapipe, CPU 소프트웨어 렌더링)** — GPU 없음
- 따라서 FPS 수치(약 1 fps)는 **의미 없음**. 드로우콜·폴리곤·메모리 등 장면 구성 지표만 유효합니다.

## 측정값 (lavapipe, 1인칭 작업실 시점)
| 항목 | 값 | 비고 |
|---|---|---|
| 드로우콜 | 약 250 (시점에 따라 250~1000) | 그림자 패스 포함 |
| 프리미티브 | 약 50만 (0.4~1.2 M) | 그림자 패스 포함 |
| 작업실 지오메트리 | 약 16.4만 삼각형 | |
| 렌더 오브젝트 | 263 | |
| 노드 수 | 633 | |
| 비디오 메모리 | 약 1.12 GB | 렌더 타깃·SDFGI(약 300 MB) 포함 |
| 텍스처 메모리 | 약 124 MB(텍스처 자체) | 보고값 988 MB는 렌더 타깃 포함 |
| 물리 프레임 | 약 1.3 ms | |

## 적용한 최적화
- 카세트 750개 → MultiMesh 1회 드로우 (아틀라스 셰이더, INSTANCE_CUSTOM)
- 정적 메시 재질별 병합, 상호작용 부품만 독립 노드
- 공유 텍스처 참조 + VRAM 압축(BC1/BC5) + 밉맵 → 중복 VRAM 2.2 GB 제거
- 단순화 충돌체(-colonly / -convcolonly)
- 작은 물체 그림자 끄기, 조명 거리 페이드, 그래픽 품질 프리셋(낮음/중간/높음)

## 사용자 PC에서 FPS 측정 방법
1. `TheUnrecordedVoice_PHASE01.exe` 가 있는 폴더에서 PowerShell 실행
2. `.\TheUnrecordedVoice_PHASE01.exe -- --benchmark`
3. 6개 시점을 자동으로 돌고 종료 → exe 옆에 `benchmark_*.txt` / `.json` 생성 (FPS·프레임 시간·드로우콜·메모리)
4. 게임 중 **F3** 키로 실시간 성능 오버레이 확인 가능

목표: 중급 GPU(GTX 1660 / RX 5600급) 1080p 높음 프리셋 60 fps. 미달 시 `-- --quality-medium` (SDFGI·SSR 끔) 또는 `-- --quality-low` (SSIL·SSAO까지 끔) 로 실행해 비교해 주세요.
