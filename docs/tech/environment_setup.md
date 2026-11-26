# 개발 환경 구성 및 점검 결과

> 점검일: 2026-11-26. **실제로 확인한 것과 확인하지 못한 것을 구분**해 기록한다.

## 1. 점검 결과 요약

| 항목 | 클라우드 개발 환경 (Claude 작업 공간, Linux) | 사용자 PC (Windows, 장치명 `pm`) |
|---|---|---|
| GitHub 저장소 연결 | ✅ `tjdus7911-ops/the-unrecorded-voice` 클론·푸시 권한 확인 | ⬜ 미클론 (아래 설치 안내) |
| Blender | ✅ **bpy 5.3.0** (Blender를 Python 모듈로 설치) — 모델링·`.blend` 저장·GLB 익스포트·Cycles CPU 렌더 실제 실행 확인 | ❓ **확인 불가** — PC 폴더가 이 세션에 연결되어 있지 않아 설치 여부를 볼 수 없음 |
| Blender Python API | ✅ `import bpy` 정상, Cycles·glTF 애드온 동작 | ❓ |
| Blender CLI (`blender -b -P`) | ⚠ 앱 바이너리 없음 — 대신 `python3 script.py`(bpy 모듈)로 동일 스크립트 실행 | ❓ |
| EEVEE 렌더 | ⚠ GPU 없음(EGL 오류) → 검토 렌더는 **Cycles CPU** 사용 | — |
| Blender MCP | ❌ **연결 안 됨** — 이 세션에 Blender MCP 서버 없음, PC의 로컬 MCP 서버 목록도 비어 있음 | ❌ |
| Godot | ✅ **4.7.2-stable** (GitHub 공식 릴리스) — 헤드리스 임포트·자동 테스트 실행 확인 | ⬜ 미설치 여부 확인 불가 |
| Godot 렌더 (스크린샷) | ⚠ Vulkan 없음 → Xvfb + OpenGL(Compatibility) 폴백으로 캡처. 최종 화질 판단은 PC Forward+에서 | — |
| Git LFS | ✅ 3.x, 저장소 로컬 설정 완료 | ⬜ |
| Unity / Unreal | ❌ 설치하지 않음 (검토만, `engine_selection.md`) | — |
| GPU | 없음 (CPU 2코어, RAM 7GB) | ❓ |

**보고 원칙**: 위 표에서 ✅만 실제 사용한 도구다. Blender MCP·Windows Blender는 사용하지 않았다.

## 2. 클라우드 환경 재현 방법 (Claude 세션용)

```bash
pip install --break-system-packages bpy==5.3.0            # Blender 5.3 Python 모듈
mkdir -p /opt/godot47 && curl -sL -o /opt/godot47/g.zip \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip -oq /opt/godot47/g.zip -d /opt/godot47
ln -sf /opt/godot47/Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot
tools/ci/run_tests.sh          # 시스템 테스트
```

## 3. 사용자 PC(Windows) 설치 안내

모두 무료. 결제·라이선스 구매 항목 없음.

| 도구 | 버전 | 용도 | 받는 곳 |
|---|---|---|---|
| Git for Windows | 최신 | 저장소 클론 (Git LFS 포함) | git-scm.com |
| Godot Engine | **4.7.2 stable** (표준판, .NET 아님) | 게임 실행·편집 | godotengine.org/download |
| Blender | **5.3** | `.blend` 열기·수정 (버전 일치 필수) | blender.org/download |
| (선택) VS Code + godot-tools 확장 | | 스크립트 편집 | |

```powershell
git lfs install
git clone https://github.com/tjdus7911-ops/the-unrecorded-voice.git
cd the-unrecorded-voice
# Godot 실행 → Import → game/project.godot 선택 → F5 실행
# 또는 자동 테스트:
tools\ci\run_tests.bat "C:\경로\Godot_v4.7.2-stable_win64.exe"
```

Blender 설치 확인: PowerShell에서 `& "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" --version`

### Blender MCP를 쓰고 싶다면 (선택)
Claude 데스크톱 앱에서 Blender를 실시간으로 조작하려면 PC에 Blender + Blender MCP 애드온(커뮤니티 오픈소스) + 데스크톱 앱 MCP 설정이 필요하다. 현재 파이프라인은 **스크립트 기반**이라 MCP 없이도 같은 결과물을 만들 수 있으므로 필수가 아니다. 설치를 원하면 별도로 안내한다.

## 4. 테스트 빌드 실행 (PC)

`game/project.godot`의 메인 씬은 현재 **시스템 테스트베드**(`scenes/tests/dev_testbed.tscn`)다.

| 키 | 동작 |
|---|---|
| WASD | 이동 |
| Shift | 달리기 (약 6초 후 탈진 → 헐떡임) |
| Ctrl / C | 앉기 |
| 마우스 | 시점 |
| E | 조사·획득 (테이블 위 손전등 → 어두운 방 바닥 카세트) |
| F | 손전등 켜기/끄기 (획득 후) |
| F9 | (디버그) 위험도 0↔1 — 심장 박동·공포 호흡 확인 |
| Esc | 마우스 잠금 해제 |
