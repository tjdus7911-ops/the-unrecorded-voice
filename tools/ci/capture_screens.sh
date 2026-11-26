#!/usr/bin/env bash
# 테스트베드 렌더링 스크린샷 (Linux: xvfb 필요 / Windows: Godot 에디터에서 capture_screens.tscn 실행)
set -euo pipefail
GODOT="${1:-godot}"; OUT="${2:-$(pwd)/art/renders/testbed}"
cd "$(dirname "$0")/../../game"
xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --fixed-fps 60 --resolution 1280x720 res://scenes/tests/capture_screens.tscn -- "$OUT"
