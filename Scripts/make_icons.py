#!/usr/bin/env python3
"""Sonnet Create 앱 아이콘 + 브랜드 마크 생성기 (v2.0 인장 & 원고).

6g '잉크 스트로크' 확정안 — 버밀리온 145° 그라데이션(#C2482D→#8E2D18) 스쿼클 위에
깃털을 45° 세 획으로 극단 추상화한 마크. 획은 뒤로 갈수록 흐려지며(불투명도
100/75/45%) 잉크가 마르는 잔상을 남긴다. 곡선 없이, 형태가 아니라 '쓰는 동작'을
새긴다. 획 색은 Paper(#F6F4EF).

출력:
  App/SonnetCreate/Assets.xcassets/AppIcon.appiconset/icon_*.png  (10개 사이즈)
  App/SonnetCreate/Assets.xcassets/BrandMark.imageset/brandmark(.png|@2x.png)
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

# 인장 & 원고 팔레트 (SonnetPalette v4와 동일 계열)
SEAL_LIGHT = (194, 72, 45)    # #C2482D — 그라데이션 시작 (좌상)
SEAL_DEEP = (142, 45, 24)     # #8E2D18 — 그라데이션 끝 (우하)
PAPER = (246, 244, 239)       # #F6F4EF — 획 색

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


def diagonal_gradient(size: int, start: tuple, end: tuple) -> Image.Image:
    """145° 대각 그라데이션 (좌상 → 우하)."""
    grad = Image.new("RGB", (size, size))
    px = grad.load()
    # 145° ≈ 정규화된 (x+y) 축을 따라 보간
    for y in range(0, size, S):
        for x in range(0, size, S):
            t = (x + y) / (2 * (size - 1))
            color = tuple(round(start[i] + (end[i] - start[i]) * t) for i in range(3))
            for dy in range(S):
                for dx in range(S):
                    if x + dx < size and y + dy < size:
                        px[x + dx, y + dy] = color
    return grad


def stroke_layer(size: int, p1: tuple, p2: tuple, width: int, alpha: int) -> Image.Image:
    """둥근 캡 선 한 획 — 겹침 시 알파가 서로를 지우지 않도록 획마다 독립 레이어."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    color = PAPER + (alpha,)
    draw.line([p1, p2], fill=color, width=width)
    r = width / 2
    for p in (p1, p2):
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=color)
    return layer


def render_master() -> Image.Image:
    """1024pt 마스터 (투명 마진 + 그림자 포함)."""
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    squircle = superellipse_mask(ICON_SIZE)

    # 드롭섀도 — 버밀리온 기운이 살짝 도는 부드러운 그림자
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_layer = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (120, 40, 20, 110))
    shadow.paste(shadow_layer, (ICON_ORIGIN, ICON_ORIGIN + 10 * S), squircle)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * S))
    canvas = Image.alpha_composite(canvas, shadow)

    # 스쿼클 본체 — 버밀리온 145° 그라데이션
    body = diagonal_gradient(ICON_SIZE, SEAL_LIGHT, SEAL_DEEP).convert("RGBA")

    # 상단 미세 하이라이트 (유리 느낌 한 스푼)
    highlight = Image.new("L", (ICON_SIZE, ICON_SIZE), 0)
    hl_draw = ImageDraw.Draw(highlight)
    hl_draw.ellipse(
        [-ICON_SIZE * 0.25, -ICON_SIZE * 0.55, ICON_SIZE * 1.25, ICON_SIZE * 0.42],
        fill=18,
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(30 * S))
    body = Image.composite(Image.new("RGBA", body.size, (255, 255, 255, 255)), body, highlight)

    # 잉크 스트로크 3획 — 24 그리드를 아이콘 콘텐츠 영역(중앙 66%)에 사상.
    # 획마다 독립 레이어로 순차 합성 (겹치는 반투명 획이 앞 획을 지우지 않게).
    grid = ICON_SIZE * 0.66 / 24
    origin = ICON_SIZE * 0.17

    def pt(x: float, y: float) -> tuple:
        return (origin + x * grid, origin + y * grid)

    width = round(2.2 * grid)
    for p1, p2, alpha in (
        (pt(4.5, 20.5), pt(19.5, 4.5), 255),
        (pt(9.5, 15.5), pt(15.0, 10.0), 191),
        (pt(12.5, 18.5), pt(18.0, 13.0), 115),
    ):
        body = Image.alpha_composite(body, stroke_layer(ICON_SIZE, p1, p2, width, alpha))

    piece = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    piece.paste(body, (ICON_ORIGIN, ICON_ORIGIN), squircle)
    canvas = Image.alpha_composite(canvas, piece)
    return canvas


def main():
    master = render_master()

    APPICON.mkdir(parents=True, exist_ok=True)
    for pt_size in (16, 32, 128, 256, 512):
        for scale, suffix in ((1, ""), (2, "@2x")):
            px = pt_size * scale
            master.resize((px, px), Image.LANCZOS).save(APPICON / f"icon_{pt_size}x{pt_size}{suffix}.png")
            print(f"appicon {pt_size}x{pt_size}{suffix} -> {px}px")

    # 브랜드 마크 — 같은 아트워크 (60pt/1x·2x)
    BRANDMARK.mkdir(parents=True, exist_ok=True)
    master.resize((512, 512), Image.LANCZOS).save(BRANDMARK / "brandmark@2x.png")
    master.resize((256, 256), Image.LANCZOS).save(BRANDMARK / "brandmark.png")
    print("brandmark 1x/2x")


if __name__ == "__main__":
    main()
