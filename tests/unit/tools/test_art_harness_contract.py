import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class ArtHarnessContractTest(unittest.TestCase):
    def test_art_design_is_flat_ui_only(self):
        text = (ROOT / "design" / "图片素材管线设计.md").read_text(encoding="utf-8")
        forbidden = ["office", "办公室", "分层场景", "TileMap"]
        for word in forbidden:
            self.assertNotIn(word, text)

    def test_claude_asset_tree_does_not_define_office_sprite_bucket(self):
        text = (ROOT / "CLAUDE.md").read_text(encoding="utf-8")
        self.assertIn("assets/\n  sprites/              运行时图片素材\n    ui/", text)
        self.assertNotIn("sprites/office", text)
        self.assertNotIn("office/             后续办公室场景素材", text)


if __name__ == "__main__":
    unittest.main()
