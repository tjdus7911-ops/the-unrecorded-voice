# Windows 설치·복원·실행 가이드

## 1. 테스트 빌드만 실행 (Godot 설치 불필요)
1. `TheUnrecordedVoice_PHASE01_windows.zip` 압축 해제
2. `TheUnrecordedVoice_PHASE01.exe` 실행 (같은 폴더의 `.pck` 파일 필요)
3. Windows SmartScreen 경고가 뜨면 **추가 정보 → 실행** (서명되지 않은 개발 빌드)
4. 요구: Vulkan 지원 그래픽카드(최근 5년 내 GPU 대부분), 최신 그래픽 드라이버
   - 화면이 안 뜨거나 매우 느리면: 명령 프롬프트에서 `TheUnrecordedVoice_PHASE01.exe -- --quality-medium` (실시간 GI 끔)
   - 그래도 안 되면: `TheUnrecordedVoice_PHASE01.exe --rendering-driver d3d12`
5. 헤드폰 권장 (3D 방향 음향)

### 조작
| 키 | 동작 |
|---|---|
| WASD / 마우스 | 이동 / 시점 |
| Shift | 달리기 (약 6초 후 헐떡임) |
| Ctrl 또는 C | 앉기 |
| E | 조사·조작 (문·스위치·스탠드·서랍·수납장·녹음기·데크·택배 상자·테이프·메모) |
| F | 손전등 (수납장 위 손전등을 먼저 주워야 함) |
| F1 / F3 | 조작 안내 / 성능 표시 (FPS·드로우콜·VRAM) |
| F9 / F10 | (개발용) 위험도 0↔1 — 심장 박동·공포 호흡 / 문 두드리는 소리 |
| Esc | 마우스 잠금 해제 · 조사 화면 닫기 |

### 확인 순서 제안
1. 책상 앞에서 빗소리·컴퓨터 팬·벽시계 초침 소리, 창의 빗물 확인
2. 수납장(문 옆) 위 **손전등** 조사 → E로 가져가기 → F로 켜고 끄기
3. 문 옆 **스위치**로 천장등 켜고 끄기, 책상 **스탠드**도 E로 끄기 → 어두워진 방에서 손전등
4. **책상 아래**에 떨어진 라벨 없는 카세트 찾기 (앉아서 비춰 보기)
5. **문 열기** → 로딩 없이 복도로. 문 앞 **택배 상자** 열기 → 메모·테이프 조사, 테이프 가져가기
6. 책상의 **녹음기**에 테이프 넣고 재생/정지 (임시 TTS 음성 + 테이프 잡음)
7. 복도 끝 **계단실** → 불 꺼진 하행 계단참에서 손전등으로 열쇠 찾기
8. F3로 성능 확인, F9로 심장 박동·공포 호흡 확인

## 2. 프로젝트 복원 (개발용)
1. `the-unrecorded-voice_project_*.zip` 압축 해제 (Git 저장소 포함 — 텍스트는 GitHub와 같은 이력)
2. 필수 설치: Git for Windows(Git LFS 포함), Godot **4.7.2 stable** (표준판, .NET 아님)
3. PowerShell:
   ```powershell
   cd the-unrecorded-voice
   powershell -ExecutionPolicy Bypass -File .\tools\windows\setup.ps1 -GodotPath "C:\Godot\Godot_v4.7.2-stable_win64.exe"
   .\tools\windows\run_tests.ps1 -GodotPath "C:\Godot\Godot_v4.7.2-stable_win64.exe"
   ```
4. Godot 에디터: `game/project.godot` 열기 → F5로 실행 (메인 씬 `scenes/levels/lvl_phase01.tscn`)

## 3. 에셋 재생성 (선택)
Blender 앱 없이 **Python + bpy(Blender 5.3 모듈)** 로 같은 스크립트를 실행한다.
```powershell
winget install Python.Python.3.13
winget install Gyan.FFmpeg
pip install bpy==5.3.0 numpy pillow scipy matplotlib fonttools
.\tools\windows\rebuild_assets.ps1            # -Render 를 붙이면 검토 렌더까지
```
`.blend` 원본을 열어 보려면 Blender **5.3** 앱을 설치한다 (이전 버전에서 열면 데이터 손실 가능).

## 4. Windows 빌드 만들기
Godot 에디터 → 편집기 → 내보내기 템플릿 관리 → 4.7.2 템플릿 다운로드 → 프로젝트 → 내보내기 → "Windows Desktop" → 프로젝트 내보내기.
또는:
```powershell
& $GodotPath --headless --path game --export-release "Windows Desktop" ..\builds\windows\TheUnrecordedVoice_PHASE01.exe
```
