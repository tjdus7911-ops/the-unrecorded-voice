#!/usr/bin/env bash
# 전체 보관본 ZIP: Git 저장소(.git 포함) + 스크립트로 생성된 모든 바이너리(.blend, .gltf/.bin, 텍스처, 음원, 렌더)
# 제외: game/.godot(임포트 캐시, 재생성됨), builds/(빌드는 별도 ZIP), refs_local/(출처 미확인 레퍼런스)
# usage: tools/ci/package_archive.sh <out.zip>
set -euo pipefail
OUT="${1:?out.zip}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$(dirname "$ROOT")"
NAME="$(basename "$ROOT")"
rm -f "$OUT"
zip -q -r -9 "$OUT" "$NAME" -x "$NAME/game/.godot/*" "$NAME/builds/*" "$NAME/refs_local/*.png" "$NAME/**/__pycache__/*"
ls -la "$OUT"
