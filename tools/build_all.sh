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
python3 tools/blender/build_arms.py
python3 tools/blender/build_characters.py
python3 tools/blender/build_apartment.py "$@"          # 요구사항 16: 1998 복도식 아파트 (TAPE 01)
python3 tools/blender/render_tape01_photo.py           # TAPE 01 이후 책상 위 사진 (apt_1998 + chr_soeun 필요)
python3 tools/blender/draw_plan.py art/blender/environments/studio/stu_studio.blend art/renders/studio/stu_floorplan.png
python3 tools/audio/make_placeholders.py
python3 tools/audio/make_sfx.py
[ -d "${TUV_SUPERTONIC:-/home/claude/ext_tts/sherpa-onnx-supertonic-3-tts-int8-2026-05-11}" ] && python3 tools/audio/make_voice_supertonic.py || echo "Supertonic 모델 없음 — 음성 생략 (tools/audio/make_voice_supertonic.py 주석 참고)"
python3 tools/audio/export_voice_list.py
python3 tools/audio/export_sfx_list.py
python3 tools/docs/make_layout_maps.py
echo done
