#!/usr/bin/env python3
"""요구사항 16 산출물: 실제 맵 배치도 + 캐릭터 위치 (게임 코드와 같은 Blender 좌표값 사용).
출력: docs/production/maps/prologue_corridor_layout.png, tape01_apartment_layout.png"""
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm
from matplotlib.patches import Rectangle, Circle, FancyArrowPatch

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "production" / "maps"
OUT.mkdir(parents=True, exist_ok=True)
fp = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
fm.fontManager.addfont(fp)
plt.rcParams["font.family"] = fm.FontProperties(fname=fp).get_name()
INK, WALL, FLOOR, ACC = "#2b2b2b", "#555", "#f3f1ec", "#b03a2e"

def room(ax, x0, y0, x1, y1, fc=FLOOR, label=None, **kw):
    ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fc=fc, ec=WALL, lw=1.6, **kw))
    if label:
        ax.text((x0 + x1) / 2, (y0 + y1) / 2, label, ha="center", va="center", fontsize=9, color="#666")

def mark(ax, x, y, n, text, c=ACC, dx=0.25, dy=0.35):
    ax.add_patch(Circle((x, y), 0.22, fc=c, ec="white", lw=1.2, zorder=5))
    ax.text(x, y, n, ha="center", va="center", color="white", fontsize=9, weight="bold", zorder=6)
    ax.text(x + dx, y + dy, text, fontsize=8.5, color=INK, zorder=6)

# ---------------- 프롤로그: 작업실 + 상가 복도 (build_studio / build_corridor 좌표)
fig, ax = plt.subplots(figsize=(14, 6.4), dpi=140)
room(ax, 0, 0, 6, 5)
ax.text(3.0, 3.4, "304호 작업실 (정우)", ha="center", fontsize=9, color="#666")
room(ax, -5, -2, 13, -0.2, fc="#ecebe6")
ax.text(-4.8, -1.95, "3층 상가 복도", fontsize=9, color="#666")
room(ax, 13, -2.4, 15.6, 3.6, fc="#e6e4de", label="계단실")
ax.add_patch(Rectangle((-1.58, -0.84), 0.46, 0.64, fc="#bbb", ec=WALL, lw=1.4, zorder=3))
ax.text(-1.35, -0.55, "기둥", ha="center", fontsize=7.5, zorder=4)
ax.add_patch(Rectangle((0.5, -0.25), 0.9, 0.12, fc="#7a5", ec=INK, zorder=3))
ax.text(0.95, 0.2, "출입문", ha="center", fontsize=8)
ax.add_patch(Rectangle((1.9, 4.05), 2.2, 0.75, fc="#c9b9a2", ec=INK, zorder=2))
ax.text(3.0, 4.42, "책상 · 녹음기 · 서랍(손전등)", ha="center", fontsize=7.5, zorder=3)
for i, x in enumerate([-3.5, -0.5, 2.5, 5.5, 8.5, 11.5]):
    ax.add_patch(Rectangle((x - 0.6, -1.15), 1.2, 0.1, fc="#ffd75a", ec="#a80", zorder=3))
    off = f"{i + 1}번째 소등" if i < 5 else "마지막 소등 (EV10b)"
    ax.text(x, -2.12, f"CorLight{i}\n{off}", ha="center", va="top", fontsize=6.8, color="#7a5b00")
mark(ax, 0.95, -0.55, "①", "문: EV04 쾅·잠김 / EV07 바깥 속삭임·노크·잠금 해제", dx=0.5, dy=0.75)
mark(ax, 12.15, -1.25, "②", "소은 (등 돌림, CorLight5 아래)\nEV08: 보면 깜빡임 → 사라짐", dx=-3.6, dy=1.35)
mark(ax, -1.84, -0.42, "③", "소음 실루엣: 기둥 뒤에서\n머리·어깨만 (EV09), 다가가면 숨음", dx=-3.0, dy=0.55)
mark(ax, 0.95, -1.15, "④", "", c="#2e6db0")
ax.text(-4.8, -3.05, "④ 플레이어: 문을 나와 동쪽(②)을 봄 → 소은 사라짐 → 뒤(서쪽) 기둥의 ③", fontsize=8, color="#2e6db0")
ax.add_patch(FancyArrowPatch((1.5, -3.55), (11.2, -3.55), arrowstyle="-|>", mutation_scale=16, color="#2e6db0", lw=1.6))
ax.text(6.3, -3.95, "EV10 플레이어 이동(동쪽) → 뒤에서부터 형광등이 하나씩 꺼짐 · 따라오는 발소리 (서쪽 뒤 7.5 → 2.4 m)", ha="center", fontsize=8, color="#2e6db0")
mark(ax, 2.9, 2.3, "⑤", "EV05 '정우야...?' 등 뒤 약 2 m (방 안)", c="#7d4bb0", dx=0.3, dy=0.25)
ax.set_xlim(-5.5, 16); ax.set_ylim(-4.3, 5.4); ax.set_aspect("equal"); ax.axis("off")
ax.set_title("프롤로그 EVENT 01~10 배치도 — 작업실·복도 (게임 좌표 그대로, 1칸 = 1 m)", fontsize=12)
fig.savefig(OUT / "prologue_corridor_layout.png", bbox_inches="tight"); plt.close(fig)

# ---------------- TAPE 01: 1998 아파트 (build_apartment 좌표)
fig, ax = plt.subplots(figsize=(13, 8.6), dpi=140)
room(ax, 0, 0, 24, 1.7, fc="#efe6cf")
room(ax, 0, 1.9, 24, 4.2, fc="#e3dccb")
ax.text(12, 3.05, "세대 (출입 불가)", ha="center", fontsize=9, color="#666")
for k, x in enumerate([2.1, 6.3, 10.5, 14.7, 18.9], 1):
    ax.text(x, 1.45, f"10{k}", ha="center", fontsize=7)
ax.plot([0, 24], [0.09, 0.09], color=WALL, lw=3)
room(ax, 24, -0.2, 27.4, 5.6, fc="#e6e4de")
ax.text(25.7, 3.0, "계단실", ha="center", fontsize=9, color="#666")
ax.add_patch(Rectangle((24.3, -1.2), 1.6, 1.0, fc="#ddd", ec=WALL))
ax.text(25.1, -0.85, "현관", ha="center", fontsize=8)
for i in range(6):
    ax.add_patch(Rectangle((0.1 + i * 3.9, -1.4), 3.4, 0.9, fc="#6d9a5b", ec="none", alpha=0.6))
ax.text(0.2, -1.95, "화단 · 난간벽(남쪽이 트인 1층 외부 복도)", fontsize=7.5, color="#666")
ax.add_patch(Rectangle((6, -13.5), 10, 7, fc="#eadcb8", ec=WALL, lw=1.4))
ax.text(11, -13.1, "놀이터 (모래 · 경계석 · 벤치)", ha="center", fontsize=9, color="#665")
ax.plot([8.0, 11.0], [-9.5, -9.5], color="#2a5f8a", lw=4)
def note(x, y, n, text, tx, ty, c=ACC):
    ax.add_patch(Circle((x, y), 0.3, fc=c, ec="white", lw=1.2, zorder=5))
    ax.text(x, y, n, ha="center", va="center", color="white", fontsize=8.5, weight="bold", zorder=6)
    ax.annotate(text, xy=(x, y), xytext=(tx, ty), fontsize=8.5, color=INK,
                arrowprops=dict(arrowstyle="-", color="#888", lw=0.8))
note(3.0, 0.85, "S", "시작 — EV10에서 1998년 복도로 (동쪽을 봄)", 0.0, 6.0, c="#2e6db0")
note(9.5, -9.5, "1", "조각 1: 빈 그네가 움직인다 (삐걱 · 아이들 웃음) — 5 m 안에 들어오면", 13.0, -8.2)
note(25.5, 1.4, "2", "조각 2: 계단 아래에서 위층 아이 발소리", 27.8, 0.0)
note(26.15, 5.0, "2'", "참에 올라가면 아무도 없다", 27.8, 6.2)
note(14.0, 0.85, "3", "조각 3: 104호 앞 — 1998 녹음 3줄 (소은 · 어린 정우 · 소은)", 6.0, 7.4)
note(23.4, 0.95, "♀", "소은: 녹음이 끝나면 복도 끝에 (플레이어가 안 볼 때 배치) → 보면 테이프 잡음과 함께 사라짐", 9.0, 8.8)
ax.annotate("", xy=(25.1, -2.4), xytext=(3.4, 0.4), arrowprops=dict(arrowstyle="-|>", color="#2e6db0", lw=1.2, connectionstyle="arc3,rad=0.12"))
ax.text(12, -4.5, "권장 동선: 복도 → 계단실 → 현관 → 놀이터(1) → 계단(2→2') → 복도 104호 앞(3) → 복도 끝 소은 → 카세트 자동 정지 → 작업실", ha="center", fontsize=8.5, color="#2e6db0")
ax.set_xlim(-1, 36); ax.set_ylim(-14.2, 9.8); ax.set_aspect("equal"); ax.axis("off")
ax.set_title("TAPE 01 「평범했던 하루」 배치도 — 1998 복도식 아파트 (게임 좌표, 1칸 = 1 m)", fontsize=12)
fig.savefig(OUT / "tape01_apartment_layout.png", bbox_inches="tight"); plt.close(fig)
print("maps ->", OUT)
