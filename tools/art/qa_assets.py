#!/usr/bin/env python3
"""QA and repair accepted UI PNG assets.

The repair path is deterministic: it reuses existing tools/art/runs/<label>/raw.png
files, runs process_asset.py with sampled background removal, then copies the
result back to assets/sprites/ui.
"""

from __future__ import annotations

import argparse
import json
import logging
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
ASSETS = REPO / "assets" / "sprites" / "ui"
RUNS = HERE / "runs"
LOGGER = logging.getLogger("art_qa")
MAX_SAFE_SAMPLED_TOLERANCE = 45


def sanitize_slug(value: str) -> str:
    import re

    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip().lower()).strip("-")
    return slug or "asset"


def iter_assets(category: str | None = None) -> list[Path]:
    root = ASSETS / category if category else ASSETS
    return sorted(path for path in root.rglob("*.png") if path.is_file())


def asset_label(path: Path) -> str:
    rel = path.relative_to(ASSETS)
    category = rel.parts[0]
    stem = path.stem
    if category == "brand":
        return stem
    if category == "founder":
        return f"founder-{stem}"
    if category == "lead":
        return f"lead-{stem}"
    if category == "office":
        return f"office-{stem}"
    if category == "infra":
        return stem
    return f"{category}-{stem}"


def repair_tolerance(path: Path) -> int:
    # Keep sampled flood-fill conservative. Higher values have eaten pale
    # foreground regions such as chat bubbles, paper, ribbons, and highlights.
    # The relative_to call keeps accidental non-asset paths noisy.
    path.relative_to(ASSETS)
    return MAX_SAFE_SAMPLED_TOLERANCE


def repair_defringe(path: Path) -> int:
    category = path.relative_to(ASSETS).parts[0]
    if category in {"brand", "charity", "simulation"}:
        return 1
    return 0


def load_meta(label: str) -> dict[str, Any]:
    meta_path = RUNS / label / "pipeline-meta.json"
    if not meta_path.exists():
        return {}
    try:
        return json.loads(meta_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def repair_one(path: Path, *, dry_run: bool = False) -> dict[str, Any]:
    label = asset_label(path)
    raw = RUNS / label / "raw.png"
    result: dict[str, Any] = {
        "asset": str(path),
        "label": label,
        "raw": str(raw),
        "status": "pending",
    }
    if path.name == "room-bg.png":
        result["status"] = "skipped-scene"
        return result
    if not raw.exists():
        result["status"] = "missing-raw"
        return result

    with Image.open(path) as current:
        width, height = current.size
    if width != height:
        result["status"] = "skipped-nonsquare"
        return result

    meta = load_meta(label)
    fit_scale = float(meta.get("fit_scale", 0.82))
    align = str(meta.get("align", "center"))
    trim_border = int(meta.get("trim_border", 6))
    edge_clean_depth = int(meta.get("edge_clean_depth", 2))
    tolerance = repair_tolerance(path)
    defringe = repair_defringe(path)

    cmd = [
        sys.executable,
        str(HERE / "process_asset.py"),
        "single",
        "--input",
        str(raw),
        "--output-dir",
        str(raw.parent),
        "--name",
        label,
        "--size",
        str(width),
        "--fit-scale",
        str(fit_scale),
        "--align",
        align,
        "--component-mode",
        "all",
        "--background-mode",
        "sampled",
        "--background-tolerance",
        str(tolerance),
        "--trim-border",
        str(trim_border),
        "--edge-clean-depth",
        str(edge_clean_depth),
    ]
    prompt = raw.parent / "prompt-used.txt"
    if prompt.exists():
        cmd += ["--prompt-file", str(prompt)]
    if defringe > 0:
        cmd += ["--defringe", str(defringe)]

    result.update(
        {
            "size": width,
            "background_tolerance": tolerance,
            "defringe": defringe,
            "command": cmd,
        }
    )
    if dry_run:
        result["status"] = "dry-run"
        return result

    LOGGER.info("repair %s", path.relative_to(REPO))
    proc = subprocess.run(cmd, text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        result["status"] = "process-failed"
        result["stderr"] = proc.stderr
        return result

    processed = raw.parent / f"{sanitize_slug(label)}.png"
    if not processed.exists():
        result["status"] = "missing-output"
        return result
    shutil.copyfile(processed, path)
    result["status"] = "repaired"
    return result


def make_contact_sheet(paths: list[Path], out_path: Path) -> None:
    if not paths:
        return
    cell = 150
    cols = 6
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (255, 255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(paths):
        x = (index % cols) * cell
        y = (index // cols) * cell
        for yy in range(y, y + cell, 8):
            for xx in range(x, x + cell, 8):
                color = (238, 238, 238, 255) if ((xx // 8 + yy // 8) % 2 == 0) else (210, 210, 210, 255)
                draw.rectangle([xx, yy, xx + 7, yy + 7], fill=color)
        with Image.open(path) as opened:
            img = opened.convert("RGBA")
        img.thumbnail((112, 112), Image.Resampling.LANCZOS)
        sheet.alpha_composite(img, (x + (cell - img.width) // 2, y + 24 + (112 - img.height) // 2))
        draw.text((x + 4, y + 4), path.name[:24], fill=(0, 0, 0, 255))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)


def cmd_contact(args: argparse.Namespace) -> int:
    out_dir = args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    categories = [args.category] if args.category else sorted(path.name for path in ASSETS.iterdir() if path.is_dir())
    for category in categories:
        paths = iter_assets(category)
        make_contact_sheet(paths, out_dir / f"{category}.png")
    return 0


def cmd_repair(args: argparse.Namespace) -> int:
    reports = [repair_one(path, dry_run=args.dry_run) for path in iter_assets(args.category)]
    repaired = sum(1 for item in reports if item["status"] == "repaired")
    skipped = sum(1 for item in reports if item["status"].startswith("skipped") or item["status"] == "missing-raw")
    failed = [item for item in reports if item["status"].endswith("failed") or item["status"] == "missing-output"]
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(reports, indent=2, ensure_ascii=False), encoding="utf-8")
    LOGGER.info("repair summary: %s repaired, %s skipped, %s failed", repaired, skipped, len(failed))
    if failed:
        for item in failed:
            LOGGER.error("%s: %s", item["label"], item["status"])
    return 1 if failed else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    contact = sub.add_parser("contact", help="Build checkerboard contact sheets.")
    contact.add_argument("--category")
    contact.add_argument("--output-dir", type=Path, default=Path("/tmp/agi-assets-contact"))
    contact.set_defaults(func=cmd_contact)

    repair = sub.add_parser("repair", help="Reprocess accepted PNGs from existing raw runs.")
    repair.add_argument("--category")
    repair.add_argument("--dry-run", action="store_true")
    repair.add_argument("--report", type=Path, default=Path("/tmp/agi-assets-repair-report.json"))
    repair.set_defaults(func=cmd_repair)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="[%(levelname)s] [art-qa] %(message)s",
    )
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
