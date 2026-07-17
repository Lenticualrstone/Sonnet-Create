#!/usr/bin/env python3
"""Sonnet Create 앱 아이콘 + 브랜드 마크 생성기 (v1.3 통합 테마).

딥네이비(#031C35) 그라데이션 스쿼클 위에 백색 깃털 — 앱의 "백색 캔버스 + 네이비
액센트" 정체성을 아이콘에서는 반전시켜 Dock에서의 존재감을 준다. 깃털 실루엣은
v1.2 아트워크에서 추출한 마스크(Scripts/assets/feather-mask.png)를 재사용한다 —
팔레트가 또 바뀌면 이 스크립트만 다시 돌리면 된다.

출력:
  App/SonnetCreate/Assets.xcassets/AppIcon.appiconset/icon_*.png  (10개 사이즈)
  App/SonnetCreate/Assets.xcassets/BrandMark.imageset/brandmark(.png|@2x.png)

v1.3 테마 일원화로 AppIcon-Pilgrimage/System, BrandMark-Pilgrimage/System
변형 세트는 삭제됐다 — 이 스크립트는 단일 세트만 만든다.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parents[1]
APPICON = REPO / "App/SonnetCreate/Assets.xcassets/AppIcon.appiconset"
BRANDMARK = REPO / "App/SonnetCreate/Assets.xcassets/BrandMark.imageset"

# 4x 슈퍼샘플링 — 축소 시 안티앨리어싱 확보
S = 4
CANVAS = 1024 * S

# 통합 팔레트 (SonnetPalette와 동일 계열)
NAVY_DEEP = (3, 28, 53)       # #031C35 — 브랜드 액센트
NAVY_LIGHT = (13, 48, 80)     # 그라데이션 상단
WHITE = (255, 255, 255)

# Apple 아이콘 그리드: 1024 캔버스에 콘텐츠 824px 중앙 배치
ICON_SIZE = 824 * S
ICON_ORIGIN = (CANVAS - ICON_SIZE) // 2


def superellipse_mask(size: int, n: float = 4.6) -> Image.Image:
    """Apple 스쿼클 근사 — |x|^n + |y|^n = 1 초타원 마스크."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    half = size / 2
    points = []
    steps = 720
    for i in range(steps):
        theta = 2 * math.pi * i / steps
        c, s = math.cos(theta), math.sin(theta)
        x = half + half * math.copysign(abs(c) ** (2 / n), c)
        y = half + half * math.copysign(abs(s) ** (2 / n), s)
        points.append((x, y))
    draw.polygon(points, fill=255)
    return mask


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    """세로 그라데이션 타일."""
    grad = Image.new("RGB", (1, size))
    px = grad.load()
    for y in range(size):
        t = y / (size - 1)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return grad.resize((size, size))


# ---------------------------------------------------------------------------
# 깃털 실루엣 — v1.2 아이콘 아트워크에서 추출한 마스크(Scripts/assets/feather-mask.png).
# 실루엣은 검증된 기존 디자인을 유지하고 팔레트만 통합 테마로 갈아입힌다.
# 마스크는 1024 캔버스 기준이며 스쿼클이 (101,101)-(923,923)에 있었다 —
# 새 그리드(824 중앙)와 동일하므로 그 영역을 잘라 그대로 쓴다.
# ---------------------------------------------------------------------------

FEATHER_SRC = REPO / "Scripts/assets/feather-mask.png"


def load_feather_mask(size: int) -> Image.Image:
    mask = Image.open(FEATHER_SRC).convert("L")
    return mask.crop((101, 101, 923, 923)).resize((size, size), Image.LANCZOS)


def render_master() -> Image.Image:
    """1024pt 마스터 (투명 마진 + 그림자 포함)."""
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    squircle = superellipse_mask(ICON_SIZE)

    # 드롭섀도 — 기존 아이콘과 같은 결 (아래로 살짝, 부드럽게)
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_layer = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 110))
    shadow.paste(shadow_layer, (ICON_ORIGIN, ICON_ORIGIN + 10 * S), squircle)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * S))
    canvas = Image.alpha_composite(canvas, shadow)

    # 스쿼클 본체 — 네이비 그라데이션
    body = vertical_gradient(ICON_SIZE, NAVY_LIGHT, NAVY_DEEP).convert("RGBA")

    # 상단 미세 하이라이트 (유리 느낌 한 스푼)
    highlight = Image.new("L", (ICON_SIZE, ICON_SIZE), 0)
    hl_draw = ImageDraw.Draw(highlight)
    hl_draw.ellipse(
        [-ICON_SIZE * 0.25, -ICON_SIZE * 0.55, ICON_SIZE * 1.25, ICON_SIZE * 0.42],
        fill=26,
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(30 * S))
    body = Image.composite(Image.new("RGBA", body.size, (255, 255, 255, 255)), body, highlight)

    # 깃털 (백색) — 슬릿/노치는 마스크에서 빠져 배경이 비친다
    feather = load_feather_mask(ICON_SIZE)
    white_layer = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), WHITE + (255,))
    body.paste(white_layer, (0, 0), feather)

    piece = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    piece.paste(body, (ICON_ORIGIN, ICON_ORIGIN), squircle)
    canvas = Image.alpha_composite(canvas, piece)
    return canvas


def main():
    master = render_master()

    APPICON.mkdir(parents=True, exist_ok=True)
    for pt in (16, 32, 128, 256, 512):
        for scale, suffix in ((1, ""), (2, "@2x")):
            px = pt * scale
            master.resize((px, px), Image.LANCZOS).save(APPICON / f"icon_{pt}x{pt}{suffix}.png")
            print(f"appicon {pt}x{pt}{suffix} -> {px}px")

    # 브랜드 마크 — 헤더 18pt 마크용, 같은 아트워크 (60pt/1x·2x)
    BRANDMARK.mkdir(parents=True, exist_ok=True)
    master.resize((512, 512), Image.LANCZOS).save(BRANDMARK / "brandmark@2x.png")
    master.resize((256, 256), Image.LANCZOS).save(BRANDMARK / "brandmark.png")
    print("brandmark 1x/2x")


if __name__ == "__main__":
    main()
