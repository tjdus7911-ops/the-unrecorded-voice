#!/usr/bin/env python3
"""요구사항 15 §5 — 녹음기 재생 대사·초자연적 목소리(실제 음성 대상)만 뽑아 음성 제작 목록(CSV·MD)을 만든다.
입력: game/data/dialogue/*.json (voice == "voiced"). 출력: docs/production/voice_production_list.{csv,md}
최종 음성 파일은 game/assets/audio/voice/final/<언어>/<대사ID>.ogg 에 넣으면 코드 수정 없이 재생된다."""
import csv, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
G = ROOT / "game"
COND = {  # 요구사항 16 공식 대본: 발생 조건·재생 순서·배경 (이벤트 JSON 기준)
    "PRO_E04_T00": ("TAPE 01 (프롤로그 재생)", 1, "EVENT 04 — 요구사항 20 순서: PLAY 버튼 → 릴 회전 → 짧은 지지직(0.7초) 완전히 끝난 직후 첫마디",
                    "1998 놀이터 녹음 첫마디 — 녹음기 가까이 (게임이 아날로그 질감 약하게 적용)"),
    "PRO_E04_T01": ("TAPE 01 (프롤로그 재생)", 2, "EVENT 04 — '잘 들려?' → 놀이터 소리(아이들 웃음·그네) → 이 대사. 끝나는 순간 등 뒤 문이 쾅",
                    "1998 놀이터 녹음 — 아이들 웃음, 그네 삐걱 (게임이 카세트 효과 적용)"),
    "PRO_E05_002": ("LIVE (테이프 아님)", 1, "EVENT 05 — 플레이어가 녹음기를 정지하고 약 3초 뒤, 등 뒤 약 2 m",
                    "조용해진 작업실(시계·빗소리 멈춤) — 3D 공간 음향, 카세트 효과 없음"),
    "PRO_E07_001": ("LIVE (테이프 아님)", 1, "EVENT 07 — 손전등을 얻은 뒤 출입문에 다가가면 문 바깥(복도)에서",
                    "정전된 작업실 · 문 너머 복도 — 문에 막힌 듯 약간 먹먹하게"),
    "PRO_E10_001": ("LIVE (테이프 아님)", 1, "EVENT 10 — 마지막 형광등·손전등이 꺼지고 모든 발소리가 멈춘 뒤 1초 정적, 귓가",
                    "완전한 정적 — 귀 바로 옆 (게임이 공간 처리)"),
    "T01_REC_001": ("TAPE 01 (1998 기억)", 1, "TAPE 01 세 번째 녹음 조각 — 104호 앞 복도에서", "1998 아파트 복도 늦은 오후 — 멀리 아이들 소리"),
    "T01_REC_002": ("TAPE 01 (1998 기억)", 2, "T01_REC_001 직후", "같은 녹음"),
    "T01_REC_003": ("TAPE 01 (1998 기억)", 3, "T01_REC_002 직후 → 녹음 종료 후 복도 끝에 소은", "같은 녹음"),
}
DIRECTION = {
    "PRO_E04_T00": "어린 소은. 녹음기에 대고 밝게 확인하는 첫마디 — 설렘",
    "PRO_E04_T01": "어린 소은. 밝고 장난스럽게 — 녹음기를 막 켜고 확인하는 설렘",
    "PRO_E05_002": "어린 소은. 작고 선명하게, 부르듯 조용히 — 테이프와 같은 음색, 괴물처럼 왜곡 금지",
    "PRO_E07_001": "어린 소은. 문 너머에서 작게, 부르는 속삭임 — 위협 아님",
    "PRO_E10_001": "어린 소은. 숨바꼭질에서 찾은 아이처럼 귓가에 속삭임 — 장난기와 서늘함, 위협·왜곡 금지",
    "T01_REC_001": "어린 소은. 다정하고 진지하게, 약속하듯",
    "T01_REC_002": "어린 정우. 쑥스럽고 시큰둥하게",
    "T01_REC_003": "어린 소은. 웃으며 당연하다는 듯",
}
rows = []
for f in sorted((G / "data" / "dialogue").glob("*.json")):
    d = json.loads(f.read_text("utf-8"))
    for ln in d.get("lines", []):
        if ln.get("voice") != "voiced":
            continue
        lid = ln["line_id"]
        tape, order, cond, amb = COND.get(lid, (ln.get("tape", ""), ln.get("order", ""), ln.get("condition", ""), ln.get("ambience", "")))
        ko = ln.get("text", {}).get("ko", "")
        est = round(0.11 * len(ko.replace(" ", "")) + 0.6, 1) if not ko.startswith("(") else ""
        final = [lg for lg in ("ko", "en", "ja") for ext in ("ogg", "wav", "mp3")
                 if (G / "assets/audio/voice/final" / lg / f"{lid}.{ext}").exists()]
        rows.append({"테이프": tape, "대사ID": lid, "등장인물": ln.get("character_id", ""), "대사(한국어)": ko,
                     "영어": ln.get("text", {}).get("en", ""), "일본어": ln.get("text", {}).get("ja", ""),
                     "감정": ln.get("emotion", ""), "연기 방향": DIRECTION.get(lid, ln.get("direction", "")), "재생 순서": order,
                     "발생 조건": cond, "배경 환경음": amb, "음성 파일명": f"final/<lang>/{lid}.ogg",
                     "예상 재생 시간(초)": est, "최종 음성": ",".join(sorted(set(final))) or "없음 (임시 자막)",
                     "상태": "기획 대사 (이벤트 미연결)" if ln.get("planned") else "게임에 연결됨"})
    for u in d.get("unwritten", []):
        rows.append({"테이프": u["tape"], "대사ID": "—", "등장인물": "—", "대사(한국어)": u["status"], "영어": "", "일본어": "",
                     "감정": "", "연기 방향": "", "재생 순서": "", "발생 조건": "", "배경 환경음": "", "음성 파일명": "",
                     "예상 재생 시간(초)": "", "최종 음성": "", "상태": "대본 필요"})
out = ROOT / "docs" / "production"
with open(out / "voice_production_list.csv", "w", newline="", encoding="utf-8-sig") as fp:
    w = csv.DictWriter(fp, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)
md = ["# 음성 제작 목록 (요구사항 15 §5) — 자동 생성: `tools/audio/export_voice_list.py`", "",
      "대상: 녹음기에서 재생되는 모든 대사 + 녹음기 밖 초자연적 목소리(소은). 현재 시점 정우의 독백·일반 대화는 자막만이라 제외.",
      "최종 음성 넣는 법: `game/assets/audio/voice/final/<ko|en|ja>/<대사ID>.ogg` (wav·mp3도 가능) — 코드 수정 없음. 없으면 임시 자막만 표시.",
      "녹음기 대사는 게임이 카세트 효과(대역 제한·미세 왜곡·워우·테이프 잡음)를 입힌다 → **파일은 깨끗하게** 녹음/생성해 주세요.", "",
      "| " + " | ".join(k for k in rows[0] if k not in ("영어", "일본어")) + " |",
      "|" + "---|" * (len(rows[0]) - 2)]
for r in rows:
    md.append("| " + " | ".join(str(v).replace("|", "/") for k, v in r.items() if k not in ("영어", "일본어")) + " |")
(out / "voice_production_list.md").write_text("\n".join(md) + "\n", "utf-8")
print(len(rows), "rows ->", out / "voice_production_list.csv")
