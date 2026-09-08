from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RepositoryLayoutTests(unittest.TestCase):
    def test_delivery_is_a_root_skill_with_libspec(self) -> None:
        self.assertTrue((ROOT / "SKILL.md").is_file())
        self.assertTrue((ROOT / "LibSpec/LibSpec.lean").is_file())
        self.assertTrue((ROOT / "scripts/check_provenance.py").is_file())

    def test_delivery_has_no_backend_or_adapter_tree(self) -> None:
        self.assertFalse((ROOT / "adapters").exists())
        self.assertFalse((ROOT / "backends").exists())
        self.assertFalse((ROOT / "formal-spec").exists())

    def test_repository_uses_its_own_formal_layout(self) -> None:
        for path in (
            "formal/model.lean",
            "formal/spec.lean",
            "formal/proof.lean",
            "formal/provenance.yaml",
            "formal/model/SKILL.lean",
            "formal/model/scripts/check_provenance.lean",
            "formal/spec/Workflow.lean",
            "formal/spec/Provenance.lean",
            "formal/proof/Workflow.lean",
            "formal/proof/Provenance.lean",
        ):
            with self.subTest(path=path):
                self.assertTrue((ROOT / path).is_file())


if __name__ == "__main__":
    unittest.main()
