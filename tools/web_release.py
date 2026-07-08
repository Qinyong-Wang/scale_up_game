#!/usr/bin/env python3
"""Web release checks, CI preset generation, and packaging for Scaling Up."""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path
from typing import Dict, Iterable, List


REQUIRED_WEB_FILES = ("index.html",)
REQUIRED_WEB_PATTERNS = ("*.js", "*.wasm", "*.pck")
EXCLUDED_DIRS = {".godot", "addons", "assets", "design", "docs", "resources", "scenes", "scripts", "tests", "tools"}
EXCLUDED_SUFFIXES = {".zip", ".DS_Store"}
CI_WEB_PRESET = """[preset.0]
name="Web"
platform="Web"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="tests/*, addons/gut/*, tools/*, design/*, docs/*, build/*, exports/*"
export_path="build/web/index.html"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/export_icon=true
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false
"""


def _read_version(project_root: Path) -> str:
    project_file = project_root / "project.godot"
    if not project_file.exists():
        return "0.0.0-dev"
    for line in project_file.read_text(encoding="utf-8").splitlines():
        if line.startswith("config/version="):
            return line.split("=", 1)[1].strip().strip('"') or "0.0.0-dev"
    return "0.0.0-dev"


def _file_size_label(size: int) -> str:
    units = ["B", "KiB", "MiB", "GiB"]
    value = float(size)
    unit = units[0]
    for unit in units:
        if value < 1024 or unit == units[-1]:
            break
        value /= 1024
    if unit == "B":
        return f"{int(value)} {unit}"
    return f"{value:.1f} {unit}"


def _die(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


def _parse_presets(path: Path) -> List[Dict[str, str]]:
    presets: List[Dict[str, str]] = []
    current: Dict[str, str] | None = None
    in_preset = False
    section_re = re.compile(r"^\[(preset\.\d+)(?:\.options)?\]\s*$")
    key_re = re.compile(r'^([A-Za-z0-9_/\-]+)="?(.*?)"?\s*$')

    for raw in path.read_text(encoding="utf-8").splitlines():
        section = section_re.match(raw.strip())
        if section:
            section_name = raw.strip().strip("[]")
            in_preset = ".options" not in section_name
            if in_preset:
                current = {}
                presets.append(current)
            else:
                current = None
            continue
        if not in_preset or current is None:
            continue
        match = key_re.match(raw.strip())
        if match:
            current[match.group(1)] = match.group(2)
    return presets


def _find_web_preset(presets: Iterable[Dict[str, str]]) -> Dict[str, str] | None:
    for preset in presets:
        if preset.get("platform") == "Web" or preset.get("name") == "Web":
            return preset
    return None


def check_preset(args: argparse.Namespace) -> int:
    presets_path = Path(args.presets).expanduser()
    if not presets_path.exists():
        return _die(f"export preset file not found: {presets_path}")
    web = _find_web_preset(_parse_presets(presets_path))
    if web is None:
        return _die("Web export preset is missing; add a Godot Web preset named \"Web\"")
    export_path = web.get("export_path", "").replace("\\", "/")
    if export_path != "build/web/index.html":
        return _die(f"Web export_path must be build/web/index.html, got {export_path or '<empty>'}")
    print(f"ok: Web preset exports to {export_path}")
    return 0


def write_preset(args: argparse.Namespace) -> int:
    presets_path = Path(args.presets).expanduser()
    if presets_path.exists() and not args.force:
        return _die(f"{presets_path} already exists; pass --force to overwrite it")
    presets_path.parent.mkdir(parents=True, exist_ok=True)
    presets_path.write_text(CI_WEB_PRESET, encoding="utf-8")
    print(f"ok: wrote CI Web export preset to {presets_path}")
    return 0


def _export_files(export_dir: Path) -> List[Path]:
    return [p for p in sorted(export_dir.rglob("*")) if p.is_file()]


def check_export_dir(export_dir: Path) -> tuple[bool, List[str]]:
    errors: List[str] = []
    if not export_dir.exists():
        return False, [f"export directory not found: {export_dir}"]
    for name in REQUIRED_WEB_FILES:
        if not (export_dir / name).is_file():
            errors.append(f"missing required Web export file: {name}")
    for pattern in REQUIRED_WEB_PATTERNS:
        if not any(export_dir.glob(pattern)):
            errors.append(f"missing required Web export file matching {pattern}")
    for bad_dir in EXCLUDED_DIRS:
        if (export_dir / bad_dir).exists():
            errors.append(f"unexpected source directory inside Web export: {bad_dir}")
    return not errors, errors


def check(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).expanduser().resolve()
    export_dir = Path(args.export_dir).expanduser().resolve()
    ok, errors = check_export_dir(export_dir)
    if not ok:
        return _die("; ".join(errors))
    files = [p for p in _export_files(export_dir) if p.suffix not in EXCLUDED_SUFFIXES and p.name not in EXCLUDED_SUFFIXES]
    total_size = sum(p.stat().st_size for p in files)
    print(f"ok: {export_dir}")
    print(f"files: {len(files)}")
    print(f"size: {_file_size_label(total_size)}")
    print(f"entry: {(export_dir / 'index.html').name}")
    print(f"version: {_read_version(project_root)}")
    return 0


def _iter_package_files(export_dir: Path, output: Path) -> Iterable[Path]:
    output_resolved = output.resolve()
    for path in _export_files(export_dir):
        if path.resolve() == output_resolved:
            continue
        if path.suffix in EXCLUDED_SUFFIXES or path.name in EXCLUDED_SUFFIXES:
            continue
        if any(part in EXCLUDED_DIRS for part in path.relative_to(export_dir).parts):
            continue
        yield path


def package(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).expanduser().resolve()
    export_dir = Path(args.export_dir).expanduser().resolve()
    ok, errors = check_export_dir(export_dir)
    if not ok:
        return _die("; ".join(errors))
    version = _read_version(project_root)
    output = Path(args.output).expanduser().resolve() if args.output else export_dir / f"Scaling-Up-{version}-web.zip"
    output.parent.mkdir(parents=True, exist_ok=True)
    files = list(_iter_package_files(export_dir, output))
    if not files:
        return _die(f"no packageable files found in {export_dir}")

    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in files:
            zf.write(path, path.relative_to(export_dir).as_posix())

    print(f"ok: wrote {output}")
    print(f"files: {len(files)}")
    print(f"size: {_file_size_label(output.stat().st_size)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Check and package the Scaling Up Web export.")
    sub = parser.add_subparsers(dest="command", required=True)

    preset = sub.add_parser("check-preset", help="Validate the local Godot Web export preset.")
    preset.add_argument("--presets", default="export_presets.cfg", help="Path to local export_presets.cfg.")
    preset.set_defaults(func=check_preset)

    write = sub.add_parser("write-preset", help="Write a CI-only Godot Web export preset.")
    write.add_argument("--presets", default="export_presets.cfg", help="Path to write export_presets.cfg.")
    write.add_argument("--force", action="store_true", help="Overwrite an existing preset file.")
    write.set_defaults(func=write_preset)

    check_cmd = sub.add_parser("check", help="Validate an already-exported Web directory.")
    check_cmd.add_argument("--project-root", default=".", help="Project root containing project.godot.")
    check_cmd.add_argument("--export-dir", default="build/web", help="Directory containing index.html.")
    check_cmd.set_defaults(func=check)

    package_cmd = sub.add_parser("package", help="Zip an already-exported Web directory.")
    package_cmd.add_argument("--project-root", default=".", help="Project root containing project.godot.")
    package_cmd.add_argument("--export-dir", default="build/web", help="Directory containing index.html.")
    package_cmd.add_argument("--output", default="", help="Output zip path. Defaults to build/web/Scaling-Up-<version>-web.zip.")
    package_cmd.set_defaults(func=package)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
