from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "formal" / ".formal-spec"
DESCRIPTION_FILES = (
    Path("spec/Workflow.md"),
    Path("model/SKILL.md"),
    Path("proof/Workflow.md"),
)


class DescriptionWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        materialized = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "materialize_libspec.py"),
             "--project", str(ROOT), "--force"],
            capture_output=True,
            text=True,
        )
        if materialized.returncode != 0:
            raise AssertionError(materialized.stderr)
        generated = subprocess.run(
            ["lake", "exe", "describe-spec"], cwd=ROOT / "formal",
            capture_output=True, text=True,
        )
        if generated.returncode != 0:
            raise AssertionError(generated.stderr)

    def read(self, relative: str | Path) -> str:
        return (OUTPUT / relative).read_text(encoding="utf-8")

    def test_documentation_defines_per_file_description_contract(self) -> None:
        skill = (ROOT / "SKILL.md").read_text(encoding="utf-8")
        reference = (ROOT / "references/descriptions.md").read_text(encoding="utf-8")
        for text in (skill, reference):
            self.assertIn("per-file", text)
            self.assertIn("vocabulary.md", text)
            self.assertIn("describeAs", text)
            self.assertIn("fail", text.lower())
            self.assertTrue(
                "without opening Lean" in text or "does not need to read Lean" in text
            )
            self.assertIn("audit interface", text)
        self.assertNotIn("formal/.formal-spec/spec.md", skill)

    def test_generator_creates_one_reader_spec_per_lean_file(self) -> None:
        for relative in (*DESCRIPTION_FILES, Path("index.md"), Path("vocabulary.md")):
            self.assertTrue((OUTPUT / relative).is_file(), relative)
            self.assertGreater((OUTPUT / relative).stat().st_size, 0, relative)
        self.assertFalse((OUTPUT / "spec.md").exists())
        heading_count = sum(
            sum(line.startswith("## ") for line in self.read(relative).splitlines())
            for relative in DESCRIPTION_FILES
        )
        self.assertEqual(heading_count, 16)

    def test_every_reader_spec_has_source_provenance_and_no_lean(self) -> None:
        for relative in DESCRIPTION_FILES:
            document = self.read(relative)
            source = relative.with_suffix(".lean").as_posix()
            self.assertIn(f"Formal source: [{source}](../../{source})", document)
            self.assertIn("[Vocabulary](../vocabulary.md)", document)
            self.assertNotIn("```", document)
            self.assertNotIn("FormalSpec.", document)
            self.assertNotIn("Exact formal statement", document)

    def test_reader_specs_explain_rules_cases_and_proofs(self) -> None:
        spec = self.read("spec/Workflow.md")
        model = self.read("model/SKILL.md")
        proof = self.read("proof/Workflow.md")
        self.assertIn("**Applies when**", spec)
        self.assertIn("**Must hold**", spec)
        self.assertEqual(model.count("**Preconditions**"), 4)
        self.assertEqual(model.count("**Effects**"), 4)
        self.assertGreaterEqual(model.count("| Field |"), 6)
        self.assertEqual(proof.count("**Proof status:** Checked theorem"), 10)
        self.assertIn("**Scope**", proof)
        self.assertIn("**Given**", proof)
        self.assertIn("**Guarantee**", proof)
        self.assertGreaterEqual(proof.count("**State under review**"), 5)

        for document in (spec, model, proof):
            prose_lines = (line for line in document.splitlines() if not line.startswith("|"))
            self.assertLessEqual(max(map(len, prose_lines)), 140)

    def test_vocabulary_is_separate_and_links_every_definition(self) -> None:
        vocabulary = self.read("vocabulary.md")
        for term in ("## Spec revision", "## Proof revision", "## Tests revision",
                     "## Implementation revision", "## Workflow model"):
            self.assertIn(term, vocabulary)
        self.assertIn("Defined in [model/SKILL.lean](../model/SKILL.lean).", vocabulary)
        self.assertNotIn("Description unavailable", vocabulary)
        self.assertNotIn("## Accepted state reachable", vocabulary)
        self.assertNotIn("## Rejected before proof", vocabulary)
        for relative in DESCRIPTION_FILES:
            self.assertNotIn("## Terms", self.read(relative))

    def test_index_links_every_description(self) -> None:
        index = self.read("index.md")
        for relative in DESCRIPTION_FILES:
            self.assertIn(f"]({relative.as_posix()})", index)
        self.assertIn("](vocabulary.md)", index)
        self.assertNotIn("incomplete", index)
        self.assertIn("| Document | Role | Formal objects | Description |", index)

    def test_contextual_names_and_vocabulary_override_compile(self) -> None:
        result = subprocess.run(
            ["lake", "env", "lean", str(ROOT / "tests" / "fixtures" / "description_context.lean")],
            cwd=ROOT / "formal", capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_skill_check_invokes_tree_generator(self) -> None:
        script = (ROOT / "scripts" / "check_skill.sh").read_text(encoding="utf-8")
        self.assertIn("lake exe describe-spec", script)
        self.assertIn("vocabulary.md", script)
        self.assertIn("spec/Workflow.md", script)
        self.assertNotIn("> \"$spec_report\"", script)
        result = subprocess.run(
            ["sh", "-n", str(ROOT / "scripts" / "check_skill.sh")],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
