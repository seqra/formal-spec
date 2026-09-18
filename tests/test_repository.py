from pathlib import Path
import unittest
import xml.etree.ElementTree as ElementTree


ROOT = Path(__file__).resolve().parents[1]


class RepositoryLayoutTests(unittest.TestCase):
    def test_delivery_is_a_self_contained_skill_directory(self) -> None:
        self.assertTrue((ROOT / "skill/SKILL.md").is_file())
        self.assertTrue((ROOT / "skill/LibSpec/LibSpec.lean").is_file())
        self.assertTrue((ROOT / "skill/LibSpec/LibSpec/Testing.lean").is_file())

    def test_delivery_has_no_backend_or_adapter_tree(self) -> None:
        self.assertFalse((ROOT / "skill/adapters").exists())
        self.assertFalse((ROOT / "skill/backends").exists())
        self.assertFalse((ROOT / "skill/formal-spec").exists())

    def test_repository_uses_its_own_formal_layout(self) -> None:
        for path in (
            "formal/model.lean",
            "formal/spec.lean",
            "formal/proof.lean",
            "formal/model/SKILL.lean",
            "formal/spec/Workflow.lean",
            "formal/proof/Workflow.lean",
        ):
            with self.subTest(path=path):
                self.assertTrue((ROOT / path).is_file())

    def test_brand_assets_are_valid_and_wired(self) -> None:
        for relative in ("skill/assets/logo.svg", "skill/assets/cover.svg"):
            with self.subTest(relative=relative):
                root = ElementTree.parse(ROOT / relative).getroot()
                self.assertTrue(root.tag.endswith("svg"))
                self.assertIn("viewBox", root.attrib)
        interface = (ROOT / "skill/agents/openai.yaml").read_text(encoding="utf-8")
        self.assertIn('icon_small: "./assets/logo.svg"', interface)
        self.assertIn('brand_color: "#CA2121"', interface)

    def test_presentation_demo_assets_are_valid(self) -> None:
        gif = (ROOT / "skill/assets/demo.gif").read_bytes()
        video = (ROOT / "skill/assets/demo.mp4").read_bytes()
        self.assertIn(gif[:6], (b"GIF87a", b"GIF89a"))
        self.assertEqual(video[4:8], b"ftyp")


if __name__ == "__main__":
    unittest.main()
