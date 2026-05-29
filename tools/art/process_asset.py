#!/usr/bin/env python3
"""Postprocess generated 2D image assets for Scaling Up.

This tool is intentionally deterministic. It does not create art or prompts; it
cleans solid-magenta raw images, extracts foreground components, centers them on
transparent canvases, and writes QA metadata for review.
"""

from __future__ import annotations

import argparse
import json
import logging
import math
import re
import sys
from collections import deque
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageFilter


MAGENTA = (255, 0, 255)
LOGGER = logging.getLogger("art_harness")


class AssetProcessingError(RuntimeError):
    """Raised when a processed asset fails the acceptance contract."""


def color_distance(rgb: tuple[int, int, int], target: tuple[int, int, int] = MAGENTA) -> float:
    r, g, b = rgb
    tr, tg, tb = target
    return math.sqrt((r - tr) ** 2 + (g - tg) ** 2 + (b - tb) ** 2)


def _color_distance_sq(rgb: tuple[int, int, int], target: tuple[int, int, int]) -> int:
    r, g, b = rgb
    tr, tg, tb = target
    return (r - tr) ** 2 + (g - tg) ** 2 + (b - tb) ** 2


def _sample_background_refs(img: Image.Image, sample: int = 6) -> list[tuple[int, int, int]]:
    rgba = img.convert("RGBA")
    px = rgba.load()
    width, height = img.size
    if width == 0 or height == 0:
        return [MAGENTA]
    anchors = (
        (0, 0),
        (width - 1, 0),
        (0, height - 1),
        (width - 1, height - 1),
        (width // 2, 0),
        (width // 2, height - 1),
        (0, height // 2),
        (width - 1, height // 2),
    )
    refs: list[tuple[int, int, int]] = []
    half = max(0, sample // 2)
    for cx, cy in anchors:
        rs = gs = bs = n = 0
        for dx in range(-half, half + 1):
            for dy in range(-half, half + 1):
                x = min(max(cx + dx, 0), width - 1)
                y = min(max(cy + dy, 0), height - 1)
                r, g, b, _ = px[x, y]
                rs += r
                gs += g
                bs += b
                n += 1
        refs.append((rs // n, gs // n, bs // n))
    return refs


def remove_bg_sampled(img: Image.Image, tolerance: int = 70, sample: int = 6) -> tuple[Image.Image, dict[str, Any]]:
    """Remove only border-connected pixels close to sampled background colors.

    This is safer for generated images whose "magenta" background became a
    grey/pink studio backdrop: it avoids global high-threshold chroma keying,
    which can delete similar-colored highlights inside the foreground.
    """
    out = img.convert("RGBA")
    width, height = out.size
    data = list(out.getdata())
    total = width * height
    refs = _sample_background_refs(out, sample)
    tol_sq = tolerance * tolerance

    def is_background(index: int) -> bool:
        r, g, b, a = data[index]
        if a <= 0:
            return True
        return any(_color_distance_sq((r, g, b), ref) <= tol_sq for ref in refs)

    visited = bytearray(total)
    queue: list[int] = []

    def add(index: int) -> None:
        if not visited[index]:
            visited[index] = 1
            queue.append(index)

    if width == 0 or height == 0:
        return out, {"ok": True, "mode": "sampled", "removed_pixels": 0, "refs": refs}
    for x in range(width):
        add(x)
        add((height - 1) * width + x)
    for y in range(height):
        add(y * width)
        add(y * width + width - 1)

    removed = 0
    head = 0
    while head < len(queue):
        index = queue[head]
        head += 1
        if not is_background(index):
            continue
        if data[index][3] > 0:
            data[index] = (0, 0, 0, 0)
            removed += 1
        x = index % width
        y = index // width
        if x > 0:
            add(index - 1)
        if x < width - 1:
            add(index + 1)
        if y > 0:
            add(index - width)
        if y < height - 1:
            add(index + width)

    out.putdata(data)
    return out, {
        "ok": True,
        "mode": "sampled",
        "tolerance": tolerance,
        "sample": sample,
        "refs": [list(ref) for ref in refs],
        "removed_pixels": removed,
    }


def flood_corners_to_magenta(img: Image.Image, tol: int = 70, sample: int = 4) -> Image.Image:
    """Recolor the border-connected background to pure magenta, in place on a copy.

    flux 时常无视 prompt 里的 "magenta background", 把底画成灰 / 浅青等纯色 (见
    design/图片素材生成流程.md §8bis 坑)。本步从四角取参考色, 做连通域 BFS 漫水:
    凡是与画面边缘连通、且接近某个角色的像素, 重染成纯洋红, 再交给 remove_bg_magenta
    去背。连通性保证不会误伤主体内部同色像素 (如灰色上衣), 因为它们不与边缘相连。
    主体轮廓与背景对比强 (距离 >> tol) 时停在轮廓上。
    """
    out = img.convert("RGBA")
    px = out.load()
    w, h = out.size
    if w == 0 or h == 0:
        return out
    refs: list[tuple[int, int, int]] = []
    for cx, cy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        rs = gs = bs = n = 0
        for dx in range(sample):
            for dy in range(sample):
                x = min(max(cx + (dx if cx == 0 else -dx), 0), w - 1)
                y = min(max(cy + (dy if cy == 0 else -dy), 0), h - 1)
                r, g, b, _ = px[x, y]
                rs += r; gs += g; bs += b; n += 1
        refs.append((rs // n, gs // n, bs // n))

    def is_bg(r: int, g: int, b: int) -> bool:
        return any(color_distance((r, g, b), ref) < tol for ref in refs)

    visited: set[tuple[int, int]] = set()
    queue: deque[tuple[int, int]] = deque()
    for x in range(w):
        queue.append((x, 0)); queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y)); queue.append((w - 1, y))
    while queue:
        x, y = queue.popleft()
        if (x, y) in visited or x < 0 or x >= w or y < 0 or y >= h:
            continue
        visited.add((x, y))
        r, g, b, _ = px[x, y]
        if is_bg(r, g, b):
            px[x, y] = (255, 0, 255, 255)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    nxt = (x + dx, y + dy)
                    if nxt not in visited:
                        queue.append(nxt)
    return out


def defringe_alpha(img: Image.Image, radius: int) -> Image.Image:
    """Erode the alpha mask by `radius` px to shave the anti-aliased edge ring.

    去背后轮廓常残留一圈半透明 / 混色像素 (写实头像的灰棚拍底光晕、logo 的洋红边),
    在对比背景上显成"白边/背景透视"。对 alpha 做形态学腐蚀 (MinFilter) 把最外 radius
    px 削成透明, 干净收边。radius<=0 不动。
    """
    if radius <= 0:
        return img
    out = img.convert("RGBA")
    a = out.getchannel("A").filter(ImageFilter.MinFilter(2 * radius + 1))
    out.putalpha(a)
    return out


def remove_bg_magenta(img: Image.Image, threshold: int = 100, edge_threshold: int = 120) -> Image.Image:
    """Remove solid magenta background and near-magenta edge fringe."""
    out = img.convert("RGBA")
    pixels = out.load()
    width, height = out.size

    for x in range(width):
        for y in range(height):
            r, g, b, a = pixels[x, y]
            if a > 0 and color_distance((r, g, b)) < threshold:
                pixels[x, y] = (0, 0, 0, 0)

    visited: set[tuple[int, int]] = set()
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if (x, y) in visited or x < 0 or x >= width or y < 0 or y >= height:
            continue
        visited.add((x, y))
        r, g, b, a = pixels[x, y]
        should_expand = a == 0
        if a > 0 and color_distance((r, g, b)) < edge_threshold:
            pixels[x, y] = (0, 0, 0, 0)
            should_expand = True
        if should_expand:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    nxt = (x + dx, y + dy)
                    if nxt not in visited:
                        queue.append(nxt)
    return out


def trim_border(img: Image.Image, px: int) -> Image.Image:
    if px <= 0:
        return img
    width, height = img.size
    if width <= px * 2 or height <= px * 2:
        return img
    return img.crop((px, px, width - px, height - px))


def clean_edges(img: Image.Image, depth: int) -> Image.Image:
    if depth <= 0:
        return img
    out = img.copy()
    pixels = out.load()
    width, height = out.size
    for d in range(depth):
        for x in range(width):
            for y in (d, height - 1 - d):
                if 0 <= y < height:
                    r, g, b, a = pixels[x, y]
                    if a > 0 and ((r < 40 and g < 40 and b < 40) or color_distance((r, g, b)) < 150):
                        pixels[x, y] = (0, 0, 0, 0)
        for y in range(height):
            for x in (d, width - 1 - d):
                if 0 <= x < width:
                    r, g, b, a = pixels[x, y]
                    if a > 0 and ((r < 40 and g < 40 and b < 40) or color_distance((r, g, b)) < 150):
                        pixels[x, y] = (0, 0, 0, 0)
    return out


def connected_components(img: Image.Image, min_area: int = 1) -> list[dict[str, Any]]:
    alpha = img.getchannel("A")
    width, height = img.size
    pixels = alpha.tobytes()
    total = width * height
    visited = bytearray(total)
    components: list[dict[str, Any]] = []

    for start in range(total):
        if pixels[start] == 0 or visited[start]:
            continue
        queue: list[int] = [start]
        visited[start] = 1
        coords: list[int] = []
        sx = start % width
        sy = start // width
        min_x = max_x = sx
        min_y = max_y = sy
        touches_edge = sx == 0 or sy == 0 or sx == width - 1 or sy == height - 1
        head = 0

        while head < len(queue):
            index = queue[head]
            head += 1
            coords.append(index)
            cx = index % width
            cy = index // width
            min_x = min(min_x, cx)
            min_y = min(min_y, cy)
            max_x = max(max_x, cx)
            max_y = max(max_y, cy)
            if cx == 0 or cy == 0 or cx == width - 1 or cy == height - 1:
                touches_edge = True
            if cx > 0:
                nxt = index - 1
                if pixels[nxt] > 0 and not visited[nxt]:
                    visited[nxt] = 1
                    queue.append(nxt)
            if cx < width - 1:
                nxt = index + 1
                if pixels[nxt] > 0 and not visited[nxt]:
                    visited[nxt] = 1
                    queue.append(nxt)
            if cy > 0:
                nxt = index - width
                if pixels[nxt] > 0 and not visited[nxt]:
                    visited[nxt] = 1
                    queue.append(nxt)
            if cy < height - 1:
                nxt = index + width
                if pixels[nxt] > 0 and not visited[nxt]:
                    visited[nxt] = 1
                    queue.append(nxt)

        if len(coords) >= min_area:
            components.append(
                {
                    "area": len(coords),
                    "bbox": (min_x, min_y, max_x + 1, max_y + 1),
                    "touches_edge": touches_edge,
                    "coords": coords,
                    "image_width": width,
                }
            )

    components.sort(key=lambda item: int(item["area"]), reverse=True)
    return components


def alpha_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    return img.getchannel("A").getbbox()


def pad_bbox(
    bbox: tuple[int, int, int, int],
    padding: int,
    width: int,
    height: int,
) -> tuple[int, int, int, int]:
    x0, y0, x1, y1 = bbox
    return (
        max(0, x0 - padding),
        max(0, y0 - padding),
        min(width, x1 + padding),
        min(height, y1 + padding),
    )


def bbox_touches_edge(
    bbox: tuple[int, int, int, int] | None,
    width: int,
    height: int,
    margin: int,
) -> bool:
    if bbox is None:
        return False
    x0, y0, x1, y1 = bbox
    return x0 <= margin or y0 <= margin or x1 >= width - margin or y1 >= height - margin


def mask_to_component(img: Image.Image, component: dict[str, Any]) -> Image.Image:
    selected = Image.new("RGBA", img.size, (0, 0, 0, 0))
    src_data = list(img.getdata())
    dst_data = [(0, 0, 0, 0)] * len(src_data)
    width = int(component.get("image_width", img.width))
    for coord in component["coords"]:
        if isinstance(coord, int):
            index = coord
        else:
            x, y = coord
            index = y * width + x
        dst_data[index] = src_data[index]
    selected.putdata(dst_data)
    return selected


def extract_foreground(
    img: Image.Image,
    *,
    component_mode: str = "all",
    component_padding: int = 0,
    min_component_area: int = 1,
    edge_touch_margin: int = 0,
    trim_border_px: int = 0,
    edge_clean_depth: int = 0,
) -> tuple[Image.Image | None, dict[str, Any]]:
    frame = trim_border(img.convert("RGBA"), trim_border_px)
    frame = clean_edges(frame, edge_clean_depth)
    components: list[dict[str, Any]] = []
    selected_component = None

    if component_mode == "largest":
        components = connected_components(frame, min_component_area)
    if component_mode == "largest" and components:
        selected_component = components[0]
        frame = mask_to_component(frame, selected_component)
        bbox = tuple(selected_component["bbox"])
    else:
        bbox = alpha_bbox(frame)

    padded_bbox = pad_bbox(bbox, component_padding, frame.width, frame.height) if bbox else None
    edge_touch = bbox_touches_edge(bbox, frame.width, frame.height, edge_touch_margin)
    foreground = frame.crop(padded_bbox) if padded_bbox else None

    return foreground, {
        "component_mode": component_mode,
        "component_count": len(components) if components else None,
        "selected_component_area": int(selected_component["area"]) if selected_component else None,
        "selected_component_bbox": list(selected_component["bbox"]) if selected_component else None,
        "crop_bbox": list(bbox) if bbox else None,
        "padded_crop_bbox": list(padded_bbox) if padded_bbox else None,
        "edge_touch": edge_touch,
        "output_size": list(foreground.size) if foreground else [0, 0],
    }


def center_on_canvas(
    img: Image.Image,
    *,
    size: int,
    fit_scale: float,
    align: str,
) -> tuple[Image.Image, dict[str, Any]]:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if img.width <= 0 or img.height <= 0:
        return canvas, {"output_size": [0, 0], "paste_position": [0, 0]}

    scale = min(size / img.width, size / img.height) * fit_scale
    new_width = max(1, int(img.width * scale))
    new_height = max(1, int(img.height * scale))
    resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
    paste_x = (size - new_width) // 2
    if align in {"bottom", "feet"}:
        pad = max(0, int(size * (1 - fit_scale) * 0.5))
        paste_y = size - new_height - pad
    else:
        paste_y = (size - new_height) // 2
    canvas.alpha_composite(resized, (paste_x, paste_y))
    return canvas, {"output_size": [new_width, new_height], "paste_position": [paste_x, paste_y]}


def sanitize_slug(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip().lower()).strip("-")
    return slug or "asset"


def parse_labels(labels: str | None, labels_file: Path | None, expected_count: int, prefix: str) -> list[str]:
    parsed: list[str] = []
    if labels:
        parsed = [item.strip() for item in labels.split(",")]
    if labels_file:
        parsed = [
            line.strip()
            for line in labels_file.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
    if len(parsed) > expected_count:
        raise AssetProcessingError(f"Got {len(parsed)} labels for {expected_count} cells.")
    if not parsed:
        parsed = [f"{prefix}-{index + 1}" for index in range(expected_count)]
    parsed.extend(f"{prefix}-{index + 1}" for index in range(len(parsed), expected_count))
    out: list[str] = []
    for label in parsed:
        if label.lower() in {"", "empty", "skip", "-"}:
            out.append("")
        else:
            out.append(sanitize_slug(label))
    return out


def iter_cells(img: Image.Image, rows: int, cols: int) -> Iterable[tuple[int, int, tuple[int, int, int, int], Image.Image]]:
    cell_width = img.width // cols
    cell_height = img.height // rows
    for row in range(rows):
        for col in range(cols):
            box = (col * cell_width, row * cell_height, (col + 1) * cell_width, (row + 1) * cell_height)
            yield row, col, box, img.crop(box)


def write_prompt(out_dir: Path, prompt: str | None, prompt_file: Path | None) -> str:
    prompt_text = ""
    if prompt_file:
        prompt_text = prompt_file.read_text(encoding="utf-8")
    elif prompt:
        prompt_text = prompt
    if prompt_text:
        (out_dir / "prompt-used.txt").write_text(prompt_text, encoding="utf-8")
    return prompt_text


def write_manifest(out_dir: Path, metadata: dict[str, Any]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "pipeline-meta.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )


def _common_meta(args: argparse.Namespace, mode: str, prompt_text: str) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "pipeline": "agi_asset_harness",
        "mode": mode,
        "ok": True,
        "input": str(args.input),
        "prompt": prompt_text,
        "size": args.size,
        "fit_scale": args.fit_scale,
        "align": args.align,
        "threshold": args.threshold,
        "edge_threshold": args.edge_threshold,
        "background_mode": args.background_mode,
        "background_tolerance": args.background_tolerance,
        "flood_bg": args.flood_bg,
        "flood_bg_tol": args.flood_bg_tol,
        "defringe": args.defringe,
        "trim_border": args.trim_border,
        "edge_clean_depth": args.edge_clean_depth,
        "component_mode": args.component_mode,
        "component_padding": args.component_padding,
        "min_component_area": args.min_component_area,
        "edge_touch_margin": args.edge_touch_margin,
    }


def process_single(args: argparse.Namespace) -> Path:
    out_dir = args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    prompt_text = write_prompt(out_dir, args.prompt, args.prompt_file)
    asset_id = sanitize_slug(args.name)

    raw = Image.open(args.input).convert("RGBA")
    raw.save(out_dir / "raw.png")
    bg_info: dict[str, Any] = {"mode": args.background_mode}
    if args.background_mode == "sampled":
        tolerance = args.background_tolerance if args.background_tolerance is not None else args.flood_bg_tol
        cleaned, bg_info = remove_bg_sampled(raw, tolerance=tolerance)
    else:
        keyable = raw
        if getattr(args, "flood_bg", False):
            keyable = flood_corners_to_magenta(raw, args.flood_bg_tol)
            keyable.save(out_dir / "flooded.png")
        cleaned = remove_bg_magenta(keyable, args.threshold, args.edge_threshold)
        bg_info = {
            "ok": True,
            "mode": "chroma",
            "flood_bg": bool(getattr(args, "flood_bg", False)),
            "flood_bg_tol": args.flood_bg_tol,
        }
    cleaned.save(out_dir / "clean.png")
    foreground, extract_info = extract_foreground(
        cleaned,
        component_mode=args.component_mode,
        component_padding=args.component_padding,
        min_component_area=args.min_component_area,
        edge_touch_margin=args.edge_touch_margin,
        trim_border_px=args.trim_border,
        edge_clean_depth=args.edge_clean_depth,
    )

    metadata = _common_meta(args, "single", prompt_text)
    metadata["asset_id"] = asset_id
    metadata["background"] = bg_info
    metadata["foreground"] = extract_info
    metadata["outputs"] = {
        "raw": str(out_dir / "raw.png"),
        "clean": str(out_dir / "clean.png"),
        "asset": str(out_dir / f"{asset_id}.png"),
    }

    if foreground is None:
        metadata["ok"] = False
        write_manifest(out_dir, metadata)
        raise AssetProcessingError("No foreground component found.")
    if args.reject_edge_touch and extract_info["edge_touch"]:
        metadata["ok"] = False
        write_manifest(out_dir, metadata)
        raise AssetProcessingError("Foreground touches image edge.")

    centered, center_info = center_on_canvas(
        foreground,
        size=args.size,
        fit_scale=args.fit_scale,
        align=args.align,
    )
    centered = defringe_alpha(centered, getattr(args, "defringe", 0))
    centered.save(out_dir / f"{asset_id}.png")
    metadata["center"] = center_info
    write_manifest(out_dir, metadata)
    LOGGER.info("processed single asset %s", out_dir / f"{asset_id}.png")
    return out_dir


def compose_sheet(frames: list[Image.Image], rows: int, cols: int, size: int) -> Image.Image:
    canvas = Image.new("RGBA", (cols * size, rows * size), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, col = divmod(index, cols)
        canvas.alpha_composite(frame, (col * size, row * size))
    return canvas


def process_sheet(args: argparse.Namespace) -> Path:
    if args.rows <= 0 or args.cols <= 0:
        raise AssetProcessingError("--rows and --cols must be positive.")

    out_dir = args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    prompt_text = write_prompt(out_dir, args.prompt, args.prompt_file)
    prefix = sanitize_slug(args.prefix)
    expected_count = args.rows * args.cols
    labels = parse_labels(args.labels, args.labels_file, expected_count, prefix)

    raw = Image.open(args.input).convert("RGBA")
    raw.save(out_dir / "raw-sheet.png")
    bg_info: dict[str, Any] = {"mode": args.background_mode}
    if args.background_mode == "sampled":
        tolerance = args.background_tolerance if args.background_tolerance is not None else args.flood_bg_tol
        cleaned, bg_info = remove_bg_sampled(raw, tolerance=tolerance)
    else:
        cleaned = remove_bg_magenta(raw, args.threshold, args.edge_threshold)
        bg_info = {"ok": True, "mode": "chroma"}
    cleaned.save(out_dir / "raw-sheet-clean.png")

    frames: list[Image.Image] = []
    frame_meta: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []

    for index, (row, col, source_box, cell) in enumerate(iter_cells(cleaned, args.rows, args.cols)):
        label = labels[index]
        info: dict[str, Any] = {
            "index": index,
            "label": label,
            "grid": [row, col],
            "source_box": list(source_box),
        }
        if not label:
            info["status"] = "skipped-label"
            skipped.append(info)
            frames.append(Image.new("RGBA", (args.size, args.size), (0, 0, 0, 0)))
            frame_meta.append(info)
            continue

        foreground, extract_info = extract_foreground(
            cell,
            component_mode=args.component_mode,
            component_padding=args.component_padding,
            min_component_area=args.min_component_area,
            edge_touch_margin=args.edge_touch_margin,
            trim_border_px=args.trim_border,
            edge_clean_depth=args.edge_clean_depth,
        )
        info.update(extract_info)
        if foreground is None:
            info["status"] = "empty"
            skipped.append(info)
            frames.append(Image.new("RGBA", (args.size, args.size), (0, 0, 0, 0)))
            frame_meta.append(info)
            continue

        centered, center_info = center_on_canvas(
            foreground,
            size=args.size,
            fit_scale=args.fit_scale,
            align=args.align,
        )
        image_path = out_dir / f"{label}.png"
        centered.save(image_path)
        info["status"] = "accepted"
        info["image"] = str(image_path)
        info["center"] = center_info
        frames.append(centered)
        frame_meta.append(info)

    sheet_path = out_dir / "sheet-transparent.png"
    compose_sheet(frames, args.rows, args.cols, args.size).save(sheet_path)
    edge_touch_frames = [item["grid"] for item in frame_meta if bool(item.get("edge_touch"))]

    metadata = _common_meta(args, "sheet", prompt_text)
    metadata.update(
        {
            "rows": args.rows,
            "cols": args.cols,
            "labels": labels,
            "frames": frame_meta,
            "skipped": skipped,
            "edge_touch_frames": edge_touch_frames,
            "background": bg_info,
            "outputs": {
                "raw": str(out_dir / "raw-sheet.png"),
                "clean": str(out_dir / "raw-sheet-clean.png"),
                "sheet": str(sheet_path),
            },
        }
    )

    if args.reject_edge_touch and edge_touch_frames:
        metadata["ok"] = False
        write_manifest(out_dir, metadata)
        raise AssetProcessingError(f"Frames touch cell edge: {edge_touch_frames}")

    write_manifest(out_dir, metadata)
    LOGGER.info("processed sheet asset %s", sheet_path)
    return out_dir


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--size", type=int, default=128)
    parser.add_argument("--fit-scale", type=float, default=0.85)
    parser.add_argument("--align", choices=["center", "bottom", "feet"], default="center")
    parser.add_argument("--threshold", type=int, default=100)
    parser.add_argument("--edge-threshold", type=int, default=120)
    parser.add_argument("--background-mode", choices=["chroma", "sampled"], default="chroma",
                        help="chroma=旧洋红抠色; sampled=边缘采样连通去背, 更适合非纯色棚拍底")
    parser.add_argument("--background-tolerance", type=int, default=None,
                        help="sampled 模式颜色距离阈值; 省略时复用 --flood-bg-tol")
    parser.add_argument("--flood-bg", action="store_true",
                        help="先从四角连通域漫水把非洋红底 (灰/浅色棚拍底) 重染成洋红再去背")
    parser.add_argument("--flood-bg-tol", type=int, default=70,
                        help="漫水时与角色参考色的颜色距离阈值")
    parser.add_argument("--defringe", type=int, default=0,
                        help="成品 alpha 向内腐蚀 N px, 削掉去背残留的白边/混色边")
    parser.add_argument("--trim-border", type=int, default=4)
    parser.add_argument("--edge-clean-depth", type=int, default=2)
    parser.add_argument("--component-mode", choices=["all", "largest"], default="all")
    parser.add_argument("--component-padding", type=int, default=0)
    parser.add_argument("--min-component-area", type=int, default=1)
    parser.add_argument("--edge-touch-margin", type=int, default=0)
    parser.add_argument("--reject-edge-touch", action="store_true")
    parser.add_argument("--prompt")
    parser.add_argument("--prompt-file", type=Path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true")
    subparsers = parser.add_subparsers(dest="command", required=True)

    single = subparsers.add_parser("single", help="Process one transparent asset.")
    add_common_args(single)
    single.add_argument("--name", required=True)

    sheet = subparsers.add_parser("sheet", help="Process a fixed-grid asset sheet.")
    add_common_args(sheet)
    sheet.add_argument("--rows", required=True, type=int)
    sheet.add_argument("--cols", required=True, type=int)
    sheet.add_argument("--labels")
    sheet.add_argument("--labels-file", type=Path)
    sheet.add_argument("--prefix", default="asset")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="[%(levelname)s] [art] %(message)s",
    )
    try:
        if args.command == "single":
            out_dir = process_single(args)
        else:
            out_dir = process_sheet(args)
    except AssetProcessingError as exc:
        LOGGER.error("%s", exc)
        return 1
    except Exception as exc:  # pragma: no cover - defensive CLI boundary.
        LOGGER.exception("unexpected failure: %s", exc)
        return 1

    print(str(out_dir.resolve()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
