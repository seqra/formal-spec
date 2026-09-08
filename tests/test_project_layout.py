from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MATERIALIZER = ROOT / "scripts" / "materialize_libspec.py"


class DocumentedProjectLayoutTests(unittest.TestCase):
    def test_documented_lake_layout_builds(self) -> None:
        with tempfile.TemporaryDirectory(prefix="formal-layout-") as temporary:
            project = Path(temporary)
            subprocess.run(
                [sys.executable, str(MATERIALIZER), "--project", str(project)],
                check=True,
                capture_output=True,
                text=True,
            )
            formal = project / "formal"
            files = {
                "lean-toolchain": (ROOT / "LibSpec/lean-toolchain").read_text(),
                "lakefile.toml": """name = "project-formal"
version = "0.1.0"
defaultTargets = ["ProjectFormal"]

[[require]]
name = "libspec"
path = ".formal-spec/LibSpec"

[[lean_lib]]
name = "ProjectFormal"
roots = ["model", "spec", "proof"]
""",
                "model/src/Token.lean": "def validateTokenModel : Bool := true\n",
                "model.lean": "import model.src.Token\n",
                "spec/TokenPolicy.lean":
                    "def tokenPolicy (value : Bool) : Prop := value = true\n",
                "spec.lean": "import spec.TokenPolicy\n",
                "proof/TokenPolicy.lean": """import LibSpec
import model.src.Token
import spec.TokenPolicy

theorem validateToken_satisfies_policy : tokenPolicy validateTokenModel := by
  rfl
""",
                "proof.lean": "import proof.TokenPolicy\n",
            }
            for relative, contents in files.items():
                path = formal / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents, encoding="utf-8")
            result = subprocess.run(
                ["lake", "build"], cwd=formal, capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
