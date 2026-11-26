#!/usr/bin/env python3
"""환경음·효과음 합성기 — The Unrecorded Voice

외부 녹음 소스 없이 DSP로 전부 합성한다 (저작권·라이선스 문제 없음, 단 최종 사운드 디자인 전 임시 음원: 파일명 PH_).
- 3D 배치용이므로 모노. 반복 재생용 환경음은 끝과 시작을 크로스페이드한 OGG 루프.
출력: game/assets/audio/{ambience,sfx,footsteps}/PH_*.wav|ogg, game/data/config/audio.json (사운드 ID → 파일 목록)
usage: python3 tools/audio/make_sfx.py
"""
import json
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
AUD = GAME / "assets" / "audio"
rng = np.random.default_rng(2026)
REG = {}


# ------------------------------------------------------------------ dsp helpers
def t_(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def pink(dur):
    n = int(dur * SR)
    w = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = 1
    return norm(np.fft.irfft(w / np.sqrt(f), n))


def brown(dur):
    return norm(np.cumsum(rng.standard_normal(int(dur * SR))) * 0.02 - np.convolve(
        np.cumsum(rng.standard_normal(int(dur * SR))) * 0.02, np.ones(2000) / 2000, "same"))


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR / 2 - 100)], "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "lowpass", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "highpass", fs=SR, output="sos"), x)


def reson(x, f, q):
    b, a = signal.iirpeak(f, q, fs=SR)
    return signal.lfilter(b, a, x)


def env_exp(dur, decay, attack=0.002):
    t = t_(dur)
    return np.minimum(t / attack, 1) * np.exp(-t / decay)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def place(buf, x, at):
    i = int(at * SR)
    j = min(len(buf), i + len(x))
    if i < len(buf):
        buf[i:j] += x[:j - i]
    return buf


def modal(freqs, decays, amps, dur):
    t = t_(dur)
    out = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        out += a * np.sin(2 * np.pi * f * t * (1 + rng.uniform(-0.01, 0.01))) * np.exp(-t / d)
    return out


def loopify(x, xf=1.0):
    """끝 xf초를 시작에 크로스페이드 → 이음매 없는 루프."""
    n = int(xf * SR)
    head, tail = x[:n], x[-n:]
    w = np.linspace(0, 1, n)
    out = x[:-n].copy()
    out[:n] = head * w + tail * (1 - w)
    return out


def save(cat, sid, x, peak=0.9, loop=False):
    x = norm(x, peak)
    path = AUD / cat / f"PH_{sid}.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    res = path
    if loop:
        ogg = path.with_suffix(".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(path), "-c:a", "libvorbis", "-q:a", "5", str(ogg)], check=True)
        path.unlink()
        res = ogg
    return "res://" + str(res.relative_to(GAME)).replace("\\", "/")


def reg(sid, paths, **meta):
    REG[sid] = {"files": paths if isinstance(paths, list) else [paths], **meta}
    print(f"  {sid:28s} {len(REG[sid]['files'])}")


# ------------------------------------------------------------------ ambience
def rain_on_glass(dur=24.0, rate=420, heavy=False):
    buf = np.zeros(int(dur * SR))
    n = rng.poisson(rate * dur)
    for at in rng.uniform(0, dur, n):
        d = rng.uniform(0.004, 0.02)
        f = rng.uniform(1800, 6500)
        drop = bp(noise(d * 4), f * 0.7, f * 1.3) * env_exp(d * 4, d) * rng.uniform(0.05, 1.0) ** 2
        place(buf, drop, at)
    for at in rng.uniform(0, dur, int(dur * 3)):           # 큰 물방울
        place(buf, reson(noise(0.08), rng.uniform(700, 1400), 8) * env_exp(0.08, 0.02) * 0.5, at)
    wash = bp(pink(dur), 300, 9000) * (0.55 if heavy else 0.35)
    wash *= 1 + 0.15 * np.sin(2 * np.pi * 0.07 * t_(dur))
    out = buf * 0.9 + wash
    if heavy:
        out += lp(brown(dur), 250) * 0.5
    return loopify(out)


def thunder(dur, near):
    t = t_(dur)
    rumble = lp(brown(dur), 160) * 1.0 + lp(pink(dur), 600) * 0.35
    am = np.abs(signal.sosfilt(signal.butter(2, 2.5, "lowpass", fs=SR, output="sos"), rng.standard_normal(len(t)))) * 6 + 0.3
    envl = np.minimum(t / (0.05 if near else 0.6), 1) * np.exp(-t / (dur * 0.33))
    out = rumble * am * envl
    if near:
        crack = hp(noise(0.6), 1200) * env_exp(0.6, 0.08) * 1.4
        out = place(out, crack, 0.0)
        out = place(out, lp(noise(1.2), 900) * env_exp(1.2, 0.25) * 1.2, 0.05)
    return out


def pc_fan(dur=10.0):
    t = t_(dur)
    air = lp(hp(pink(dur), 120), 3200) * 0.5
    blade = sum(a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) for f, a in ((228, 0.18), (456, 0.07), (684, 0.03)))
    blade *= 1 + 0.05 * np.sin(2 * np.pi * 0.4 * t)
    hum = 0.05 * np.sin(2 * np.pi * 120 * t)
    return loopify(air + blade + hum)


def fluorescent_hum(dur=6.0, buzz=0.3):
    t = t_(dur)
    hum = sum(a * np.sin(2 * np.pi * f * t) for f, a in ((120, 0.5), (240, 0.3), (360, 0.15), (480, 0.08), (600, 0.05)))
    bz = bp(noise(dur), 2000, 7000) * (0.5 + 0.5 * np.sin(2 * np.pi * 120 * t)) * buzz
    return loopify(hum * 0.6 + bz)


def tape_motor(dur=8.0, speed=1.0):
    t = t_(dur)
    motor = 0.25 * np.sin(2 * np.pi * 95 * speed * t) + 0.12 * np.sin(2 * np.pi * 190 * speed * t)
    flutter = 1 + 0.03 * np.sin(2 * np.pi * 3.1 * t)
    gears = bp(noise(dur), 800, 2500) * 0.08 * (1 + 0.5 * np.sin(2 * np.pi * 11 * speed * t))
    hiss = hp(noise(dur), 3000) * 0.18
    return loopify(motor * flutter + gears + hiss)


# ------------------------------------------------------------------ foley
def click(dur=0.05, f=3500, q=5, body=900, amt=1.0):
    x = reson(noise(dur), f, q) * env_exp(dur, 0.004) + reson(noise(dur), body, 8) * env_exp(dur, 0.01) * 0.6
    return x * amt


def footstep(surface):
    d = 0.35
    if surface == "wood":       # 콘크리트 위 우드 데코타일 (PVC)
        heel = lp(noise(d), 260) * env_exp(d, 0.025) * 1.2
        tap = bp(noise(d), 900, 3000) * env_exp(d, 0.008) * 0.45
        toe = place(np.zeros(int(d * SR)), bp(noise(0.1), 700, 2500) * env_exp(0.1, 0.01) * 0.3, rng.uniform(0.07, 0.11))
        return heel + tap + toe
    if surface == "tile":       # 세라믹 타일 — 딱딱한 클릭 + 짧은 울림
        heel = lp(noise(d), 300) * env_exp(d, 0.02) * 0.9
        clk = bp(noise(d), 2200, 6500) * env_exp(d, 0.006) * 0.9 + reson(noise(d), rng.uniform(2600, 3400), 25) * env_exp(d, 0.03) * 0.25
        toe = place(np.zeros(int(d * SR)), bp(noise(0.08), 1800, 5000) * env_exp(0.08, 0.006) * 0.5, rng.uniform(0.06, 0.1))
        return heel + clk + toe
    if surface == "concrete":   # 인조석 계단 — 모래 섞인 마찰
        heel = lp(noise(d), 220) * env_exp(d, 0.03) * 1.1
        grit = bp(noise(d), 1500, 7000) * env_exp(d, 0.05) * 0.25 * (rng.random(int(d * SR)) > 0.6)
        return heel + grit + bp(noise(d), 1000, 3000) * env_exp(d, 0.007) * 0.4
    if surface == "rug":        # 러그 — 둔탁하고 부드러움
        return lp(noise(d), 180) * env_exp(d, 0.035) * 0.8 + bp(noise(d), 1500, 5000) * env_exp(d, 0.06, 0.02) * 0.08
    raise ValueError(surface)


def steel_door_knock():
    k = modal([172, 398, 702, 1163, 1688], [0.12, 0.08, 0.05, 0.03, 0.02], [1, 0.6, 0.4, 0.25, 0.12], 0.7)
    k += lp(noise(0.7), 300) * env_exp(0.7, 0.015) * 0.8
    return k * env_exp(0.7, 0.25)


def knock_seq(n=3, gap=0.42):
    buf = np.zeros(int((n * gap + 1.0) * SR))
    for i in range(n):
        place(buf, steel_door_knock() * rng.uniform(0.85, 1.0), i * gap * rng.uniform(0.97, 1.03))
    return buf


def creak(dur, f0, f1):
    t = t_(dur)
    f = np.linspace(f0, f1, len(t)) * (1 + 0.04 * np.sin(2 * np.pi * 7 * t))
    ph = np.cumsum(f) / SR * 2 * np.pi
    pulses = (np.sin(ph) > 0.95).astype(float)
    x = reson(pulses, 900, 6) + reson(pulses, 1600, 9) * 0.5 + reson(pulses, 2600, 12) * 0.3
    return x * np.hanning(len(t)) ** 0.5


def door_open():
    latch = click(0.08, 2800, 6, 700, 1.0)
    out = np.zeros(int(1.6 * SR))
    place(out, latch, 0.0)
    place(out, creak(1.0, 18, 30) * 0.35, 0.18)
    place(out, lp(noise(1.2), 400) * env_exp(1.2, 0.4, 0.3) * 0.2, 0.15)
    return out


def door_close():
    out = np.zeros(int(1.4 * SR))
    place(out, lp(noise(0.4), 500) * env_exp(0.4, 0.15, 0.15) * 0.25, 0.0)
    thud = modal([62, 118, 176, 395], [0.18, 0.1, 0.07, 0.04], [1, 0.6, 0.4, 0.2], 0.9) + lp(noise(0.9), 250) * env_exp(0.9, 0.03)
    place(out, thud, 0.32)
    place(out, click(0.08, 2600, 6, 800, 0.8), 0.33)
    return out


def door_locked():
    out = np.zeros(int(0.8 * SR))
    for k in range(3):
        place(out, click(0.06, 2000 + k * 200, 5, 600, 0.8) + steel_door_knock()[:int(0.06 * SR)] * 0.2, k * 0.14)
    return out


def cardboard_flap():
    d = 0.5
    return bp(noise(d), 300, 3000) * env_exp(d, 0.12, 0.05) * 0.6 + lp(noise(d), 200) * env_exp(d, 0.02) * 0.4


def tape_rip():
    d = 1.1
    t = t_(d)
    crackle = bp(noise(d), 1500, 8000) * (rng.random(len(t)) > 0.75) * np.minimum(t / 0.05, 1) * np.exp(-((t - 0.5) / 0.35) ** 2)
    return crackle + bp(noise(d), 400, 1500) * np.exp(-((t - 0.5) / 0.4) ** 2) * 0.3


def paper_rustle(d=0.8):
    t = t_(d)
    gr = bp(noise(d), 1200, 9000) * (rng.random(len(t)) > 0.5)
    return gr * np.abs(signal.sosfilt(signal.butter(2, 12, "lowpass", fs=SR, output="sos"), rng.standard_normal(len(t)))) * 8 * np.hanning(len(t))


def drawer(open_=True):
    d = 0.6
    t = t_(d)
    slide = bp(noise(d), 300, 2500) * np.hanning(len(t)) * 0.4 * (1 + 0.3 * np.sin(2 * np.pi * 40 * t))
    stop = lp(noise(0.3), 400) * env_exp(0.3, 0.03) * 0.8
    out = np.zeros(int(0.9 * SR))
    place(out, slide, 0)
    place(out, stop, 0.55 if open_ else 0.5)
    return out


def elevator_ding():
    t = t_(2.0)
    return (np.sin(2 * np.pi * 1318 * t) * 0.6 + np.sin(2 * np.pi * 2636 * t) * 0.2) * np.exp(-t / 0.6)


def main():
    print("ambience:")
    reg("amb_rain_window", save("ambience", "amb_rain_window", rain_on_glass(), 0.8, loop=True), loop=True)
    reg("amb_rain_heavy", save("ambience", "amb_rain_heavy", rain_on_glass(24, 650, True), 0.8, loop=True), loop=True)
    muff = lp(rain_on_glass(24, 500, True), 500, 4)
    reg("amb_rain_muffled", save("ambience", "amb_rain_muffled", loopify(muff, 0.5), 0.7, loop=True), loop=True)
    reg("amb_pc_fan", save("ambience", "amb_pc_fan", pc_fan(), 0.6, loop=True), loop=True)
    reg("amb_fluorescent_hum", save("ambience", "amb_fluorescent_hum", fluorescent_hum(), 0.5, loop=True), loop=True)
    reg("amb_fluorescent_buzz", save("ambience", "amb_fluorescent_buzz", fluorescent_hum(6, 0.9), 0.6, loop=True), loop=True)
    reg("amb_tape_motor", save("ambience", "amb_tape_motor", tape_motor(), 0.6, loop=True), loop=True)
    reg("amb_tape_rewind", save("ambience", "amb_tape_rewind", tape_motor(6, 3.2), 0.6, loop=True), loop=True)
    reg("amb_tape_hiss", save("ambience", "amb_tape_hiss", loopify(hp(pink(8), 2500) * 0.4 + lp(pink(8), 200) * 0.1), 0.4, loop=True),
        loop=True)
    reg("sfx_thunder", [save("sfx", f"sfx_thunder_{i}", thunder(d, near), 0.95) for i, (d, near) in
                        enumerate(((10, False), (12, False), (8, True)))])
    print("foley:")
    reg("sfx_clock_tick", [save("sfx", "sfx_clock_tick", click(0.06, 4200, 6, 1300, 1.0), 0.5),
                           save("sfx", "sfx_clock_tock", click(0.06, 3600, 6, 1100, 1.0), 0.45)])
    reg("sfx_flicker_zap", [save("sfx", f"sfx_flicker_zap_{i}", bp(noise(0.12), 1500, 8000) * env_exp(0.12, 0.03) +
                                 0.3 * np.sin(2 * np.pi * 120 * t_(0.12)) * env_exp(0.12, 0.05), 0.6) for i in range(3)])
    for s in ("wood", "tile", "concrete", "rug"):
        reg(f"step_{s}", [save("footsteps", f"step_{s}_{i:02d}", footstep(s), 0.85) for i in range(6)])
    reg("sfx_door_open", save("sfx", "sfx_door_open", door_open()))
    reg("sfx_door_close", save("sfx", "sfx_door_close", door_close()))
    reg("sfx_door_locked", save("sfx", "sfx_door_locked", door_locked(), 0.7))
    reg("sfx_knock_3", save("sfx", "sfx_knock_3", knock_seq(3)))
    reg("sfx_light_switch", save("sfx", "sfx_light_switch", click(0.07, 2400, 4, 600, 1.0), 0.6))
    reg("sfx_flashlight_on", save("sfx", "sfx_flashlight_on", click(0.05, 3800, 7, 1500) + 0.4 * click(0.05, 2400, 5, 900), 0.55))
    reg("sfx_flashlight_off", save("sfx", "sfx_flashlight_off", click(0.05, 3100, 7, 1200) + 0.4 * click(0.05, 2000, 5, 800), 0.5))
    reg("sfx_cassette_insert", save("sfx", "sfx_cassette_insert", click(0.12, 1800, 4, 500, 1.0) + click(0.12, 3000, 6, 700, 0.5), 0.8))
    reg("sfx_cassette_door", save("sfx", "sfx_cassette_door", click(0.15, 1500, 4, 420, 1.0), 0.8))
    reg("sfx_deck_button", save("sfx", "sfx_deck_button", click(0.1, 1200, 3, 300, 1.0) + lp(noise(0.1), 200) * env_exp(0.1, 0.01), 0.8))
    reg("sfx_tape_stop", save("sfx", "sfx_tape_stop", click(0.15, 900, 3, 250, 1.0) + lp(noise(0.15), 150) * env_exp(0.15, 0.02), 0.8))
    reg("sfx_cardboard_flap", [save("sfx", f"sfx_cardboard_flap_{i}", cardboard_flap(), 0.7) for i in range(3)])
    reg("sfx_tape_rip", save("sfx", "sfx_tape_rip", tape_rip(), 0.75))
    reg("sfx_paper_rustle", [save("sfx", f"sfx_paper_rustle_{i}", paper_rustle(), 0.6) for i in range(3)])
    reg("sfx_pickup", save("sfx", "sfx_pickup", bp(noise(0.25), 400, 3000) * env_exp(0.25, 0.06, 0.02), 0.5))
    reg("sfx_drawer_open", save("sfx", "sfx_drawer_open", drawer(True), 0.7))
    reg("sfx_drawer_close", save("sfx", "sfx_drawer_close", drawer(False), 0.7))
    reg("sfx_elevator_ding", save("sfx", "sfx_elevator_ding", elevator_ding(), 0.5))
    cfg = {"_doc": "사운드 ID → 파일 (PH_ = 합성 임시 음원). tools/audio/make_sfx.py 생성. 교체 시 이 파일만 수정.", "sounds": REG}
    (GAME / "data" / "config" / "audio.json").write_text(json.dumps(cfg, ensure_ascii=False, indent=1), "utf-8")


if __name__ == "__main__":
    main()
