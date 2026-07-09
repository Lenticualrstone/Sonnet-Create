#!/usr/bin/env python3
"""Sonnet Create DMG 설치 화면 배경(PNG)을 생성한다.

Sonnet 테마(앤티크 페이퍼 캔버스 + 적갈 액센트 + 그레인)를 그대로 옮겨,
Finder DMG 창의 브랜드 경험이 앱 자체와 이어지도록 한다.
create-dmg의 --window-size 700 460 (pt) 기준 2x(레티나) 픽셀로 렌더링한다.
"""
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "dist" / "dmg-assets" / "background.png"
OUT.parent.mkdir(parents=True, exist_ok=True)

# 700x460 pt 창 기준 2x
SCALE = 2
W, H = 700 * SCALE, 460 * SCALE

CANVAS = (246, 241, 231)      # SonnetPalette.canvas #F6F1E7
INK = (51, 41, 30)            # SonnetPalette.ink #33291E
INK_MUTED = (134, 123, 103)   # SonnetPalette.inkMuted #867B67
ACCENT = (156, 74, 46)        # SonnetPalette.accent #9C4A2E

img = Image.new("RGB", (W, H), CANVAS)

# --- 미세 그레인 (DesignSystem.GrainOverlay와 같은 결의 정적 노이즈) ---
random.seed(42)
grain = Image.new("L", (W, H), 0)
grain_px = grain.load()
for _ in range(int(W * H * 0.012)):
    x = random.randrange(W)
    y = random.randrange(H)
    grain_px[x, y] = random.randint(40, 160)
grain = grain.filter(ImageFilter.GaussianBlur(0.3))
dark_layer = Image.new("RGB", (W, H), INK)
img = Image.composite(dark_layer, img, grain.point(lambda p: int(p * 0.06)))

draw = ImageDraw.Draw(img)


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
    mark_size = 30 * SCALE
    mark = Image.open(brandmark_path).convert("RGBA").resize((mark_size, mark_size), Image.LANCZOS)
    img.paste(mark, (CENTER_X - mark_size // 2, 22 * SCALE), mark)

draw.text((CENTER_X, 66 * SCALE), "Sonnet Create", font=georgia, fill=INK, anchor="mm")
draw.text(
    (CENTER_X, 90 * SCALE),
    "marks · scenes · worlds — a native writing workspace",
    font=georgia_italic, fill=INK_MUTED, anchor="mm"
)

# 헤더 아래 얇은 액센트 선
rule_y = 104 * SCALE
draw.line([(CENTER_X - 90 * SCALE, rule_y), (CENTER_X + 90 * SCALE, rule_y)], fill=ACCENT, width=max(1, SCALE // 2))

# --- 1행: 앱 → Applications 화살표 안내 ---
row1_y = 160 * SCALE
draw.text((CENTER_X, row1_y - 34 * SCALE), "앱을 Applications 폴더로 드래그하세요", font=pretendard_body, fill=INK, anchor="mm")

arrow_left = 150 * SCALE + 58 * SCALE
arrow_right = 550 * SCALE - 58 * SCALE
draw.line([(arrow_left, row1_y), (arrow_right, row1_y)], fill=ACCENT, width=3 * SCALE // 2)
draw.polygon(
    [
        (arrow_right, row1_y - 9 * SCALE // 2),
        (arrow_right, row1_y + 9 * SCALE // 2),
        (arrow_right + 14 * SCALE // 2, row1_y),
    ],
    fill=ACCENT,
)

# --- 2행: 튜토리얼 프로젝트 안내 ---
row2_y = 300 * SCALE
draw.text(
    (CENTER_X, row2_y),
    "↓  튜토리얼 프로젝트 · 읽어보세요",
    font=pretendard_body, fill=INK, anchor="mm"
)

# --- 하단 각주 ---
footer_y = H - 26 * SCALE
draw.text(
    (CENTER_X, footer_y),
    "처음 실행 시 확인되지 않은 개발자 경고가 뜨면, 아이콘을 우클릭 → 열기를 선택하세요.",
    font=pretendard_small, fill=INK_MUTED, anchor="mm"
)

img.save(OUT, dpi=(144, 144))
print(f"wrote {OUT} ({W}x{H} @144dpi)")
