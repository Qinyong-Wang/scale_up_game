import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
TOOL_PATH = ROOT / "tools" / "art" / "process_asset.py"


def make_sheet(path: Path, *, edge_touch: bool = False) -> None:
    img = Image.new("RGBA", (80, 80), (255, 0, 255, 255))
    colors = [
        (35, 90, 190, 255),
        (40, 150, 110, 255),
        (190, 110, 35, 255),
        (140, 70, 190, 255),
    ]
    for index, color in enumerate(colors):
        row, col = divmod(index, 2)
        left = col * 40 + 10
        top = row * 40 + 10
        right = left + 18
        bottom = top + 18
        if edge_touch and index == 0:
            left = col * 40
        for x in range(left, right):
            for y in range(top, bottom):
                img.putpixel((x, y), color)
    img.save(path)


class ProcessAssetCliTest(unittest.TestCase):
    def run_cli(self, *args: str, cwd: Path):
        return subprocess.run(
            [sys.executable, str(TOOL_PATH), *args],
            cwd=cwd,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_sheet_cli_exports_labels_sheet_and_manifest(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            raw = root / "raw.png"
            out = root / "out"
            make_sheet(raw)

            result = self.run_cli(
                "sheet",
                "--input", str(raw),
                "--output-dir", str(out),
                "--rows", "2",
                "--cols", "2",
                "--labels", "model,lead,infra,event",
                "--size", "32",
                "--fit-scale", "0.75",
                "--component-mode", "largest",
                "--reject-edge-touch",
                "--prompt", "clean hd ui icon pack, no real brands",
                cwd=root,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            for label in ("model", "lead", "infra", "event"):
                self.assertTrue((out / f"{label}.png").exists())
            self.assertTrue((out / "sheet-transparent.png").exists())
            self.assertTrue((out / "prompt-used.txt").exists())

            meta = json.loads((out / "pipeline-meta.json").read_text(encoding="utf-8"))
            self.assertTrue(meta["ok"])
            self.assertEqual(meta["mode"], "sheet")
            self.assertEqual(meta["rows"], 2)
            self.assertEqual(meta["cols"], 2)
            self.assertEqual(len(meta["frames"]), 4)
            self.assertEqual(meta["edge_touch_frames"], [])

            exported = Image.open(out / "model.png").convert("RGBA")
            self.assertEqual(exported.size, (32, 32))
            self.assertEqual(exported.getpixel((0, 0))[3], 0)

    def test_reject_edge_touch_returns_nonzero_and_writes_manifest(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            raw = root / "raw.png"
            out = root / "out"
            make_sheet(raw, edge_touch=True)

            result = self.run_cli(
                "sheet",
                "--input", str(raw),
                "--output-dir", str(out),
                "--rows", "2",
                "--cols", "2",
                "--labels", "bad,ok1,ok2,ok3",
                "--size", "32",
                "--component-mode", "largest",
                "--reject-edge-touch",
                cwd=root,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("touch", result.stderr.lower())
            meta = json.loads((out / "pipeline-meta.json").read_text(encoding="utf-8"))
            self.assertFalse(meta["ok"])
            self.assertEqual(meta["edge_touch_frames"], [[0, 0]])


if __name__ == "__main__":
    unittest.main()
