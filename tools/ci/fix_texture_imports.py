#!/usr/bin/env python3
"""Godot 텍스처 임포트 설정 보정: *_normal.* 은 노멀맵 압축(RGTC/BC5), *_orm.* 은 거칠기 채널 지정 없이 VRAM 압축.
Godot이 한 번 임포트해 .import 파일을 만든 뒤 실행하고, 다시 --import 한다."""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "game" / "assets" / "textures"
n = 0
for imp in root.rglob("*.import"):
    s = imp.read_text("utf-8")
    o = s
    s = re.sub(r"compress/mode=\d", "compress/mode=2", s)
    s = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", s)
    if "_normal." in imp.name:
        s = re.sub(r"compress/normal_map=\d", "compress/normal_map=1", s)
    if s != o:
        imp.write_text(s, "utf-8")
        n += 1
print("patched", n)
