#!/usr/bin/env bash
# 저장소에서 바이너리 산출물 전체 재생성: 텍스처 → .blend/GLB → 평면도 → 임시 음원
# usage: tools/build_all.sh [--render]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 tools/audio/make_placeholders.py
python3 tools/blender/gen_studio_textures.py
python3 tools/blender/build_studio.py "$@"
python3 tools/blender/draw_plan.py art/blender/environments/studio/stu_studio.blend art/renders/studio/stu_floorplan.png
echo "done"
