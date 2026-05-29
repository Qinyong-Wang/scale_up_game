#!/usr/bin/env python3
"""Build deterministic brand and task UI icons.

These icons are intentionally not AI cutouts: they are small functional marks
shown at 28-112px, so solid silhouettes are more reliable than detailed art.
"""

from __future__ import annotations

import argparse
from math import cos, pi, sin
from pathlib import Path
from typing import Callable, Iterable

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
ASSET_ROOT = ROOT / "assets" / "sprites" / "ui"
SIZE = 128
SCALE = 4

Color = tuple[int, int, int, int]
Point = tuple[float, float]
Painter = Callable[[ImageDraw.ImageDraw], None]


SLATE: Color = (35, 51, 74, 255)
SLATE_2: Color = (51, 65, 85, 255)
BLUE: Color = (37, 99, 235, 255)
BLUE_2: Color = (59, 130, 246, 255)
CYAN: Color = (6, 182, 212, 255)
CYAN_2: Color = (103, 232, 249, 255)
TEAL: Color = (20, 184, 166, 255)
GREEN: Color = (34, 197, 94, 255)
GREEN_2: Color = (134, 239, 172, 255)
AMBER: Color = (245, 158, 11, 255)
AMBER_2: Color = (253, 224, 71, 255)
ORANGE: Color = (249, 115, 22, 255)
ROSE: Color = (244, 63, 94, 255)
VIOLET: Color = (124, 58, 237, 255)
VIOLET_2: Color = (168, 85, 247, 255)
PINK: Color = (236, 72, 153, 255)
WHITE: Color = (248, 250, 252, 255)
WHITE_SOFT: Color = (226, 232, 240, 255)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--category",
        choices=["all", "brand", "task"],
        default="all",
        help="Which icon group to build.",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=ASSET_ROOT,
        help="Directory containing category folders, defaults to assets/sprites/ui.",
    )
    args = parser.parse_args()

    if args.category in ("all", "brand"):
        _write_group(args.output_root / "brand", BRAND_ICONS)
    if args.category in ("all", "task"):
        _write_group(args.output_root / "task", TASK_ICONS)
    return 0


def _write_group(directory: Path, icons: dict[str, Painter]) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for name, painter in icons.items():
        image = _render(painter)
        path = directory / f"{name}.png"
        image.save(path)
        print(path)


def _render(painter: Painter) -> Image.Image:
    image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image, "RGBA")
    painter(draw)
    try:
        resampling = Image.Resampling.LANCZOS
    except AttributeError:
        resampling = Image.LANCZOS
    return image.resize((SIZE, SIZE), resampling)


def _xy(point: Point) -> tuple[int, int]:
    return (round(point[0] * SCALE), round(point[1] * SCALE))


def _box(box: tuple[float, float, float, float]) -> tuple[int, int, int, int]:
    return tuple(round(v * SCALE) for v in box)


def _points(points: Iterable[Point]) -> list[tuple[int, int]]:
    return [_xy(p) for p in points]


def _line(
    draw: ImageDraw.ImageDraw,
    points: Iterable[Point],
    fill: Color,
    width: float,
    closed: bool = False,
) -> None:
    scaled = _points(points)
    if closed and scaled:
        scaled.append(scaled[0])
    try:
        draw.line(scaled, fill=fill, width=round(width * SCALE), joint="curve")
    except TypeError:
        draw.line(scaled, fill=fill, width=round(width * SCALE))
    radius = width * 0.5
    for x, y in scaled[:1] + scaled[-1:]:
        draw.ellipse(
            (
                round(x - radius * SCALE),
                round(y - radius * SCALE),
                round(x + radius * SCALE),
                round(y + radius * SCALE),
            ),
            fill=fill,
        )


def _poly(draw: ImageDraw.ImageDraw, points: Iterable[Point], fill: Color) -> None:
    draw.polygon(_points(points), fill=fill)


def _ellipse(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], fill: Color) -> None:
    draw.ellipse(_box(box), fill=fill)


def _rounded(
    draw: ImageDraw.ImageDraw,
    box: tuple[float, float, float, float],
    radius: float,
    fill: Color,
) -> None:
    draw.rounded_rectangle(_box(box), radius=round(radius * SCALE), fill=fill)


def _arc(
    draw: ImageDraw.ImageDraw,
    box: tuple[float, float, float, float],
    start: float,
    end: float,
    fill: Color,
    width: float,
) -> None:
    draw.arc(_box(box), start=start, end=end, fill=fill, width=round(width * SCALE))


def _regular_polygon(cx: float, cy: float, radius: float, sides: int, rotation: float) -> list[Point]:
    return [
        (
            cx + cos(rotation + 2.0 * pi * i / sides) * radius,
            cy + sin(rotation + 2.0 * pi * i / sides) * radius,
        )
        for i in range(sides)
    ]


def _brand_01(draw: ImageDraw.ImageDraw) -> None:
    _poly(draw, [(64, 12), (116, 64), (64, 116), (12, 64)], CYAN)
    _poly(draw, [(64, 26), (102, 64), (64, 102), (26, 64)], BLUE_2)
    _poly(draw, [(64, 42), (86, 64), (64, 86), (42, 64)], WHITE)
    _poly(draw, [(64, 51), (77, 64), (64, 77), (51, 64)], TEAL)
    _poly(draw, [(64, 91), (79, 106), (64, 121), (49, 106)], CYAN_2)


def _brand_02(draw: ImageDraw.ImageDraw) -> None:
    _ellipse(draw, (19, 19, 109, 109), (14, 165, 190, 255))
    _poly(draw, [(16, 72), (56, 20), (112, 58), (75, 70), (66, 112), (52, 71)], CYAN)
    _poly(draw, [(56, 20), (75, 70), (112, 58)], BLUE_2)
    _poly(draw, [(16, 72), (52, 71), (33, 94)], TEAL)
    _poly(draw, [(52, 71), (75, 70), (66, 112)], BLUE)
    _poly(draw, [(40, 47), (56, 20), (59, 63)], WHITE_SOFT)


def _brand_03(draw: ImageDraw.ImageDraw) -> None:
    _poly(draw, [(10, 104), (52, 24), (88, 104)], BLUE)
    _poly(draw, [(42, 104), (76, 34), (118, 104)], CYAN)
    _poly(draw, [(52, 24), (66, 57), (42, 56)], WHITE)
    _poly(draw, [(76, 34), (91, 62), (64, 61)], WHITE_SOFT)
    _poly(draw, [(10, 104), (118, 104), (104, 114), (24, 114)], SLATE_2)


def _brand_04(draw: ImageDraw.ImageDraw) -> None:
    _poly(draw, [(64, 12), (112, 39), (98, 99), (64, 118), (30, 99), (16, 39)], VIOLET)
    _poly(draw, [(64, 12), (112, 39), (64, 48)], CYAN)
    _poly(draw, [(64, 12), (64, 48), (16, 39)], PINK)
    _poly(draw, [(16, 39), (64, 48), (30, 99)], BLUE)
    _poly(draw, [(112, 39), (98, 99), (64, 48)], BLUE_2)
    _poly(draw, [(30, 99), (64, 48), (64, 118)], VIOLET_2)
    _poly(draw, [(98, 99), (64, 118), (64, 48)], PINK)


def _brand_05(draw: ImageDraw.ImageDraw) -> None:
    _ellipse(draw, (20, 20, 108, 108), AMBER)
    _poly(
        draw,
        [
            (64, 17),
            (76, 51),
            (111, 64),
            (76, 77),
            (64, 111),
            (52, 77),
            (17, 64),
            (52, 51),
        ],
        AMBER_2,
    )
    _ellipse(draw, (50, 50, 78, 78), WHITE)


def _brand_06(draw: ImageDraw.ImageDraw) -> None:
    _ellipse(draw, (20, 20, 108, 108), GREEN_2)
    _ellipse(draw, (35, 35, 93, 93), GREEN)
    _ellipse(draw, (54, 54, 74, 74), PINK)
    _arc(draw, (12, 29, 116, 99), 198, 342, TEAL, 8)
    _arc(draw, (12, 29, 116, 99), 18, 162, TEAL, 8)
    _arc(draw, (29, 12, 99, 116), 108, 252, BLUE_2, 7)
    _arc(draw, (29, 12, 99, 116), 288, 72, BLUE_2, 7)


def _brand_07(draw: ImageDraw.ImageDraw) -> None:
    _ellipse(draw, (18, 20, 110, 112), (21, 128, 61, 255))
    _line(draw, [(64, 106), (64, 71)], SLATE_2, 9)
    _poly(draw, [(62, 71), (16, 50), (22, 29), (56, 30), (77, 57)], GREEN)
    _poly(draw, [(66, 71), (112, 50), (106, 29), (72, 30), (51, 57)], GREEN_2)
    _poly(draw, [(20, 50), (57, 39), (62, 71)], TEAL)
    _poly(draw, [(108, 50), (71, 39), (66, 71)], TEAL)
    _line(draw, [(64, 76), (35, 48)], WHITE, 4)
    _line(draw, [(64, 76), (93, 48)], WHITE, 4)


def _brand_08(draw: ImageDraw.ImageDraw) -> None:
    points: list[Point] = []
    for i in range(181):
        t = 2.0 * pi * i / 180.0
        points.append((64 + 42 * sin(t), 64 + 24 * sin(2 * t)))
    _line(draw, points, BLUE_2, 26, closed=True)
    _line(draw, points, CYAN, 14, closed=True)


def _brand_09(draw: ImageDraw.ImageDraw) -> None:
    _poly(draw, [(64, 12), (112, 38), (64, 64), (16, 38)], AMBER_2)
    _poly(draw, [(16, 38), (64, 64), (64, 116), (16, 90)], VIOLET)
    _poly(draw, [(112, 38), (64, 64), (64, 116), (112, 90)], ORANGE)
    _poly(draw, [(64, 64), (112, 38), (112, 90), (64, 116)], PINK)
    _poly(draw, [(16, 38), (64, 64), (112, 38), (64, 12)], AMBER)


def _brand_10(draw: ImageDraw.ImageDraw) -> None:
    _ellipse(draw, (20, 18, 108, 112), (30, 64, 175, 255))
    _poly(draw, [(64, 10), (85, 45), (80, 89), (64, 108), (48, 89), (43, 45)], BLUE)
    _ellipse(draw, (53, 28, 75, 50), CYAN_2)
    _poly(draw, [(48, 76), (25, 103), (51, 96)], ROSE)
    _poly(draw, [(80, 76), (103, 103), (77, 96)], ROSE)
    _poly(draw, [(56, 99), (64, 122), (72, 99)], AMBER_2)
    _poly(draw, [(50, 48), (78, 48), (75, 86), (53, 86)], WHITE_SOFT)
    _line(draw, [(64, 12), (64, 27)], ROSE, 7)


def _brand_11(draw: ImageDraw.ImageDraw) -> None:
    _ellipse(draw, (20, 18, 108, 112), (190, 82, 20, 255))
    _poly(draw, [(74, 10), (27, 73), (55, 73), (43, 118), (101, 50), (70, 53)], ORANGE)
    _poly(draw, [(79, 16), (44, 64), (68, 63), (56, 102), (91, 56), (64, 58)], AMBER_2)


def _brand_12(draw: ImageDraw.ImageDraw) -> None:
    _poly(draw, _regular_polygon(64, 64, 54, 6, pi / 6.0), GREEN)
    _poly(draw, _regular_polygon(64, 64, 39, 6, pi / 6.0), GREEN_2)
    _ellipse(draw, (49, 49, 79, 79), WHITE)
    _ellipse(draw, (56, 56, 72, 72), TEAL)


def _brand_13(draw: ImageDraw.ImageDraw) -> None:
    _poly(draw, [(13, 55), (116, 19), (82, 110), (62, 78)], BLUE_2)
    _poly(draw, [(13, 55), (62, 78), (31, 91)], VIOLET)
    _poly(draw, [(62, 78), (116, 19), (77, 67)], WHITE_SOFT)
    _poly(draw, [(62, 78), (82, 110), (73, 72)], BLUE)


def _brand_14(draw: ImageDraw.ImageDraw) -> None:
    _ellipse(draw, (15, 15, 113, 113), BLUE)
    blades = [
        (64, 19, 96, 36, 77, 61),
        (96, 36, 101, 74, 70, 69),
        (101, 74, 72, 104, 61, 73),
        (72, 104, 33, 91, 51, 66),
        (33, 91, 27, 52, 58, 59),
        (27, 52, 56, 24, 67, 55),
    ]
    colors = [CYAN, TEAL, VIOLET, PINK, BLUE_2, CYAN_2]
    for blade, color in zip(blades, colors):
        _poly(draw, [(blade[0], blade[1]), (blade[2], blade[3]), (blade[4], blade[5])], color)
    _ellipse(draw, (47, 47, 81, 81), WHITE)
    _ellipse(draw, (56, 56, 72, 72), SLATE)


def _task_pretrain(draw: ImageDraw.ImageDraw) -> None:
    _rounded(draw, (20, 24, 108, 104), 18, SLATE)
    _rounded(draw, (30, 34, 98, 94), 12, BLUE)
    _ellipse(draw, (45, 31, 83, 69), CYAN_2)
    _ellipse(draw, (53, 39, 75, 61), TEAL)
    _line(draw, [(64, 17), (64, 34)], BLUE_2, 8)
    _line(draw, [(39, 82), (89, 82)], WHITE_SOFT, 8)
    _poly(draw, [(51, 104), (64, 122), (77, 104)], AMBER_2)


def _task_posttrain(draw: ImageDraw.ImageDraw) -> None:
    _rounded(draw, (18, 26, 110, 102), 16, SLATE)
    _rounded(draw, (31, 38, 97, 89), 11, BLUE_2)
    for x in (26, 40, 88, 102):
        _line(draw, [(x, 18), (x, 30)], CYAN, 5)
        _line(draw, [(x, 98), (x, 112)], CYAN, 5)
    _ellipse(draw, (47, 45, 81, 79), VIOLET_2)
    _ellipse(draw, (55, 53, 73, 71), WHITE)
    _line(draw, [(78, 30), (100, 52), (86, 66)], AMBER_2, 10)
    _line(draw, [(88, 41), (70, 59)], AMBER_2, 10)


def _task_evaluate(draw: ImageDraw.ImageDraw) -> None:
    _rounded(draw, (24, 18, 104, 110), 14, SLATE)
    _rounded(draw, (34, 30, 74, 92), 8, BLUE_2)
    for y in (42, 56, 70):
        _line(draw, [(42, y), (66, y)], WHITE_SOFT, 5)
    _ellipse(draw, (65, 50, 107, 92), CYAN_2)
    _arc(draw, (71, 56, 101, 86), 200, 340, BLUE, 7)
    _line(draw, [(86, 73), (98, 61)], ROSE, 5)
    _ellipse(draw, (82, 69, 90, 77), WHITE)
    _rounded(draw, (43, 98, 92, 113), 7, TEAL)


def _task_data_collection(draw: ImageDraw.ImageDraw) -> None:
    _ellipse(draw, (25, 19, 103, 45), CYAN_2)
    _rounded(draw, (25, 31, 103, 89), 10, BLUE)
    _ellipse(draw, (25, 75, 103, 101), TEAL)
    _ellipse(draw, (34, 28, 94, 43), WHITE_SOFT)
    _poly(draw, [(37, 44), (91, 44), (75, 75), (53, 75)], CYAN)
    for x, y, color in [
        (48, 18, AMBER_2),
        (64, 14, WHITE),
        (80, 18, GREEN_2),
        (55, 59, WHITE),
        (72, 61, WHITE),
    ]:
        _ellipse(draw, (x - 5, y - 5, x + 5, y + 5), color)
    _rounded(draw, (38, 94, 90, 113), 7, SLATE_2)


def _task_tech_research(draw: ImageDraw.ImageDraw) -> None:
    _ellipse(draw, (36, 13, 92, 69), AMBER_2)
    _rounded(draw, (45, 59, 83, 83), 8, ORANGE)
    _rounded(draw, (36, 80, 92, 106), 10, BLUE)
    _rounded(draw, (45, 101, 83, 116), 7, SLATE)
    _line(draw, [(45, 50), (83, 50)], WHITE, 6)
    _line(draw, [(64, 25), (64, 51)], WHITE, 5)
    _line(draw, [(31, 92), (18, 92), (18, 72)], CYAN, 6)
    _line(draw, [(97, 92), (110, 92), (110, 72)], CYAN, 6)
    _ellipse(draw, (13, 67, 23, 77), CYAN_2)
    _ellipse(draw, (105, 67, 115, 77), CYAN_2)


BRAND_ICONS: dict[str, Painter] = {
    "brand-01": _brand_01,
    "brand-02": _brand_02,
    "brand-03": _brand_03,
    "brand-04": _brand_04,
    "brand-05": _brand_05,
    "brand-06": _brand_06,
    "brand-07": _brand_07,
    "brand-08": _brand_08,
    "brand-09": _brand_09,
    "brand-10": _brand_10,
    "brand-11": _brand_11,
    "brand-12": _brand_12,
    "brand-13": _brand_13,
    "brand-14": _brand_14,
}

TASK_ICONS: dict[str, Painter] = {
    "data_collection": _task_data_collection,
    "evaluate": _task_evaluate,
    "posttrain": _task_posttrain,
    "pretrain": _task_pretrain,
    "tech_research": _task_tech_research,
}


if __name__ == "__main__":
    raise SystemExit(main())
