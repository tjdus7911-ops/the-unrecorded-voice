#!/usr/bin/env bash
# 저장소에서 바이너리 산출물 전체 재생성 (bpy·numpy·pillow·scipy·matplotlib·ffmpeg 필요)
# usage: tools/build_all.sh [--render]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 tools/textures/gen_pbr.py
python3 tools/blender/gen_studio_textures.py
python3 tools/textures/gen_prop_textures.py
python3 tools/textures/gen_fx_textures.py
python3 tools/blender/build_props.py "$@"
python3 tools/blender/build_studio.py "$@"
python3 tools/blender/build_corridor.py "$@"
python3 tools/blender/draw_plan.py art/blender/environments/studio/stu_studio.blend art/renders/studio/stu_floorplan.png
python3 tools/audio/make_placeholders.py
python3 tools/audio/make_sfx.py
[ -d "${TUV_TTS_MODEL:-/opt/tts/vits-mimic3-ko_KO-kss_low}" ] && python3 tools/audio/make_voice_samples.py || echo "TTS 모델 없음 — 음성 샘플 생략"
echo done
