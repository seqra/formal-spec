from __future__ import annotations

from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DescriptionWorkflowTests(unittest.TestCase):
    def test_documentation_covers_readable_spec_contract(self) -> None:
        skill = (ROOT / "SKILL.md").read_text(encoding="utf-8")
        reference = (ROOT / "references/descriptions.md").read_text(encoding="utf-8")
        for text in (skill, reference):
            self.assertIn("docstring", text)
            self.assertIn("formal statement", text)
            self.assertIn("explicit", text)
        self.assertIn("exact formal statement", skill)
        self.assertIn("describe-spec", skill)
        self.assertIn("formal/.formal-spec/spec.md", skill)

    def test_skill_check_invokes_describe_spec_without_snapshotting_prose(self) -> None:
        script = (ROOT / "scripts/check_skill.sh").read_text(encoding="utf-8")
        self.assertIn("lake exe describe-spec", script)
        self.assertIn('formal/.formal-spec/spec.md', script)
        self.assertIn("-s", script)
        result = subprocess.run(
            ["sh", "-n", str(ROOT / "scripts/check_skill.sh")],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
