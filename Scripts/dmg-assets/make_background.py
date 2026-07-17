#!/usr/bin/env python3
"""Generates the Sonnet Create DMG installer background (PNG).

v1.3 unified theme: white canvas + deep-navy (#031C35) accent — the Finder
DMG window should feel like an extension of the app itself.
Rendered at 2x (Retina) pixels for create-dmg's --window-size 700 460 (pt).
Text is kept in English — see the "dmg-english-only" decision: the DMG
background is a baked image, so per-language variants aren't worth the
maintenance cost. The app itself is localized via AppCore's Localizer.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "dist" / "dmg-assets" / "background.png"
OUT.parent.mkdir(parents=True, exist_ok=True)

# 700x460 pt 창 기준 2x
SCALE = 2
W, H = 700 * SCALE, 460 * SCALE

# v1.3 통합 팔레트 (SonnetPalette와 동일)
CANVAS = (255, 255, 255)      # canvas #FFFFFF
SURFACE = (246, 248, 251)     # surface #F6F8FB
INK = (14, 27, 44)            # ink #0E1B2C
INK_MUTED = (95, 107, 124)    # inkMuted #5F6B7C
ACCENT = (3, 28, 53)          # accent #031C35

img = Image.new("RGB", (W, H), CANVAS)
draw = ImageDraw.Draw(img)

# --- 상단 살짝 가라앉은 띠 — 앱 헤더(sunken 톤)의 결을 잇는다 ---
band_h = 116 * SCALE
for y in range(band_h):
    t = y / band_h
    color = tuple(round(SURFACE[i] + (CANVAS[i] - SURFACE[i]) * t) for i in range(3))
    draw.line([(0, y), (W, y)], fill=color)


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size)


georgia = font(Path("/System/Library/Fonts/Supplemental/Georgia.ttf"), 46 * SCALE // 2)
georgia_italic = font(Path("/System/Library/Fonts/Supplemental/Georgia Italic.ttf"), 15 * SCALE)
pretendard = REPO / "Packages/DesignSystem/Sources/DesignSystem/Fonts/PretendardVariable.ttf"
pretendard_body = font(pretendard, 14 * SCALE)
pretendard_small = font(pretendard, 11 * SCALE)

CENTER_X = W // 2

# --- 헤더: 브랜드마크 + 워드마크 ---
brandmark_path = REPO / "App/SonnetCreate/Assets.xcassets/BrandMark.imageset/brandmark@2x.png"
if brandmark_path.exists():
    mark_size = 34 * SCALE
    mark = Image.open(brandmark_path).convert("RGBA").resize((mark_size, mark_size), Image.LANCZOS)
    img.paste(mark, (CENTER_X - mark_size // 2, 18 * SCALE), mark)

draw.text((CENTER_X, 66 * SCALE), "Sonnet Create", font=georgia, fill=INK, anchor="mm")
draw.text(
    (CENTER_X, 90 * SCALE),
    "marks · scenes · worlds — a native writing workspace",
    font=georgia_italic, fill=INK_MUTED, anchor="mm"
)

# 헤더 아래 얇은 액센트 선
rule_y = 106 * SCALE
draw.line([(CENTER_X - 90 * SCALE, rule_y), (CENTER_X + 90 * SCALE, rule_y)], fill=ACCENT, width=max(1, SCALE // 2))

# --- 1행: 앱 → Applications 화살표 안내 (아이콘 위치: 220/480) ---
row1_y = 160 * SCALE
draw.text((CENTER_X, row1_y - 34 * SCALE), "Drag the app into Applications", font=pretendard_body, fill=INK, anchor="mm")

arrow_left = 220 * SCALE + 58 * SCALE
arrow_right = 480 * SCALE - 58 * SCALE
draw.line([(arrow_left, row1_y), (arrow_right, row1_y)], fill=ACCENT, width=3 * SCALE // 2)
draw.polygon(
    [
        (arrow_right, row1_y - 9 * SCALE // 2),
        (arrow_right, row1_y + 9 * SCALE // 2),
        (arrow_right + 14 * SCALE // 2, row1_y),
    ],
    fill=ACCENT,
)

# --- 2행: Read Me 안내 (아이콘 위치: 350/330) ---
row2_y = 300 * SCALE
draw.text(
    (CENTER_X, row2_y),
    "↓  Read Me for setup notes",
    font=pretendard_body, fill=INK, anchor="mm"
)

# --- 하단 각주 ---
footer_y = H - 26 * SCALE
draw.text(
    (CENTER_X, footer_y),
    "If macOS warns about an unidentified developer, right-click the icon and choose Open.",
    font=pretendard_small, fill=INK_MUTED, anchor="mm"
)

img.save(OUT, dpi=(144, 144))
print(f"wrote {OUT} ({W}x{H} @144dpi)")
