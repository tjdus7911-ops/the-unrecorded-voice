#!/usr/bin/env python3
"""캐릭터별 한국어 음성 '임시 가이드' 샘플 생성.

⚠ 최종 더빙이 아니다. 오프라인 TTS 1종(sherpa-onnx + Mimic3 ko_KO kss_low, 여성 화자 1명)을
   캐릭터별 음정·포먼트·속도·음색 처리로 구분한 것이다. 감정 연기 불가.
   KSS 데이터셋 라이선스는 비상업(CC BY-NC-SA 4.0) → 상업 빌드에 포함 금지. 대사 타이밍·자막 동기화 테스트용.
출력: game/assets/audio/voice/<character_id>/PH_<line_id>.wav, game/data/dialogue/voice_samples.json
usage: python3 tools/audio/make_voice_samples.py   (모델: /opt/tts/vits-mimic3-ko_KO-kss_low)
"""
import json
import os
import subprocess
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
MODEL = Path(os.environ.get("TUV_TTS_MODEL", "/opt/tts/vits-mimic3-ko_KO-kss_low"))

# 캐릭터별 처리: rubberband 음정 배율·포먼트·템포 + 추가 필터
VOICES = {
    "jungwoo_adult": {"pitch": 0.74, "tempo": 0.94, "extra": "lowshelf=g=3:f=180,highshelf=g=-3:f=5000", "speed": 0.95},
    "jungwoo_child": {"pitch": 1.16, "tempo": 1.06, "extra": "highshelf=g=2:f=4000", "speed": 1.05},
    "soeun":         {"pitch": 1.27, "tempo": 1.04, "extra": "highshelf=g=2:f=4500", "speed": 1.0},
    "mansu":         {"pitch": 0.70, "tempo": 0.90, "extra": "vibrato=f=5.5:d=0.06,lowpass=f=6000,lowshelf=g=2:f=200", "speed": 0.9},
    "youngsik":      {"pitch": 0.78, "tempo": 0.97, "extra": "acompressor=threshold=0.1:ratio=3,lowshelf=g=2:f=160", "speed": 0.95},
}

LINES = [
    ("jungwoo_adult", "PRO_S03_001", "이 시간에 누구지?", "uneasy"),
    ("jungwoo_adult", "PRO_S05_002", "뭐야?", "flustered"),
    ("jungwoo_adult", "PRO_S06_001", "누구세요?", "fear"),
    ("jungwoo_adult", "PRO_S06_002", "전기가 나갔나… 손전등. 책상 서랍에 있었는데.", "fear"),
    ("soeun", "PRO_S07_001", "정우야, 여기야.", "whisper"),
    ("soeun", "TAPE01_LAUGH_A", "하하하하! 히히.", "joy"),
    ("jungwoo_child", "TAPE01_LAUGH_B", "아하하하!", "joy"),
    ("soeun", "PRO_S05_001", "정우야, 녹음되고 있어?", "playful"),
    ("soeun", "PRO_S05_003", "정우야?", "whisper"),
    ("soeun", "SMP_SOEUN_01", "나중에 까먹을 수도 있잖아.", "joy"),
    ("jungwoo_child", "SMP_JWC_01", "이런 걸 왜 녹음해?", "playful"),
    ("jungwoo_child", "SMP_JWC_02", "난 안 까먹는데?", "playful"),
    ("mansu", "SMP_MANSU_01", "거기 누구 있어요? 순찰 중입니다.", "uneasy"),
    ("mansu", "SMP_MANSU_02", "나는 아무것도 못 들었어요.", "fear"),
    ("youngsik", "SMP_YOUNGSIK_01", "들어가면 안 됩니다.", "neutral"),
    ("youngsik", "SMP_YOUNGSIK_02", "관리사무소입니다. 무슨 일이시죠?", "neutral"),
]


def tts(text, speed):
    import sherpa_onnx
    cfg = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=str(MODEL / "ko_KO-kss_low.onnx"), tokens=str(MODEL / "tokens.txt"),
                                                   data_dir=str(MODEL / "espeak-ng-data")), num_threads=2))
    a = sherpa_onnx.OfflineTts(cfg).generate(text, sid=0, speed=speed)
    return np.array(a.samples), a.sample_rate


def write(path, x, sr):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def main():
    out = []
    for char, lid, text, emo in LINES:
        v = VOICES[char]
        x, sr = tts(text, v["speed"])
        d = GAME / "assets" / "audio" / "voice" / char
        d.mkdir(parents=True, exist_ok=True)
        raw = Path("/tmp") / f"{lid}_raw.wav"
        write(raw, x / (np.abs(x).max() + 1e-9) * 0.9, sr)
        dst = d / f"PH_{lid}.wav"
        af = f"rubberband=pitch={v['pitch']}:tempo={v['tempo']}:formant=shifted,{v['extra']},aresample=44100," \
             f"apad=pad_dur=0.25,loudnorm=I=-19:TP=-2"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw), "-af", af, "-ac", "1", "-c:a", "pcm_s16le", "-ar", "44100", str(dst)], check=True)
        out.append({"line_id": lid, "character_id": char, "voice_id": f"vo_{char}", "text": {"ko": text}, "emotion": emo,
                    "audio": {"ko": "res://" + str(dst.relative_to(GAME))}, "status": "PLACEHOLDER_TTS_NONCOMMERCIAL"})
        print(f"  {char:14s} {lid:16s} {text}")
    tape_playground(out)
    (GAME / "data" / "dialogue" / "voice_samples.json").write_text(json.dumps(
        {"_doc": "임시 TTS 가이드 음성 (비상업 라이선스 모델). 최종 더빙으로 교체 전용. 대사 타이밍·자막 동기화 테스트.",
         "chapter_id": "samples", "lines": [ln for ln in out if ln["line_id"].startswith("SMP_")]}, ensure_ascii=False, indent=1), "utf-8")
    # 프롤로그 대사 데이터에 임시 음성 경로 연결 (코드 변경 없음 — 데이터만)
    pro = GAME / "data" / "dialogue" / "prologue.json"
    data = json.loads(pro.read_text("utf-8"))
    paths = {o["line_id"]: o["audio"]["ko"] for o in out}
    for ln in data["lines"]:
        if ln["line_id"] in paths:
            ln["audio"]["ko"] = paths[ln["line_id"]]
    pro.write_text(json.dumps(data, ensure_ascii=False, indent=2), "utf-8")


def tape_playground(out):
    """테이프 01 도입부: 놀이터 공기 + 그네 삐걱임 + 아이들 웃음 (모두 임시 합성) → 카세트 녹음 질감(대역 제한·와우).
    결과를 audio.json의 'tape_playground' ID로 등록한다."""
    sfx = GAME / "assets" / "audio" / "sfx"
    laugh_a = GAME / "assets" / "audio" / "voice" / "soeun" / "PH_TAPE01_LAUGH_A.wav"
    laugh_b = GAME / "assets" / "audio" / "voice" / "jungwoo_child" / "PH_TAPE01_LAUGH_B.wav"
    swing = sfx / "PH_sfx_swing_creak.wav"
    dst = sfx / "PH_tape_playground.wav"
    fc = ("anoisesrc=color=pink:amplitude=0.05:d=6.5,lowpass=f=1800,highpass=f=120[air];"
          "[0:a]adelay=200|200,volume=0.8[sw];[1:a]adelay=900|900,volume=0.9[la];[2:a]adelay=2300|2300,volume=0.8[lb];"
          "[air][sw][la][lb]amix=inputs=4:duration=longest:normalize=0,"
          "vibrato=f=0.7:d=0.04,highpass=f=250,lowpass=f=4200,acompressor=threshold=0.2:ratio=3,"
          "atrim=0:6.3,afade=t=in:d=0.3,afade=t=out:st=5.6:d=0.7,loudnorm=I=-22:TP=-3")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(swing), "-i", str(laugh_a), "-i", str(laugh_b),
                    "-filter_complex", fc, "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", str(dst)], check=True)
    cfgp = GAME / "data" / "config" / "audio.json"
    cfg = json.loads(cfgp.read_text("utf-8"))
    cfg["sounds"]["tape_playground"] = {"files": ["res://assets/audio/sfx/PH_tape_playground.wav"], "loop": False}
    cfgp.write_text(json.dumps(cfg, ensure_ascii=False, indent=1), "utf-8")
    print("  tape_playground (임시 합성)")


if __name__ == "__main__":
    main()
