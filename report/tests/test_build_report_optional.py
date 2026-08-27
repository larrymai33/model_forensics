import importlib.util
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPORT_DIR = Path(__file__).resolve().parents[1]
HAS_BUILD_DEPENDENCIES = bool(
    importlib.util.find_spec("PIL") and importlib.util.find_spec("docx")
)


@unittest.skipUnless(
    HAS_BUILD_DEPENDENCIES,
    "optional report-build smoke test requires Pillow and python-docx",
)
class OptionalReportBuildSmokeTests(unittest.TestCase):
    def test_default_build_writes_generated_docx_and_preserves_checked_in_artifacts(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            shutil.copy2(REPORT_DIR / "build_report.py", root / "build_report.py")
            shutil.copy2(REPORT_DIR / "takehome.md", root / "takehome.md")
            shutil.copytree(REPORT_DIR / "figures", root / "figures")
            audited = root / "odd-number-model-forensics-takehome.docx"
            audited.write_bytes(b"audited-sentinel")
            figure_bytes = {
                path.name: path.read_bytes() for path in (root / "figures").iterdir()
            }

            result = subprocess.run(
                [sys.executable, str(root / "build_report.py")],
                cwd=root,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            generated = root / "generated" / audited.name
            self.assertGreater(generated.stat().st_size, 10_000)
            self.assertEqual(audited.read_bytes(), b"audited-sentinel")
            for name, expected in figure_bytes.items():
                self.assertEqual((root / "figures" / name).read_bytes(), expected)


if __name__ == "__main__":
    unittest.main()
