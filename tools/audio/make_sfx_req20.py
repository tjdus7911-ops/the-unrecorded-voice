#!/usr/bin/env python3
"""요구사항 20 효과음 (자체 DSP 합성, 외부 음원 없음) — audio.json에 병합한다 (다른 항목은 그대로 둔다).
- sfx_tape_start_crackle (×3): 녹음기 PLAY 직후 테이프 도입부의 짧은 '지지직' (0.65~0.85초).
  헤드가 테이프에 닿는 순간의 잡음·작은 튐 몇 개 → 끝 0.12초 동안 완전히 0으로 줄어든다 (대사 시작 전에 반드시 끝남).
usage: python3 tools/audio/make_sfx_req20.py
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_sfx as S  # noqa: E402

rng = np.random.default_rng(2020)
SR = S.SR


def tape_start_crackle():
    d = rng.uniform(0.65, 0.85)
    n = int(d * SR)
    t = np.arange(n) / SR
    hiss = S.hp(S.pink(d), 1500)[:n] * 0.55
    # 테이프 표면 잡음: 불규칙하게 오르내림 (빠르게 바뀌는 게이트)
    flutter = 0.55 + 0.45 * np.convolve(rng.uniform(0, 1, n), np.ones(int(SR * 0.025)) / int(SR * 0.025), "same")
    out = hiss * flutter
    # 작은 튐(크래클) 몇 개
    for _ in range(rng.integers(6, 11)):
        at = int(rng.uniform(0.02, d - 0.18) * SR)
        ln = int(rng.uniform(0.002, 0.007) * SR)
        click = rng.normal(0, 1, ln) * np.hanning(ln) * rng.uniform(0.6, 1.3)
        out[at:at + ln] += S.hp(click, 900)[:ln] if hasattr(S, "hp") else click
    # 헤드가 닿는 순간의 낮은 '툭'
    th = int(0.03 * SR)
    out[:th] += np.sin(2 * np.pi * 90 * t[:th]) * np.hanning(th * 2)[:th][::-1] * 0.35
    env = np.ones(n)
    a = int(0.012 * SR)
    env[:a] = np.linspace(0, 1, a)
    r = int(0.12 * SR)
    env[-r:] = np.linspace(1, 0, r) ** 2
    out = out * env
    out[-int(0.01 * SR):] = 0.0          # 마지막 10 ms는 완전 무음
    return out


def main():
    reg = {}
    reg["sfx_tape_start_crackle"] = {
        "files": [S.save("sfx", f"sfx_tape_start_crackle_{i}", tape_start_crackle(), 0.55) for i in range(3)],
        "note": "요구사항 20: PLAY 직후 0.65~0.85초 — 끝난 뒤에 첫 대사가 시작된다 (prologue_story tape_sequence)"}
    p = S.GAME / "data" / "config" / "audio.json"
    cfg = json.loads(p.read_text("utf-8"))
    cfg["sounds"].update(reg)
    p.write_text(json.dumps(cfg, ensure_ascii=False, indent=1), "utf-8")
    for k, v in reg.items():
        print(f"  {k:24s} {len(v['files'])}")


if __name__ == "__main__":
    main()
