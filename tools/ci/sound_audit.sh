#!/usr/bin/env bash
# 요구사항 20 사운드 전수 검수: 스토리 회귀 테스트를 '실제 오디오 믹싱'으로 다시 돈다.
# 헤드리스(Dummy 오디오)는 소리를 믹싱하지 않아 원샷이 끝나지 않으므로, xvfb + Movie Maker(오디오 포함)로 실행한다.
# 결과: 소리 관련 check_audio 항목 PASS/FAIL + SOUND@<구간> 스냅샷 → /tmp/sound_audit.log, 녹음된 소리 /tmp/sound_audit.avi
# usage: tools/ci/sound_audit.sh [godot-binary]
set -euo pipefail
GODOT="${1:-godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/game"
timeout 1800 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver vulkan --fixed-fps 20 --resolution 320x180 \
  --write-movie /tmp/sound_audit.avi --path . res://scenes/tests/run_story_tests.tscn -- --quality-low 2>&1 | tee /tmp/sound_audit.log | grep -E "PASS|FAIL|SKIP|passed|audio mixing" | grep -E "req20|FAIL|passed|audio mixing"
grep -q "audio mixing: true" /tmp/sound_audit.log || { echo "audio was not mixed"; exit 1; }
grep -q " 0 failed" /tmp/sound_audit.log
