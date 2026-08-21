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
        pkce = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-ai/oauth/pkce.lisp"
        ]
        self.assertEqual(len(pkce), 1)
        self.assertEqual(pkce[0]["class"], "paired")
        self.assertIn("oauth_pkce.challenge_urls", pkce[0]["metrics"])
        evals_summary = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-evals/summary.lisp"
        ]
        self.assertEqual(len(evals_summary), 1)
        self.assertEqual(evals_summary[0]["class"], "paired")
        self.assertIn("evals_harness.summarize", evals_summary[0]["metrics"])
        model_data = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-ai/model-data.lisp"
        ]
        self.assertEqual(len(model_data), 1)
        self.assertEqual(model_data[0]["class"], "paired")
        self.assertIn("ai_crypto_model_data.manifest", model_data[0]["metrics"])
        crypto = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-ai/crypto.lisp"
        ]
        self.assertEqual(len(crypto), 1)
        self.assertEqual(crypto[0]["class"], "paired")
        self.assertIn("ai_crypto.hmac", crypto[0]["metrics"])
        matching = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-cli/models/matching.lisp"
        ]
        self.assertEqual(len(matching), 1)
        self.assertEqual(matching[0]["class"], "paired")
        self.assertIn("cli_models_rest.pattern_match", matching[0]["metrics"])
        terminal_image = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/terminal-image.lisp"
        ]
        self.assertEqual(len(terminal_image), 1)
        self.assertEqual(terminal_image[0]["class"], "paired")
        self.assertIn("image_runtime.dimensions", terminal_image[0]["metrics"])
        print_mode = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-cli/modes/print.lisp"
        ]
        self.assertEqual(len(print_mode), 1)
        self.assertEqual(print_mode[0]["class"], "paired")
        self.assertIn("cli_print_rpc.jsonl_line", print_mode[0]["metrics"])
        latex = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/latex.lisp"
        ]
        self.assertEqual(len(latex), 1)
        self.assertEqual(latex[0]["class"], "paired")
        self.assertIn("tui_latex.render", latex[0]["metrics"])
        fuzzy = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/fuzzy.lisp"
        ]
        self.assertEqual(len(fuzzy), 1)
        self.assertEqual(fuzzy[0]["class"], "paired")
        self.assertIn("tui_editor_helpers.fuzzy_match", fuzzy[0]["metrics"])
        terminal_colors = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/terminal-colors.lisp"
        ]
        self.assertEqual(len(terminal_colors), 1)
        self.assertEqual(terminal_colors[0]["class"], "paired")
        self.assertIn("tui_theme_overlay.osc11_bg", terminal_colors[0]["metrics"])
        estimate = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-ai/support/token-estimation.lisp"
        ]
        self.assertEqual(len(estimate), 1)
        self.assertEqual(estimate[0]["class"], "paired")
        self.assertIn("ai_support.estimate_text", estimate[0]["metrics"])
        overflow = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-ai/support/overflow.lisp"
        ]
        self.assertEqual(len(overflow), 1)
        self.assertEqual(overflow[0]["class"], "paired")
        self.assertIn("ai_support.context_overflow", overflow[0]["metrics"])
        select_list = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/components/select-list.lisp"
        ]
        self.assertEqual(len(select_list), 1)
        self.assertEqual(select_list[0]["class"], "paired")
        self.assertIn("tui_select_settings_loaders.filter", select_list[0]["metrics"])
        word_nav = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/word-navigation.lisp"
        ]
        self.assertEqual(len(word_nav), 1)
        self.assertEqual(word_nav[0]["class"], "paired")
        self.assertIn("tui_word_navigation.step", word_nav[0]["metrics"])
        overlay = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/overlay.lisp"
        ]
        self.assertEqual(len(overlay), 1)
        self.assertEqual(overlay[0]["class"], "paired")
        self.assertIn("tui_overlay.composite_line", overlay[0]["metrics"])
        kill_ring = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/kill-ring.lisp"
        ]
        self.assertEqual(len(kill_ring), 1)
        self.assertEqual(kill_ring[0]["class"], "paired")
        self.assertIn("tui_kill_ring.push_peek", kill_ring[0]["metrics"])
        undo_stack = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/undo-stack.lisp"
        ]
        self.assertEqual(len(undo_stack), 1)
        self.assertEqual(undo_stack[0]["class"], "paired")
        self.assertIn("tui_undo_stack.push_pop", undo_stack[0]["metrics"])
        autocomplete = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/autocomplete.lisp"
        ]
        self.assertEqual(len(autocomplete), 1)
        self.assertEqual(autocomplete[0]["class"], "paired")
        self.assertIn("tui_autocomplete.suggest_apply", autocomplete[0]["metrics"])
        keybindings = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/keybindings.lisp"
        ]
        self.assertEqual(len(keybindings), 1)
        self.assertEqual(keybindings[0]["class"], "paired")
        self.assertIn("tui_keybindings.resolve_match", keybindings[0]["metrics"])
        stdin_buffer = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/stdin-buffer.lisp"
        ]
        self.assertEqual(len(stdin_buffer), 1)
        self.assertEqual(stdin_buffer[0]["class"], "paired")
        self.assertIn("tui_stdin_buffer.process", stdin_buffer[0]["metrics"])
        input_component = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/input-component.lisp"
        ]
        self.assertEqual(len(input_component), 1)
        self.assertEqual(input_component[0]["class"], "paired")
        self.assertIn("tui_input_component.edit", input_component[0]["metrics"])
        native_modifiers = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/native-modifiers.lisp"
        ]
        self.assertEqual(len(native_modifiers), 1)
        self.assertEqual(native_modifiers[0]["class"], "paired")
        self.assertIn("tui_native_modifiers.pressed", native_modifiers[0]["metrics"])
        settings_list = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-tui/composition/settings-list.lisp"
        ]
        self.assertEqual(len(settings_list), 1)
        self.assertEqual(settings_list[0]["class"], "paired")
        self.assertIn("tui_settings_list.apply_filter", settings_list[0]["metrics"])
        short_hash = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-ai/capabilities/streaming-json.lisp"
        ]
        self.assertEqual(len(short_hash), 1)
        self.assertEqual(short_hash[0]["class"], "paired")
        self.assertIn("ai_capabilities.short_hash", short_hash[0]["metrics"])
        strip_ansi = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-cli/support/changelog-share.lisp"
        ]
        self.assertEqual(len(strip_ansi), 1)
        self.assertEqual(strip_ansi[0]["class"], "paired")
        self.assertIn("cli_support.strip_ansi", strip_ansi[0]["metrics"])
        normalize_path = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-cli/support/paths.lisp"
        ]
        self.assertEqual(len(normalize_path), 1)
        self.assertEqual(normalize_path[0]["class"], "paired")
        self.assertIn("cli_support.normalize_path", normalize_path[0]["metrics"])
        decode_entity = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-cli/interactive/syntax.lisp"
        ]
        self.assertEqual(len(decode_entity), 1)
        self.assertEqual(decode_entity[0]["class"], "paired")
        self.assertIn(
            "cli_interactive_controller.decode_entity", decode_entity[0]["metrics"]
        )
        cache_version = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-cli/sdk/cache-version.lisp"
        ]
        self.assertEqual(len(cache_version), 1)
        self.assertEqual(cache_version[0]["class"], "paired")
        self.assertIn("cli_sdk.version_newer", cache_version[0]["metrics"])
        provider_defs = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-ai/providers/definitions.lisp"
        ]
        self.assertEqual(len(provider_defs), 1)
        self.assertEqual(provider_defs[0]["class"], "paired")
        self.assertIn("provider_registry_defs.lookup", provider_defs[0]["metrics"])
        skill_prompt = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-cli/sdk/system-prompt.lisp"
        ]
        self.assertEqual(len(skill_prompt), 1)
        self.assertEqual(skill_prompt[0]["class"], "paired")
        self.assertIn("skill_prompt_load.build_prompt", skill_prompt[0]["metrics"])
        bootstrap_tools = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-cli/bootstrap/tools.lisp"
        ]
        self.assertEqual(len(bootstrap_tools), 1)
        self.assertEqual(bootstrap_tools[0]["class"], "paired")
        self.assertIn("cli_bootstrap_sessions.coding_tools", bootstrap_tools[0]["metrics"])
        faux = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-ai/runtime/faux-provider.lisp"
        ]
        self.assertEqual(len(faux), 1)
        self.assertEqual(faux[0]["class"], "paired")
        self.assertIn("ai_runtime_faux.blocks", faux[0]["metrics"])
        http_transport = [
            row
            for row in classified["rows"]
            if row["path"] == "src/cadr-ai/transport/http.lisp"
        ]
        self.assertEqual(len(http_transport), 1)
        self.assertEqual(http_transport[0]["class"], "paired")
        self.assertIn("http_transport.parse_url", http_transport[0]["metrics"])

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
