#!/usr/bin/env bash
# 실제 OS(X11) 마우스·키보드 이벤트로 입력 검증 — 타이틀 → 새 게임 → 시점 회전 → ESC 일시정지 → 계속하기 → 회전 → 종료
# xvfb + lavapipe(Vulkan) + xdotool. Windows 실기 테스트를 대신하지는 않는다 (같은 Godot 입력 코드 경로 검증용).
# usage: tools/ci/input_test_x11.sh [godot 실행 파일(기본 godot)] [추가 인자...]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-godot}"; shift || true
LOG=/tmp/input_test.log
export DISPLAY=:77
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
Xvfb :77 -screen 0 1280x720x24 >/dev/null 2>&1 &
XPID=$!
sleep 2
rm -f "$HOME"/.local/share/godot/app_userdata/*/save_01.json
if [[ "$BIN" == "godot" ]]; then
  godot --path "$ROOT/game" --rendering-driver vulkan "$@" -- --quality-low --input-probe > "$LOG" 2>&1 &
else
  "$BIN" "$@" -- --quality-low --input-probe > "$LOG" 2>&1 &
fi
GPID=$!
wait_for() { # $1 패턴, $2 초
  for _ in $(seq 1 "$2"); do grep -q "$1" "$LOG" && return 0; sleep 1; done; echo "TIMEOUT waiting: $1"; return 1; }
last() { grep PROBE "$LOG" | tail -1; }
yaw() { last | sed -E 's/.*yaw=([-0-9.]+).*/\1/'; }
pass=0; fail=0
check() { if [[ "$1" == "1" ]]; then echo "  PASS  $2"; pass=$((pass+1)); else echo "  FAIL  $2  ($(last))"; fail=$((fail+1)); fi; }

wait_for "PROBE state=1" 240; sleep 6
check "$(last | grep -q 'mouse_mode=0' && echo 1)" "title: cursor visible on title screen"
xdotool key Return           # 포커스된 '새 게임'
wait_for "PROBE state=2" 300; sleep 8
check "$(last | grep -q 'mouse_mode=2' && echo 1)" "play: cursor captured after new game"
y0=$(yaw)
for i in $(seq 1 10); do xdotool mousemove_relative -- 40 0; sleep 0.3; done
sleep 4
y1=$(yaw)
check "$(python3 -c "print(1 if abs($y1-($y0))>0.2 else 0)")" "play: real mouse X motion rotates view (yaw $y0 -> $y1)"
p0=$(last | sed -E 's/.*pitch=([-0-9.]+).*/\1/')
for i in $(seq 1 6); do xdotool mousemove_relative -- 0 30; sleep 0.3; done
sleep 4
p1=$(last | sed -E 's/.*pitch=([-0-9.]+).*/\1/')
check "$(python3 -c "print(1 if abs($p1-($p0))>0.1 else 0)")" "play: real mouse Y motion pitches view ($p0 -> $p1)"
xdotool key Escape; sleep 5
check "$(last | grep -q 'state=4 paused=true mouse_mode=0' && echo 1)" "pause: ESC pauses, cursor visible"
y2=$(yaw); for i in $(seq 1 5); do xdotool mousemove_relative -- 40 0; sleep 0.3; done; sleep 3; y3=$(yaw)
check "$(python3 -c "print(1 if abs($y3-($y2))<0.001 else 0)")" "pause: mouse does not rotate view while paused"
xdotool key Escape; sleep 6      # ESC로 복귀
check "$(last | grep -q 'state=2 paused=false mouse_mode=2' && echo 1)" "resume(ESC): back to play, cursor recaptured"
xdotool key Escape; sleep 5; xdotool key Return; sleep 6      # 다시 일시정지 → '계속하기'(기본 선택) Enter
check "$(last | grep -q 'state=2 paused=false mouse_mode=2' && echo 1)" "resume(계속하기): back to play, cursor recaptured"
y4=$(yaw); for i in $(seq 1 10); do xdotool mousemove_relative -- -40 0; sleep 0.3; done; sleep 4; y5=$(yaw)
check "$(python3 -c "print(1 if abs($y5-($y4))>0.2 else 0)")" "resume: mouse look works again ($y4 -> $y5)"
# 게임 종료: ESC → 아래로 4칸 → Enter → 확인(예: 왼쪽) → Enter
xdotool key Escape; sleep 4
for i in 1 2 3 4; do xdotool key Down; sleep 0.8; done
xdotool key Return; sleep 3; xdotool key Left; sleep 1; xdotool key Return
for _ in $(seq 1 60); do kill -0 $GPID 2>/dev/null || break; sleep 1; done
if kill -0 $GPID 2>/dev/null; then check 0 "quit: game process exits from pause menu"; kill $GPID; else check 1 "quit: game process exits from pause menu"; fi
kill $XPID 2>/dev/null
echo "== X11 input test: $pass passed, $fail failed =="
