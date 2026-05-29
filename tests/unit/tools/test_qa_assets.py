import importlib.util
import sys
import types
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
QA_PATH = ROOT / "tools" / "art" / "qa_assets.py"
GENERATE_PATH = ROOT / "tools" / "art" / "generate.py"
ALPHA_MIN_PIXELS = 3600
ALPHA_MIN_BBOX_FILL = 0.45


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class QaAssetsTest(unittest.TestCase):
    def setUp(self):
        self.qa = load_module("qa_assets", QA_PATH)

    def test_repair_uses_low_sampled_tolerance_for_product_assets(self):
        path = ROOT / "assets" / "sprites" / "ui" / "product" / "chatbot.png"

        report = self.qa.repair_one(path, dry_run=True)

        self.assertEqual(report["status"], "dry-run")
        self.assertLessEqual(report["background_tolerance"], self.qa.MAX_SAFE_SAMPLED_TOLERANCE)
        joined = " ".join(str(part) for part in report["command"])
        self.assertIn("--background-mode sampled", joined)
        self.assertIn(f"--background-tolerance {self.qa.MAX_SAFE_SAMPLED_TOLERANCE}", joined)

    def test_generate_sampled_batches_do_not_default_to_destructive_tolerance(self):
        sys.modules.setdefault("requests", types.SimpleNamespace())
        generate = load_module("generate", GENERATE_PATH)
        too_high = []
        for name, spec in generate.BATCHES.items():
            if spec.get("background_mode") != "sampled":
                continue
            tolerance = int(spec.get("background_tolerance", self.qa.MAX_SAFE_SAMPLED_TOLERANCE))
            if tolerance > self.qa.MAX_SAFE_SAMPLED_TOLERANCE:
                too_high.append((name, tolerance))

        self.assertEqual(too_high, [])

    def test_brand_and_task_icons_are_dense_enough_for_small_ui(self):
        offenders = []
        for directory in [
            ROOT / "assets" / "sprites" / "ui" / "brand",
            ROOT / "assets" / "sprites" / "ui" / "task",
        ]:
            for path in sorted(directory.glob("*.png")):
                metrics = _alpha_metrics(path)
                if (
                    metrics["alpha_pixels"] < ALPHA_MIN_PIXELS
                    or metrics["bbox_fill"] < ALPHA_MIN_BBOX_FILL
                ):
                    offenders.append(
                        "%s alpha=%d fill=%.3f"
                        % (
                            path.relative_to(ROOT),
                            metrics["alpha_pixels"],
                            metrics["bbox_fill"],
                        )
                    )
        self.assertEqual(
            offenders,
            [],
            "brand/task icons must be solid enough at 28-48px; failing assets: %s"
            % ", ".join(offenders),
        )


def _alpha_metrics(path: Path) -> dict:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    xs = []
    ys = []
    alpha_pixels = 0
    for y in range(image.height):
        for x in range(image.width):
            if alpha.getpixel((x, y)) > 12:
                alpha_pixels += 1
                xs.append(x)
                ys.append(y)
    if not xs:
        return {"alpha_pixels": 0, "bbox_fill": 0.0}
    bbox_area = (max(xs) - min(xs) + 1) * (max(ys) - min(ys) + 1)
    return {
        "alpha_pixels": alpha_pixels,
        "bbox_fill": alpha_pixels / float(bbox_area),
    }


if __name__ == "__main__":
    unittest.main()
