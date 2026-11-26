"""캐릭터 음성 생성 — Supertonic 3 (Supertone, 모델 OpenRAIL-M / 코드 MIT, 상업 이용 가능·무료) + sherpa-onnx.

game/data/dialogue/*.json 의 대사(ko/en/ja)를 읽어 언어별 음성을 만들고 audio 경로를 채운다.
캐릭터 구분 (Supertonic 화자 + 후처리):
  - jungwoo_adult : 30대 남성 (남성 화자, 약간 낮게)
  - jungwoo_child : 남자아이 (여성 화자 → 음정·포먼트 상승)
  - soeun         : 여자아이 (여성 화자 → 음정·포먼트 상승, 더 밝게)
  - mansu/youngsik: 중년 남성 (샘플)
비명(scream 감정)은 같은 화자를 크게·짧게 만든 뒤 왜곡 없이 압축만 한다.
녹음기 속 목소리(테이프)는 게임 안 VoiceTape 버스가 아날로그 질감을 입힌다 — 파일은 깨끗하게 둔다.

모델: https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2
usage: TUV_SUPERTONIC=/path/to/model_dir python3 tools/audio/make_voice_supertonic.py
"""
import json
import os
import subprocess
from pathlib import Path

import numpy as np
import sherpa_onnx
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
M = Path(os.environ.get("TUV_SUPERTONIC", "/home/claude/ext_tts/sherpa-onnx-supertonic-3-tts-int8-2026-05-11"))
LANGS = ["ko", "en", "ja"]

# 화자 번호: 0~4 여성(약 165~212 Hz), 5~9 남성(약 89~147 Hz) — 음정 분석으로 확인
VOICES = {
    "jungwoo_adult": {"sid": 7, "speed": 0.95, "af": "rubberband=pitch=0.97:formant=preserved,highpass=f=70,lowpass=f=9000"},
    "jungwoo_child": {"sid": 3, "speed": 1.05, "af": "rubberband=pitch=1.22:formant=shifted,highpass=f=140"},
    "soeun": {"sid": 1, "speed": 1.03, "af": "rubberband=pitch=1.26:formant=shifted,highpass=f=150"},
    "mansu": {"sid": 5, "speed": 0.92, "af": "rubberband=pitch=0.95:formant=preserved"},
    "youngsik": {"sid": 8, "speed": 0.95, "af": "rubberband=pitch=0.93:formant=preserved"},
}
EMOTION = {   # 감정별 속도·볼륨 조정 (과장 없이)
    "whisper": {"speed": 0.9, "gain": -6.0},
    "fear": {"speed": 1.05, "gain": 0.0},
    "scream": {"speed": 1.2, "gain": 4.0},
    "tired": {"speed": 0.88, "gain": -2.0},
    "dazed": {"speed": 0.85, "gain": -3.0},
}


def make_tts():
    cfg = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        supertonic=sherpa_onnx.OfflineTtsSupertonicModelConfig(
            duration_predictor=str(M / "duration_predictor.int8.onnx"), text_encoder=str(M / "text_encoder.int8.onnx"),
            vector_estimator=str(M / "vector_estimator.int8.onnx"), vocoder=str(M / "vocoder.int8.onnx"),
            tts_json=str(M / "tts.json"), unicode_indexer=str(M / "unicode_indexer.bin"), voice_style=str(M / "voice.bin")),
        num_threads=4, provider="cpu"))
    return sherpa_onnx.OfflineTts(cfg)


def synth(tts, text, lang, sid, speed):
    g = sherpa_onnx.GenerationConfig()
    g.sid = sid
    g.num_steps = 12
    g.speed = speed
    g.extra["lang"] = lang
    a = tts.generate(text, g)
    return np.array(a.samples, dtype=np.float32), a.sample_rate


def main():
    tts = make_tts()
    count = 0
    for f in sorted((GAME / "data" / "dialogue").glob("*.json")):
        data = json.loads(f.read_text("utf-8"))
        changed = False
        for ln in data.get("lines", []):
            ch = ln.get("character_id", "")
            if ch not in VOICES or ln.get("playback", {}).get("mode") == "document":
                continue
            v = VOICES[ch]
            emo = EMOTION.get(ln.get("emotion", ""), {})
            ln.setdefault("audio", {})
            for lang in LANGS:
                text = ln.get("text", {}).get(lang, "")
                if not text:
                    continue
                x, sr = synth(tts, text, lang, v["sid"], v["speed"] * emo.get("speed", 1.0))
                raw = Path("/tmp") / f"vo_{ln['line_id']}_{lang}.wav"
                sf.write(raw, x / (np.abs(x).max() + 1e-9) * 0.9, sr)
                d = GAME / "assets" / "audio" / "voice" / ch / lang
                d.mkdir(parents=True, exist_ok=True)
                dst = d / f"TTS_{ln['line_id']}.wav"
                loud = -16 + emo.get("gain", 0.0)
                af = f"{v['af']},aresample=44100,apad=pad_dur=0.2,loudnorm=I={loud}:TP=-1.5"
                subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw), "-af", af, "-ac", "1",
                                "-c:a", "pcm_s16le", "-ar", "44100", str(dst)], check=True)
                ln["audio"][lang] = "res://" + str(dst.relative_to(GAME))
                count += 1
            ln["voice_source"] = "Supertonic 3 TTS (OpenRAIL-M, commercial use allowed) — replace with voice actors if budget allows"
            changed = True
            print(f"  {ch:14s} {ln['line_id']:16s} {ln['text'].get('ko', '')}")
        if changed:
            f.write_text(json.dumps(data, ensure_ascii=False, indent=2), "utf-8")
    print(count, "files")
    tape_playground(tts)


def tape_playground(tts):
    """테이프 01 도입부: 놀이터 공기 + 그네 삐걱임(make_sfx) + 아이 웃음(위 화자) → audio.json 'tape_playground'."""
    sfx = GAME / "assets" / "audio" / "sfx"
    laughs = []
    for ch, text in (("soeun", "하하하하! 히히."), ("jungwoo_child", "아하하하!")):
        v = VOICES[ch]
        x, sr = synth(tts, text, "ko", v["sid"], v["speed"])
        raw = Path("/tmp") / f"laugh_{ch}.wav"
        sf.write(raw, x / (np.abs(x).max() + 1e-9) * 0.9, sr)
        out = Path("/tmp") / f"laugh_{ch}_p.wav"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw), "-af", v["af"] + ",aresample=44100", "-ac", "1", str(out)], check=True)
        laughs.append(out)
    dst = sfx / "TTS_tape_playground.wav"
    fc = ("anoisesrc=color=pink:amplitude=0.05:d=6.5,lowpass=f=1800,highpass=f=120[air];"
          "[0:a]adelay=200|200,volume=0.8[sw];[1:a]adelay=900|900,volume=0.9[la];[2:a]adelay=2300|2300,volume=0.8[lb];"
          "[air][sw][la][lb]amix=inputs=4:duration=longest:normalize=0,"
          "vibrato=f=0.7:d=0.04,highpass=f=250,lowpass=f=4200,acompressor=threshold=0.2:ratio=3,"
          "atrim=0:6.3,afade=t=in:d=0.3,afade=t=out:st=5.6:d=0.7,loudnorm=I=-22:TP=-3")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(sfx / "PH_sfx_swing_creak.wav"), "-i", str(laughs[0]),
                    "-i", str(laughs[1]), "-filter_complex", fc, "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", str(dst)], check=True)
    cfgp = GAME / "data" / "config" / "audio.json"
    cfg = json.loads(cfgp.read_text("utf-8"))
    cfg["sounds"]["tape_playground"] = {"files": ["res://assets/audio/sfx/TTS_tape_playground.wav"], "loop": False}
    cfg["sounds"]["sfx_child_laugh"] = {"files": [str("res://" + str(l.relative_to(GAME))) for l in []] or
                                        ["res://assets/audio/sfx/TTS_child_laugh.wav"], "loop": False}
    # 작업실에서 들리는 아이 웃음 (EVENT 06) — 소은 웃음만, 실제 공간용
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(laughs[0]), "-af", "atrim=0:2.2,afade=t=out:st=1.7:d=0.5,loudnorm=I=-20:TP=-3",
                    "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", str(sfx / "TTS_child_laugh.wav")], check=True)
    cfgp.write_text(json.dumps(cfg, ensure_ascii=False, indent=1), "utf-8")
    print("  tape_playground, sfx_child_laugh")


if __name__ == "__main__":
    main()
