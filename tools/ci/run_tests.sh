#!/usr/bin/env bash
# 헤드리스 자동 테스트: 임포트 → 시스템 테스트. 실패 시 종료 코드 1.
# usage: tools/ci/run_tests.sh [godot-binary]
set -euo pipefail
GODOT="${1:-godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# 임시 음원이 없으면 생성
ls "$ROOT"/game/assets/audio/breathing/PH_*.wav >/dev/null 2>&1 || python3 "$ROOT/tools/audio/make_placeholders.py"
# 작업실 GLB가 없으면 생성 (bpy 필요)
[ -f "$ROOT/game/assets/models/environments/stu_studio.gltf" ] || "$ROOT/tools/build_all.sh"
cd "$ROOT/game"
"$GODOT" --headless --import --path . >/dev/null 2>&1 || true
"$GODOT" --headless --fixed-fps 60 --path . res://scenes/tests/run_tests.tscn
"$GODOT" --headless --fixed-fps 60 --path . res://scenes/tests/run_phase01_tests.tscn
"$GODOT" --headless --fixed-fps 60 --path . res://scenes/tests/run_story_tests.tscn
