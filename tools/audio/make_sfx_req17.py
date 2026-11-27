#!/usr/bin/env python3
"""요구사항 17 효과음 재제작 (자체 DSP 합성, 외부 음원 없음) — audio.json에 병합한다 (다른 항목은 그대로 둔다).
- sfx_knock_hit (×8): 사람이 손가락 마디로 사무실 철문(속이 빈 강판 문)을 두드리는 한 번의 타격. 게임이 3번을 강도·간격을 달리해 조합
- sfx_knock_late_hit (×5): 후반 초자연 노크 — 더 느리고 낮고 눌린 소리 (초반 노크와 구분)
- sfx_door_slam (×3): 도어클로저 달린 철제 출입문이 세게 닫힘 (바람 → 문짝·문틀 충돌 저음 → 금속 울림 짧게) — 폭발음 아님, 리미터로 클리핑 방지
- sfx_latch (×3): 잠금장치가 걸리는 짧은 금속음
- sfx_object_drop: 복도 끝에서 금속 쓰레받기/깡통이 떨어져 구르는 소리
- sfx_tape_glitch (×4): 불규칙한 카세트 잡음 (늘어짐·드롭아웃·헤드 잡음) — 추격 중
- amb_apt_1998: 1998 아파트 복도 늦은 오후 환경음 (먼 차 소리·바람·먼 아이들 소리 대신 생활 소음 웅성임)
usage: python3 tools/audio/make_sfx_req17.py
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_sfx as S  # noqa: E402

rng = np.random.default_rng(1717)
SR = S.SR


def soft_limit(x, ceiling=0.85):
    """부드러운 리미터: 큰 충격음의 클리핑 방지 (tanh 곡선)."""
    m = np.max(np.abs(x)) + 1e-9
    y = np.tanh(x / m * 1.6) / np.tanh(1.6)
    return y * ceiling


def knock_hit(strength=1.0, hollow=1.0):
    """손가락 마디 노크: 아주 짧은 접촉(뼈·피부) + 강판 문짝 저음 '통' (속이 빈 문 공명) + 짧은 금속 성분. 잔향 거의 없음."""
    d = 0.42
    f0 = rng.uniform(118, 138)                         # 문짝 기본 공명 (속빈 강판 문)
    body = S.modal([f0, f0 * 1.9, f0 * 3.1, f0 * 4.6], [0.06, 0.04, 0.025, 0.015], [1.0, 0.45, 0.22, 0.1], d) * hollow
    knuckle = S.bp(S.noise(d), 700, 2600) * S.env_exp(d, 0.004, 0.0006) * 0.9 * rng.uniform(0.8, 1.1)
    thump = S.lp(S.noise(d), 240) * S.env_exp(d, 0.012, 0.001) * 1.4
    ring = S.modal([rng.uniform(980, 1150), rng.uniform(1700, 1900)], [0.03, 0.018], [0.12, 0.06], d)
    x = S.mix(body * 0.9, knuckle, thump, ring) * S.env_exp(d, 0.09)
    return x * strength


def knock_late_hit():
    """초자연 노크: 느리게, 손바닥 아래쪽으로 누르듯 — 낮고 둔하고 길게 남는다."""
    d = 0.9
    f0 = rng.uniform(88, 100)
    body = S.modal([f0, f0 * 2.1, f0 * 3.3], [0.16, 0.09, 0.05], [1.0, 0.4, 0.15], d)
    press = S.lp(S.noise(d), 160) * S.env_exp(d, 0.05, 0.02) * 1.3
    return S.mix(body, press) * S.env_exp(d, 0.3)


def door_slam(strength=1.0):
    """철제 출입문 쾅: 닫히는 바람(짧음) → 문짝이 문틀에 부딪히는 묵직한 저음 + 짧은 금속 울림 + 문틀 떨림.
    충격 시점 = 0.14초 (게임은 문 애니메이션이 닫히는 프레임에서 이 소리의 0.14초 지점이 맞도록 재생)."""
    out = np.zeros(int(1.8 * SR))
    S.place(out, S.bp(S.noise(0.16), 120, 900) * np.linspace(0, 1, int(0.16 * SR)) ** 2 * 0.25, 0.0)
    imp = 0.14
    low = S.modal([54, 92, 141, 212], [0.32, 0.2, 0.12, 0.08], [1.0, 0.7, 0.45, 0.25], 1.5)
    hit = S.lp(S.noise(0.6), 180) * S.env_exp(0.6, 0.045, 0.0008) * 2.2
    slap = S.bp(S.noise(0.2), 400, 2500) * S.env_exp(0.2, 0.012, 0.0005) * 0.8
    metal = S.modal([rng.uniform(640, 700), rng.uniform(1230, 1320), rng.uniform(2050, 2200)], [0.09, 0.06, 0.035], [0.35, 0.22, 0.12], 0.8)
    rattle = np.zeros(int(0.5 * SR))
    for k in range(5):
        S.place(rattle, S.click(0.03, 2200 + 300 * k, 6, 700, 0.25 / (k + 1)), 0.03 + k * rng.uniform(0.035, 0.06))
    S.place(out, S.mix(low * 0.9, hit, slap) * strength, imp)
    S.place(out, metal * strength, imp + 0.003)
    S.place(out, rattle, imp + 0.02)
    return soft_limit(out, 0.85)


def latch():
    """잠금장치 걸림: 짧은 금속 '철컥' (스프링 래치 + 볼트)."""
    out = np.zeros(int(0.35 * SR))
    a = S.mix(S.modal([rng.uniform(1900, 2100), rng.uniform(3300, 3600)], [0.02, 0.012], [1, 0.5], 0.15), S.click(0.04, 3000, 7, 900, 0.7))
    b = S.mix(S.modal([rng.uniform(820, 900), 1650], [0.04, 0.02], [1, 0.4], 0.2), S.lp(S.noise(0.2), 400) * S.env_exp(0.2, 0.01) * 0.4)
    S.place(out, a * 0.7, 0.0)
    S.place(out, b, rng.uniform(0.05, 0.07))
    return out


def object_drop():
    """금속 쓰레받기가 바닥에 떨어져 두세 번 튀고 짧게 구른다."""
    out = np.zeros(int(2.0 * SR))
    t = 0.0
    for k, amp in enumerate((1.0, 0.55, 0.3, 0.16)):
        h = S.modal([rng.uniform(480, 560), rng.uniform(1150, 1300), rng.uniform(2300, 2600), rng.uniform(3900, 4300)],
                    [0.12, 0.08, 0.05, 0.03], [1, 0.6, 0.35, 0.2], 0.6)
        h = S.mix(h, S.lp(S.noise(0.6), 300) * S.env_exp(0.6, 0.01) * 0.8)
        S.place(out, h * amp, t)
        t += 0.22 * (0.62 ** k) + 0.04
    roll_d = 0.7
    roll = S.bp(S.noise(roll_d), 1500, 5000) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * S.t_(roll_d))) * np.linspace(0.25, 0, int(roll_d * SR))
    S.place(out, roll, t)
    return out


def tape_glitch():
    """카세트 잡음 순간: 헤드 잡음 증가 + 피치가 늘어지는 웅 + 드롭아웃."""
    d = rng.uniform(0.5, 1.1)
    t = S.t_(d)
    wow = 1 + 0.25 * np.sin(2 * np.pi * rng.uniform(2, 5) * t)
    tone = np.sin(np.cumsum(2 * np.pi * rng.uniform(150, 320) * wow / SR)) * 0.25
    hiss = S.hp(S.pink(d), 1800) * 0.6
    gate = (np.sin(2 * np.pi * rng.uniform(8, 20) * t) > rng.uniform(-0.3, 0.4)).astype(float)
    gate = np.convolve(gate, np.ones(200) / 200, "same")
    return (tone + hiss) * gate * np.hanning(len(t)) ** 0.3


def apt_ambience(dur=24.0):
    """1998 아파트 늦은 오후: 먼 도로 웅웅·바람, 아주 가끔 먼 문 닫힘. 새·사람 목소리는 합성하지 않는다."""
    traffic = S.lp(S.brown(dur), 180) * 0.6 + S.bp(S.pink(dur), 300, 1200) * 0.08
    wind = S.bp(S.pink(dur), 200, 1800) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * S.t_(dur))) * 0.25
    out = traffic + wind
    for at in (5.5, 15.0):
        S.place(out, S.lp(S.door_close(), 900) * 0.08, at)
    return S.loopify(out, 1.5)


def main():
    reg = {}
    reg["sfx_knock_hit"] = {"files": [S.save("sfx", f"sfx_knock_hit_{i}", knock_hit(), 0.85) for i in range(8)],
                            "note": "게임이 3번을 강도·간격을 달리해 조합 (lvl_phase01.knock)"}
    reg["sfx_knock_late_hit"] = {"files": [S.save("sfx", f"sfx_knock_late_hit_{i}", knock_late_hit(), 0.75) for i in range(5)]}
    reg["sfx_door_slam"] = {"files": [S.save("sfx", f"sfx_door_slam_{i}", door_slam(0.9 + 0.05 * i), 0.85) for i in range(3)],
                            "impact_at": 0.14}
    reg["sfx_latch"] = {"files": [S.save("sfx", f"sfx_latch_{i}", latch(), 0.6) for i in range(3)]}
    reg["sfx_object_drop"] = {"files": [S.save("sfx", "sfx_object_drop", object_drop(), 0.8)]}
    reg["sfx_tape_glitch"] = {"files": [S.save("sfx", f"sfx_tape_glitch_{i}", tape_glitch(), 0.6) for i in range(4)]}
    reg["amb_apt_1998"] = {"files": [S.save("ambience", "amb_apt_1998", apt_ambience(), 0.5, loop=True)], "loop": True}
    p = S.GAME / "data" / "config" / "audio.json"
    cfg = json.loads(p.read_text("utf-8"))
    cfg["sounds"].update(reg)
    p.write_text(json.dumps(cfg, ensure_ascii=False, indent=1), "utf-8")
    for k, v in reg.items():
        print(f"  {k:22s} {len(v['files'])}")


if __name__ == "__main__":
    main()
