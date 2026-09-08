from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts" / "check_provenance.py"


class ProvenanceCheckerTests(unittest.TestCase):
    def make_project(self, root: Path) -> Path:
        files = {
            "src/token.ts": "export function validateToken() { return true; }\n",
            "formal/model/src/token.lean": "def validateTokenModel := true\n",
            "formal/spec/TokenPolicy.lean": "def tokenPolicy := true\n",
            "formal/proof/TokenPolicy.lean":
                "theorem validateToken_satisfies_policy : True := by trivial\n",
        }
        for name, contents in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents, encoding="utf-8")
        source_hash = hashlib.sha256(files["src/token.ts"].encode()).hexdigest()
        manifest = {
            "version": 1,
            "bindings": [{
                "id": "token-binding",
                "source": "src/token.ts",
                "source_anchor": "function validateToken",
                "source_sha256": source_hash,
                "model": "formal/model/src/token.lean",
                "model_anchor": "def validateTokenModel",
            }],
            "proofs": [{
                "id": "token-proof",
                "spec": "formal/spec/TokenPolicy.lean",
                "spec_anchor": "def tokenPolicy",
                "model": "formal/model/src/token.lean",
                "model_anchor": "def validateTokenModel",
                "proof": "formal/proof/TokenPolicy.lean",
                "proof_anchor": "theorem validateToken_satisfies_policy",
            }],
        }
        path = root / "formal/provenance.yaml"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        return path

    def run_checker(self, project: Path, manifest: Path, *extra: str):
        return subprocess.run(
            [sys.executable, str(CHECKER), str(manifest), "--root", str(project), *extra],
            capture_output=True,
            text=True,
        )

    def test_validates_and_renders_without_external_tools(self) -> None:
        with tempfile.TemporaryDirectory(prefix="formal-provenance-") as temporary:
            project = Path(temporary)
            manifest = self.make_project(project)
            result = self.run_checker(
                project, manifest, "--html", "formal/.formal-spec/provenance.html"
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            report = project / "formal/.formal-spec/provenance.html"
            self.assertIn("Visual source → model → spec → proof", report.read_text())

    def test_rejects_changed_source(self) -> None:
        with tempfile.TemporaryDirectory(prefix="formal-provenance-") as temporary:
            project = Path(temporary)
            manifest = self.make_project(project)
            (project / "src/token.ts").write_text(
                "// changed\nexport function validateToken() { return true; }\n",
                encoding="utf-8",
            )
            result = self.run_checker(project, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("source hash changed", result.stderr)


if __name__ == "__main__":
    unittest.main()
