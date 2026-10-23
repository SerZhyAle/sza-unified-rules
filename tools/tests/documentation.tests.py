"""Positive/negative documentation checks in independent throwaway Git corpora."""
import importlib.util
import json
import subprocess
import sys
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("documents", ROOT / "tools/docs/check-documents.py")
DOCS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DOCS)


class Documents(unittest.TestCase):
    def setUp(self):
        self.root = ROOT / "temp/S0011_contract-reader-follow-up" / ("docs-" + uuid.uuid4().hex)
        (self.root / "docs").mkdir(parents=True)
        (self.root / "dev").mkdir()
        (self.root / ".gitignore").write_text("dev/\n")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.config = self.root / "docs/corpus.json"
        self.config.write_text(json.dumps({"visibility": "published", "registry": "docs/registry.jsonl",
            "map": "docs/map.md", "roots": ["docs"], "ignore": []}))
        self.page = self.root / "docs/page.md"
        self.page.write_text("# Page\n\n[Heading](#page)\n\n[Stable](https://example.org/docs#stable)\n")
        (self.root / "docs/map.md").touch()
        self.assertEqual(self.check(register=True, render=True)[0], [])

    def check(self, **options):
        return DOCS.check_corpus(self.root, self.config, **options)

    def assertFailure(self, text):
        errors, _ = self.check()
        self.assertTrue(any(text in error for error in errors), errors)

    def test_valid_and_missing_reverse_coverage(self):
        self.assertEqual(self.check()[0], [])
        (self.root / "docs/unannounced.md").write_text("# Unknown")
        self.assertFailure("missing registry entry")

    def test_missing_and_duplicate_records(self):
        self.page.unlink()
        self.assertFailure("missing")
        registry = self.root / "docs/registry.jsonl"
        registry.write_text(registry.read_text() * 2)
        self.assertFailure("duplicate authoritative record")

    def test_anchor_and_missing_file(self):
        self.page.write_text("# Page\n[Bad](#absent)\n[Missing](gone.md)\n")
        self.assertFailure("missing anchor")
        self.assertFailure("missing target")

    def test_duplicate_unicode_and_cross_file_anchors(self):
        self.page.write_text("# Page\n# Page\n# Привет\n[Second](#page-1)\n[Unicode](#привет)\n[Map](map.md#documentation-map)", encoding="utf-8")
        self.assertEqual(self.check()[0], [])

    def test_fenced_and_inline_examples_are_not_links(self):
        self.page.write_text("# Page\n```md\n[Missing](absent.md)\n```\n`[Missing](absent.md)`")
        self.assertEqual(self.check()[0], [])

    def test_generated_map_drift(self):
        (self.root / "docs/map.md").write_text("# Changed")
        self.assertFailure("generated derivative drift")

    def test_house_style_prose_and_literal_code(self):
        self.page.write_text("# Page\nText\u2014text...\n", encoding="utf-8")
        self.assertFailure("house style")
        self.page.write_text("# Page\n`code...`\n```python\ncode...\n```\n")
        self.assertEqual(self.check()[0], [])

    def test_assets_missing_untracked_and_tracked(self):
        self.page.write_text("# Page\n![Image](image.svg)")
        self.assertFailure("missing target")
        (self.root / "docs/image.svg").write_text("<svg/>")
        self.assertFailure("not tracked")
        subprocess.run(["git", "-C", str(self.root), "add", "docs/image.svg"], check=True)
        self.assertEqual(self.check()[0], [])

    def test_offline_http_scripts_fonts_and_pixels(self):
        for snippet in ("[HTTP](http://example.org)", '<script src="https://example.org/app.js"></script>',
                        '<style>@import "https://example.org/font.css";</style>',
                        '![Pixel](https://example.org/pixel.gif)'):
            with self.subTest(snippet=snippet):
                self.page.write_text("# Page\n" + snippet)
                errors, _ = self.check()
                self.assertTrue(any("unsafe external" in e or "unavailable offline" in e for e in errors), errors)

    def test_reference_images_and_escape(self):
        self.page.write_text("# Page\n![Screenshot][image]\n\n[image]: missing.svg\n[Escape](../../outside.md)")
        self.assertFailure("missing target")
        self.assertFailure("escapes repository")

    def test_published_corpus_cannot_expose_ignored_files(self):
        hidden = self.root / "dev/private.md"
        hidden.write_text("# Private")
        self.page.write_text("# Page\n[Hidden](../dev/private.md)")
        self.assertFailure("published link exposes ignored")
        config = json.loads(self.config.read_text())
        config["roots"].append("dev")
        self.config.write_text(json.dumps(config))
        errors, _ = self.check(register=True, render=True)
        self.assertTrue(any("published registry exposes" in e for e in errors), errors)

    def test_local_ignored_assets_and_independent_registry(self):
        self.config = self.root / "dev/corpus.json"
        self.config.write_text(json.dumps({"visibility": "local", "registry": "dev/registry.jsonl",
            "map": "dev/map.md", "roots": ["dev"], "ignore": []}))
        (self.root / "dev/map.md").touch()
        (self.root / "dev/note.md").write_text("# Note\n![Image](image.svg)")
        (self.root / "dev/image.svg").write_text("<svg/>")
        self.assertEqual(self.check(register=True, render=True)[0], [])
        (self.root / "dev/note.md").write_text("# Note\n![Image](../docs/image.svg)")
        (self.root / "docs/image.svg").write_text("<svg/>")
        self.assertFailure("asset outside local corpus")


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Documents)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print(f"documentation-tests: {'PASS' if result.wasSuccessful() else 'FAIL'} (run={result.testsRun} skipped={len(result.skipped)})")
    sys.exit(0 if result.wasSuccessful() else 1)
