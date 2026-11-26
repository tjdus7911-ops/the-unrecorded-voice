#!/usr/bin/env bash
# 손·팔 검토 캡처 (실제 Godot Forward+ 렌더, lavapipe). usage: tools/ci/hands_lab.sh <out_dir> [--plain]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-/tmp/hands}"; shift || true
rm -rf "$OUT"; mkdir -p "$OUT"
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path "$ROOT/game" --rendering-driver vulkan --resolution 1280x720 res://scenes/tests/hands_lab.tscn -- --out "$OUT" --keep-window "$@" 2>&1 | grep -E "SHOT|SCRIPT ERROR|Parse Error"
python3 - "$OUT" <<'PY'
import sys, glob
from PIL import Image
fs = sorted(glob.glob(sys.argv[1] + "/*.png"))
m = Image.new("RGB", (1920, 360 * ((len(fs) + 2) // 3)))
for i, f in enumerate(fs):
    m.paste(Image.open(f).convert("RGB").resize((640, 360)), ((i % 3) * 640, (i // 3) * 360))
m.save(sys.argv[1] + "/_sheet.jpg", quality=88)
PY
