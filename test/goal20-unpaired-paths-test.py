#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_script():
    spec = importlib.util.spec_from_file_location(
        "goal20_unpaired_paths",
        ROOT / "scripts" / "goal20-unpaired-paths.py",
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_script()


class TestClassify(unittest.TestCase):
    def test_longest_prefix_wins(self) -> None:
        rules = [
            {"prefix": "src/cadr-tui/", "class": "unpairable", "pathId": "x"},
            {
                "prefix": "src/cadr-tui/renderer/",
                "class": "paired",
                "metrics": ["goal11.mouse_drag"],
            },
        ]
        hit = MODULE.classify("src/cadr-tui/renderer/main-screen.lisp", rules)
        self.assertEqual(hit["class"], "paired")
        miss = MODULE.classify("src/cadr-cli/repl.lisp", rules)
        self.assertEqual(miss["class"], "pairable-uncovered")

    def test_inventory_classifies_the_locked_tree(self) -> None:
        inventory = MODULE.load_inventory(MODULE.INVENTORY_PATH)
        classified = MODULE.classify_tree(ROOT, inventory)
        self.assertEqual(classified["files"], inventory["denominator"]["files"])
        self.assertEqual(classified["lines"], inventory["denominator"]["lines"])
        totals = classified["totals"]
        self.assertEqual(
            totals["paired"]["files"]
            + totals["unpairable"]["files"]
            + totals["covered-as-callee"]["files"]
            + totals["needs-pair"]["files"]
            + totals["pairable-uncovered"]["files"],
            classified["files"],
        )
        self.assertEqual(totals["pairable-uncovered"]["lines"], 0)
        sqlite = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-agent/sqlite-storage.lisp"
        ]
        self.assertEqual(len(sqlite), 1)
        self.assertEqual(sqlite[0]["class"], "paired")
        self.assertIn("sqlite_session.open_walk", sqlite[0]["metrics"])
        discovery = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-agent/session/discovery.lisp"
        ]
        self.assertEqual(len(discovery), 1)
        self.assertEqual(discovery[0]["class"], "paired")
        self.assertIn("session_discovery.header_probe", discovery[0]["metrics"])
        export_html = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-agent/session/export-html.lisp"
        ]
        self.assertEqual(len(export_html), 1)
        self.assertEqual(export_html[0]["class"], "paired")
        self.assertIn("session_export_html.to_html", export_html[0]["metrics"])
        cbor = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-protocol/cbor.lisp"
        ]
        self.assertEqual(len(cbor), 1)
        self.assertEqual(cbor[0]["class"], "paired")
        self.assertIn("protocol_cbor.roundtrip", cbor[0]["metrics"])
        schema = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-agent/schema.lisp"
        ]
        self.assertEqual(len(schema), 1)
        self.assertEqual(schema[0]["class"], "paired")
        self.assertIn("agent_schema.validate_ok_fail", schema[0]["metrics"])
        jsonl = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-agent/storage/jsonl.lisp"
        ]
        self.assertEqual(len(jsonl), 1)
        self.assertEqual(jsonl[0]["class"], "paired")
        self.assertIn("harness_storage.open_walk", jsonl[0]["metrics"])
        codec = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-protocol/codec.lisp"
        ]
        self.assertEqual(len(codec), 1)
        self.assertEqual(codec[0]["class"], "paired")
        self.assertIn("protocol_codec.roundtrip", codec[0]["metrics"])
        proxy = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-agent/proxy.lisp"
        ]
        self.assertEqual(len(proxy), 1)
        self.assertEqual(proxy[0]["class"], "paired")
        self.assertIn("agent_proxy.stream_roundtrip", proxy[0]["metrics"])

    def test_booked_classes_include_callee_and_needs_pair(self) -> None:
        inventory = MODULE.load_inventory(MODULE.INVENTORY_PATH)
        classified = MODULE.classify_tree(ROOT, inventory)
        classes = {row["class"] for row in classified["rows"]}
        self.assertIn("covered-as-callee", classes)
        self.assertIn("needs-pair", classes)
        self.assertNotIn("pairable-uncovered", classes)

    def test_stale_denominator_fails_closed(self) -> None:
        inventory = MODULE.load_inventory(MODULE.INVENTORY_PATH)
        inventory = json.loads(json.dumps(inventory))
        inventory["denominator"]["files"] = 1
        with self.assertRaises(MODULE.GateError) as raised:
            MODULE.classify_tree(ROOT, inventory)
        self.assertIn("denominator drifted", str(raised.exception))

    def test_unused_prefix_fails_closed(self) -> None:
        inventory = MODULE.load_inventory(MODULE.INVENTORY_PATH)
        inventory = json.loads(json.dumps(inventory))
        inventory["fileRules"].append(
            {
                "prefix": "src/cadr-cli/does-not-exist.lisp",
                "class": "paired",
                "metrics": ["cli_dispatch.argv_parse"],
            }
        )
        with self.assertRaises(MODULE.GateError) as raised:
            MODULE.classify_tree(ROOT, inventory)
        self.assertIn("matched no Lisp file", str(raised.exception))

    def test_check_accepts_the_written_ledger(self) -> None:
        inventory = MODULE.load_inventory(MODULE.INVENTORY_PATH)
        classified = MODULE.classify_tree(ROOT, inventory)
        MODULE.check_ledger(ROOT, inventory, classified)

    def test_replace_refuses_missing_markers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ledger.md"
            path.write_text("# no markers\n", encoding="utf-8")
            with self.assertRaises(MODULE.GateError):
                MODULE.replace_marked_section(path.read_text(encoding="utf-8"), "x")


if __name__ == "__main__":
    unittest.main()
