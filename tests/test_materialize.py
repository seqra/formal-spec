from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MATERIALIZER = ROOT / "scripts" / "materialize_libspec.py"


class MaterializeTests(unittest.TestCase):
    def test_materializes_delivery_without_build_state(self) -> None:
        with tempfile.TemporaryDirectory(prefix="formal-libspec-") as temporary:
            project = Path(temporary)
            first = subprocess.run(
                [sys.executable, str(MATERIALIZER), "--project", str(project)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            delivery = project / "formal/.formal-spec/LibSpec"
            self.assertTrue((delivery / "LibSpec.lean").is_file())
            self.assertFalse((delivery / ".lake").exists())

            check = subprocess.run(
                [
                    sys.executable,
                    str(MATERIALIZER),
                    "--project",
                    str(project),
                    "--check",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(check.returncode, 0, check.stderr)


if __name__ == "__main__":
    unittest.main()
