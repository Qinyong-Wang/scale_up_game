import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TOOL_PATH = ROOT / "tools" / "web_release.py"


def write_project(root: Path) -> None:
    (root / "project.godot").write_text(
        '[application]\n\nconfig/name="Scaling Up"\nconfig/version="0.1.1-alpha"\n',
        encoding="utf-8",
    )


def write_web_export(root: Path) -> Path:
    export_dir = root / "build" / "web"
    export_dir.mkdir(parents=True)
    for name, data in {
        "index.html": "<!doctype html><title>Scaling Up</title>",
        "index.js": "console.log('boot');",
        "index.wasm": b"\0asm",
        "index.pck": b"pck",
        "icon.png": b"png",
        "old-release.zip": b"stale",
    }.items():
        path = export_dir / name
        if isinstance(data, bytes):
            path.write_bytes(data)
        else:
            path.write_text(data, encoding="utf-8")
    return export_dir


class WebReleaseCliTest(unittest.TestCase):
    def run_cli(self, *args: str, cwd: Path):
        return subprocess.run(
            [sys.executable, str(TOOL_PATH), *args],
            cwd=cwd,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_check_and_package_web_export(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            write_project(root)
            export_dir = write_web_export(root)
            output = export_dir / "Scaling-Up-0.1.1-alpha-web.zip"

            check = self.run_cli("check", "--project-root", str(root), "--export-dir", str(export_dir), cwd=root)
            self.assertEqual(check.returncode, 0, check.stderr)
            self.assertIn("index.html", check.stdout)

            package = self.run_cli(
                "package",
                "--project-root", str(root),
                "--export-dir", str(export_dir),
                "--output", str(output),
                cwd=root,
            )
            self.assertEqual(package.returncode, 0, package.stderr)
            self.assertTrue(output.exists())

            with zipfile.ZipFile(output) as zf:
                names = set(zf.namelist())
            self.assertIn("index.html", names)
            self.assertIn("index.wasm", names)
            self.assertIn("index.pck", names)
            self.assertNotIn("old-release.zip", names)
            self.assertNotIn(output.name, names)

    def test_check_preset_requires_web_export_path(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            presets = root / "export_presets.cfg"
            presets.write_text(
                '[preset.0]\n\nname="macOS"\nplatform="macOS"\nexport_path="build/macos/Scaling-Up.app"\n',
                encoding="utf-8",
            )

            result = self.run_cli("check-preset", "--presets", str(presets), cwd=root)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Web", result.stderr)

            presets.write_text(
                '[preset.0]\n\nname="Web"\nplatform="Web"\nexport_path="build/web/index.html"\n',
                encoding="utf-8",
            )
            ok = self.run_cli("check-preset", "--presets", str(presets), cwd=root)
            self.assertEqual(ok.returncode, 0, ok.stderr)

    def test_write_preset_creates_ci_web_export_preset(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            presets = root / "export_presets.cfg"

            write = self.run_cli("write-preset", "--presets", str(presets), cwd=root)
            self.assertEqual(write.returncode, 0, write.stderr)
            contents = presets.read_text(encoding="utf-8")
            self.assertIn('name="Web"', contents)
            self.assertIn('platform="Web"', contents)
            self.assertIn('export_path="build/web/index.html"', contents)
            self.assertIn("variant/thread_support=false", contents)
            self.assertIn("variant/extensions_support=false", contents)
            self.assertIn("progressive_web_app/enabled=false", contents)

            ok = self.run_cli("check-preset", "--presets", str(presets), cwd=root)
            self.assertEqual(ok.returncode, 0, ok.stderr)

            refused = self.run_cli("write-preset", "--presets", str(presets), cwd=root)
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("--force", refused.stderr)

            forced = self.run_cli("write-preset", "--presets", str(presets), "--force", cwd=root)
            self.assertEqual(forced.returncode, 0, forced.stderr)

    def test_github_pages_workflow_builds_and_deploys_web_export(self):
        workflow = ROOT / ".github" / "workflows" / "deploy-web.yml"
        self.assertTrue(workflow.exists(), "missing GitHub Pages deployment workflow")
        text = workflow.read_text(encoding="utf-8")

        self.assertIn("chickensoft-games/setup-godot@v2", text)
        self.assertIn("include-templates: true", text)
        self.assertIn("python3 tools/web_release.py write-preset --force", text)
        self.assertIn('godot --headless --path . --export-release "Web" build/web/index.html', text)
        self.assertIn("python3 tools/web_release.py check --export-dir build/web", text)
        self.assertIn("actions/configure-pages@v5", text)
        self.assertIn("actions/upload-pages-artifact@v4", text)
        self.assertIn("actions/deploy-pages@v4", text)
        self.assertIn("path: build/web", text)


if __name__ == "__main__":
    unittest.main()
