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


if __name__ == "__main__":
    unittest.main()
