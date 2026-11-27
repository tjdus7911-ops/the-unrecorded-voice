#!/usr/bin/env python3
"""요구사항 16 산출물 — 효과음 목록 + 라이선스 (자동 생성).
입력: game/data/config/audio.json, game/data/events/*.json, game/scripts/**/*.gd, game/scenes/**/*.gd
출력: docs/production/sfx_list.md
모든 PH_* 음원은 자체 DSP 합성(임시), TTS_* 는 Supertonic 3(OpenRAIL-M) 합성 + DSP. 외부 라이선스 음원 없음."""
import json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
G = ROOT / "game"
snd = json.loads((G / "data/config/audio.json").read_text("utf-8"))["sounds"]
ev_use = {}
for f in sorted((G / "data/events").glob("*.json")):
    for e in json.loads(f.read_text("utf-8"))["events"]:
        for a in e.get("actions", []):
            sid = a.get("id")
            if sid in snd:
                ev_use.setdefault(sid, []).append(e["id"])
code_use = {}
for f in list((G / "scripts").rglob("*.gd")) + list((G / "scenes").rglob("*.gd")):
    if "/tests/" in str(f):
        continue
    txt = f.read_text("utf-8")
    for sid in snd:
        if re.search(r'"%s"' % re.escape(sid), txt):
            code_use.setdefault(sid, []).append(f.stem)
def lic(files):
    names = " ".join(files)
    if "TTS_" in names:
        return "THIRD_PARTY 생성물 — Supertonic 3 (OpenRAIL-M, 상업 이용 가능) 음성 합성 + 자체 DSP", "⚠ 임시 (아이 웃음·놀이터 — 실제 녹음/라이선스 음원으로 교체 권장)"
    if "PH_" in names:
        return "ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`)", "PLACEHOLDER (교체 예정)"
    return "확인 필요", ""
rows = []
for sid, d in sorted(snd.items()):
    files = [Path(p).name for p in d.get("files", [])]
    l, st = lic(files)
    rows.append((sid, ", ".join(files[:3]) + (" …" if len(files) > 3 else ""), "루프" if d.get("loop") else "1회",
                 ", ".join(sorted(set(ev_use.get(sid, [])))) or "—", ", ".join(sorted(set(code_use.get(sid, [])))) or "—", l, st))
md = ["# 효과음 목록 · 라이선스 (요구사항 16 산출물) — 자동 생성: `tools/audio/export_sfx_list.py`", "",
      "- 모든 효과음은 `game/data/config/audio.json`의 ID로만 재생한다 (`Sounds` autoload). 파일 교체 시 코드 수정 없음.",
      "- 외부(구매·다운로드) 음원은 **사용하지 않았다**. 전부 자체 합성(PH_) 또는 Supertonic 3 TTS 합성(TTS_)이며 `docs/production/asset_license_log.md`에 기록.",
      "- 공포 효과음은 자막 여부와 관계없이 항상 실제 소리로 재생된다 (요구사항 15).", "",
      "| ID | 파일 | 재생 | 사용 이벤트(JSON) | 사용 코드 | 라이선스 / 출처 | 상태 |", "|---|---|---|---|---|---|---|"]
for r in rows:
    md.append("| " + " | ".join(str(v).replace("|", "/") for v in r) + " |")
(ROOT / "docs/production/sfx_list.md").write_text("\n".join(md) + "\n", "utf-8")
print(len(rows), "sfx ->", ROOT / "docs/production/sfx_list.md")
