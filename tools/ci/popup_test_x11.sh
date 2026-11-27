#!/usr/bin/env bash
# P0 (2026-11-27) 팝업 실제 입력 검증 — 저장이 있는 상태로 타이틀 → '새 게임' → 확인 팝업이 화면 중앙에 뜨는지,
# 실제 X11 마우스 클릭으로 '아니오'·'예'가 눌리는지. 창 크기 3종(1600×900 기본, 1280×720, 1920×1080 전체 화면 크기).
# usage: tools/ci/popup_test_x11.sh [godot 실행 파일(기본 godot)]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-godot}"
export DISPLAY=:78
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
Xvfb :78 -screen 0 1920x1080x24 >/dev/null 2>&1 &
XPID=$!
sleep 2
SAVE_DIR="$HOME/.local/share/godot/app_userdata/녹음되지 않은 목소리 (The Unrecorded Voice)"
SHOTS="${SHOTS:-/tmp/popup_test}"
mkdir -p "$SHOTS"
pass=0; fail=0
check() { if [[ "$1" == "1" ]]; then echo "  PASS  $2"; pass=$((pass+1)); else echo "  FAIL  $2  ($(grep PROBE "$LOG" | tail -1))"; fail=$((fail+1)); fi; }
for RES in 1600x900 1280x720 1920x1080; do
  W=${RES%x*}; H=${RES#*x}
  LOG=/tmp/popup_test_$RES.log
  mkdir -p "$SAVE_DIR"
  printf '{"version":%s,"checkpoint":"game_start","label":"게임 시작","time":0,"state":{"done":[]}}' 1 > "$SAVE_DIR/save_01.json"
  if [[ "$BIN" == "godot" ]]; then
    godot --path "$ROOT/game" --rendering-driver vulkan --resolution $RES --position 0,0 -- --quality-low --input-probe > "$LOG" 2>&1 &
  else
    "$BIN" --resolution $RES --position 0,0 -- --quality-low --input-probe > "$LOG" 2>&1 &
  fi
  GPID=$!
  for _ in $(seq 1 240); do grep "PROBE state=1" "$LOG" | tail -1 | grep -q "focus=이어하기\|focus=새 게임" && break; sleep 1; done; sleep 3
  xdotool mousemove 960 540; sleep 0.3; xdotool key Up; sleep 0.6; xdotool key Return; sleep 4                       # 포커스된 '새 게임' → 저장이 있으므로 확인 팝업
  ffmpeg -loglevel error -y -f x11grab -video_size ${W}x${H} -i :78 -frames:v 1 "$SHOTS/popup_$RES.png"
  check "$(grep PROBE "$LOG" | tail -1 | grep -q 'popups=1' && echo 1)" "[$RES] new-game confirm popup is open"
  # 카드 중앙 아래쪽 두 버튼: 1920×1080 기준 (870,609)=예, (1050,609)=아니오 → 창 크기 비율로
  NX=$(python3 -c "print(int(1050*$W/1920))"); NY=$(python3 -c "print(int(609*$H/1080))")
  YX=$(python3 -c "print(int(870*$W/1920))")
  xdotool mousemove $NX $NY; sleep 1.0; xdotool click 1
  for _ in $(seq 1 10); do grep PROBE "$LOG" | tail -1 | grep -q 'popups=0' && break; sleep 1; done
  ffmpeg -loglevel error -y -f x11grab -video_size ${W}x${H} -i :78 -frames:v 1 "$SHOTS/after_no_$RES.png"
  check "$(grep PROBE "$LOG" | tail -1 | grep -q 'state=1 .*popups=0' && echo 1)" "[$RES] real mouse click on '아니오' closes it (stays on title)"
  xdotool key Up; sleep 0.6; xdotool key Return; sleep 4
  check "$(grep PROBE "$LOG" | tail -1 | grep -q 'state=1 .*popups=1' && echo 1)" "[$RES] popup opens again (no duplicate, one popup)"
  xdotool mousemove $YX $NY; sleep 0.5; xdotool click 1
  for _ in $(seq 1 200); do grep PROBE "$LOG" | tail -1 | grep -q 'state=2' && break; sleep 1; done; sleep 4
  check "$(grep PROBE "$LOG" | tail -1 | grep -q 'state=2 paused=false mouse_mode=2 popups=0' && echo 1)" "[$RES] real mouse click on '예' starts the game, cursor captured"
  kill $GPID 2>/dev/null; sleep 2
done
kill $XPID 2>/dev/null
echo "== popup X11 test: $pass passed, $fail failed =="
[ $fail -eq 0 ]
