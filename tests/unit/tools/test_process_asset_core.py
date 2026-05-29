import importlib.util
import sys
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
TOOL_PATH = ROOT / "tools" / "art" / "process_asset.py"


def load_tool():
    spec = importlib.util.spec_from_file_location("process_asset", TOOL_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules["process_asset"] = module
    spec.loader.exec_module(module)
    return module


class ProcessAssetCoreTest(unittest.TestCase):
    def setUp(self):
        self.tool = load_tool()

    def test_remove_bg_magenta_turns_background_transparent(self):
        img = Image.new("RGBA", (8, 8), (255, 0, 255, 255))
        img.putpixel((3, 3), (20, 80, 210, 255))

        cleaned = self.tool.remove_bg_magenta(img, threshold=8, edge_threshold=8)

        self.assertEqual(cleaned.getpixel((0, 0))[3], 0)
        self.assertEqual(cleaned.getpixel((7, 7))[3], 0)
        self.assertEqual(cleaned.getpixel((3, 3)), (20, 80, 210, 255))

    def test_sampled_background_removal_preserves_subject_highlight(self):
        img = Image.new("RGBA", (20, 20), (225, 115, 145, 255))
        for x in range(5, 15):
            for y in range(4, 17):
                img.putpixel((x, y), (30, 90, 190, 255))
        for y in range(6, 15):
            img.putpixel((10, y), (235, 125, 155, 255))

        cleaned, info = self.tool.remove_bg_sampled(img, tolerance=35)

        self.assertGreater(info["removed_pixels"], 0)
        self.assertEqual(cleaned.getpixel((0, 0))[3], 0)
        self.assertEqual(cleaned.getpixel((19, 19))[3], 0)
        self.assertEqual(cleaned.getpixel((10, 10)), (235, 125, 155, 255))
        self.assertEqual(cleaned.getpixel((6, 10)), (30, 90, 190, 255))

    def test_sampled_background_removal_handles_non_magenta_backdrop(self):
        img = Image.new("RGBA", (18, 18), (236, 234, 235, 255))
        for x in range(6, 12):
            for y in range(5, 14):
                img.putpixel((x, y), (35, 85, 170, 255))

        cleaned, info = self.tool.remove_bg_sampled(img, tolerance=20)

        self.assertTrue(info["ok"])
        self.assertEqual(cleaned.getpixel((0, 0))[3], 0)
        self.assertEqual(cleaned.getpixel((17, 17))[3], 0)
        self.assertEqual(cleaned.getpixel((8, 8)), (35, 85, 170, 255))

    def test_extract_foreground_largest_component_ignores_small_noise(self):
        img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        for x in range(10, 22):
            for y in range(8, 24):
                img.putpixel((x, y), (10, 90, 180, 255))
        img.putpixel((1, 1), (0, 255, 0, 255))

        foreground, info = self.tool.extract_foreground(
            img,
            component_mode="largest",
            component_padding=0,
            min_component_area=1,
            edge_touch_margin=0,
        )

        self.assertIsNotNone(foreground)
        self.assertEqual(foreground.size, (12, 16))
        self.assertEqual(info["component_count"], 2)
        self.assertEqual(info["selected_component_area"], 192)
        self.assertFalse(info["edge_touch"])

    def test_center_on_canvas_preserves_transparency_and_centers_subject(self):
        img = Image.new("RGBA", (10, 20), (40, 90, 180, 255))

        centered, info = self.tool.center_on_canvas(img, size=40, fit_scale=0.5, align="center")

        self.assertEqual(centered.size, (40, 40))
        self.assertEqual(centered.getpixel((0, 0))[3], 0)
        self.assertEqual(info["output_size"], [10, 20])
        self.assertEqual(info["paste_position"], [15, 10])


if __name__ == "__main__":
    unittest.main()
