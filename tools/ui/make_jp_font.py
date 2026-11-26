"""일본어 표시용 Noto Sans CJK JP 서브셋 (SIL OFL 1.1) — 한국어 폰트의 폴백으로 사용.
포함: 기본 라틴, 히라가나·가타카나, 전각 기호, 상용 한자(JIS X 0208 1·2수준 범위 내 CJK 통합 한자 중 Shift_JIS 인코딩 가능한 글자).
usage: python3 tools/ui/make_jp_font.py
"""
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTCollection

ROOT = Path(__file__).resolve().parents[2]
SRC = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
OUT = ROOT / "game/assets/fonts/NotoSansJP-Regular-subset.otf"


def chars():
    cs = set(range(0x20, 0x7F)) | set(range(0x3000, 0x3100)) | set(range(0xFF00, 0xFFF0)) | set(range(0x30A0, 0x3100))
    cs |= {0x2026, 0x2014, 0x2015, 0x201C, 0x201D, 0x2018, 0x2019, 0x00B7, 0x30FB}
    cs |= set(range(0x2190, 0x2200)) | set(range(0x25A0, 0x2600)) | set(range(0x2460, 0x2474))   # 화살표·도형(●○)·원문자
    for cp in range(0x4E00, 0xA000):
        try:
            chr(cp).encode("shift_jis")
            cs.add(cp)
        except UnicodeEncodeError:
            pass
    return cs


def main():
    col = TTCollection(SRC)
    font = col.fonts[0]          # index 0 = Noto Sans CJK JP
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=chars())
    sub.subset(font)
    font.save(str(OUT))
    print(OUT, OUT.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
