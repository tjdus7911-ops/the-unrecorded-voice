#!/usr/bin/env python3
"""임시(Placeholder) 음원 생성기 — The Unrecorded Voice

실제 성우 녹음·최종 사운드가 준비되기 전까지 시스템 테스트용으로 쓰는 합성 음원을 만든다.
모든 출력 파일명은 PH_ 로 시작하며 docs/production/asset_license_log.md 에 PLACEHOLDER로 기록된다.
최종 에셋은 같은 경로의 JSON(game/data/config/*.json)만 바꿔 교체한다.

usage: python3 tools/audio/make_placeholders.py
"""
import json
import wave
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parents[2] / "game"
AUD = ROOT / "assets" / "audio"
rng = np.random.default_rng(1998)


def write_wav(path: Path, x: np.ndarray) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.clip(x, -1, 1)
    pcm = (x * 32767 * 0.9).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return "res://" + str(path.relative_to(ROOT)).replace("\\", "/")


def one_pole_lp(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def breath_noise(n, bright):
    w = rng.standard_normal(n)
    lo = one_pole_lp(w, 300 + 900 * bright)
    hi = one_pole_lp(w, 2500 + 3500 * bright)
    return (hi - lo * 0.6) * 0.8


def envelope(n, attack, release, curve=1.6):
    t = np.linspace(0, 1, n)
    env = np.minimum(t / max(attack, 1e-3), 1) * np.minimum((1 - t) / max(release, 1e-3), 1)
    return np.clip(env, 0, 1) ** curve


def breath_cycle(inhale, exhale, gain, bright, tremble=0.0, pause=0.0):
    ni, ne = int(inhale * SR), int(exhale * SR)
    a = breath_noise(ni, bright) * envelope(ni, 0.55, 0.25) * gain * 0.7
    b = breath_noise(ne, bright * 0.8) * envelope(ne, 0.15, 0.6) * gain
    if tremble:
        t = np.arange(ne) / SR
        b *= 1 - tremble * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t))
    gap = np.zeros(int(0.06 * SR))
    tail = np.zeros(int(pause * SR))
    return np.concatenate([a, gap, b, tail])


STATES = {
    #           inhale exhale gain bright tremble
    "calm":      (1.5, 2.0, 0.18, 0.1, 0.0),
    "walk":      (1.2, 1.6, 0.24, 0.2, 0.0),
    "run":       (0.55, 0.65, 0.55, 0.6, 0.0),
    "exhausted": (0.42, 0.55, 0.8, 0.8, 0.0),
    "fear":      (0.7, 0.9, 0.42, 0.5, 0.35),
}


def main():
    cfg = {"_note": "PLACEHOLDER 음원. 최종 성우 녹음으로 교체 시 이 목록만 변경.", "loops": {}, "oneshots": {}}
    for state, (i, e, g, br, tr) in STATES.items():
        files = []
        for k in range(3):
            j = rng.uniform(0.9, 1.12)
            x = breath_cycle(i * j, e * rng.uniform(0.9, 1.12), g * rng.uniform(0.85, 1.1), br, tr)
            files.append(write_wav(AUD / "breathing" / f"PH_breath_{state}_{k + 1:02d}.wav", x))
        cfg["loops"][state] = files
    # one-shots
    gasp = breath_noise(int(0.45 * SR), 0.9) * envelope(int(0.45 * SR), 0.1, 0.5) * 0.9
    relief = breath_cycle(0.9, 2.4, 0.4, 0.25)
    exhale_hard = breath_noise(int(0.9 * SR), 0.9) * envelope(int(0.9 * SR), 0.05, 0.7) * 1.0
    cfg["oneshots"]["gasp"] = [write_wav(AUD / "breathing" / "PH_breath_gasp_01.wav", gasp)]
    cfg["oneshots"]["relief"] = [write_wav(AUD / "breathing" / "PH_breath_relief_01.wav", relief)]
    cfg["oneshots"]["exhale_hard"] = [write_wav(AUD / "breathing" / "PH_breath_exhale_hard_01.wav", exhale_hard)]
    (ROOT / "data" / "config" / "breathing.json").write_text(json.dumps(cfg, ensure_ascii=False, indent=2), "utf-8")

    # heartbeat: lub-dub
    beats = []
    for k in range(3):
        n = int(0.55 * SR)
        t = np.arange(n) / SR
        def thump(t0, f, amp):
            tt = np.clip(t - t0, 0, None)
            return amp * np.sin(2 * np.pi * f * tt) * np.exp(-tt * 22) * (t >= t0)
        x = thump(0.0, 48 + k * 2, 1.0) + thump(0.17 + 0.01 * k, 58, 0.6)
        x = one_pole_lp(x, 180) * 2.5
        beats.append(write_wav(AUD / "heartbeat" / f"PH_heartbeat_{k + 1:02d}.wav", x))
    (ROOT / "data" / "config" / "heartbeat.json").write_text(
        json.dumps({"_note": "PLACEHOLDER", "beats": beats}, ensure_ascii=False, indent=2), "utf-8")

    # flashlight click on/off
    for name, f in (("on", 3200), ("off", 2600)):
        n = int(0.06 * SR)
        t = np.arange(n) / SR
        x = (rng.standard_normal(n) * 0.5 + np.sin(2 * np.pi * f * t)) * np.exp(-t * 140)
        write_wav(AUD / "sfx" / f"PH_flashlight_click_{name}.wav", x * 0.8)
    print("placeholders written")


if __name__ == "__main__":
    main()
