#!/usr/bin/env python3
"""Deterministic orchestration tests for the fixed-baseline render gate."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/render-diff.py"
SPEC = importlib.util.spec_from_file_location("cadr_render_diff", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
RENDER_DIFF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RENDER_DIFF)


class RenderDiffGateTest(unittest.TestCase):
    def arguments(self, output: Path) -> argparse.Namespace:
        return argparse.Namespace(
            manifest=ROOT / "test/fixtures/render-diff/scenarios.json",
            dispositions=ROOT / "test/fixtures/render-diff/dispositions.json",
            pi_repo=ROOT,
            output=output,
            analysis_output=output / "analysis",
            baseline_cache=Path("/tmp/unused-render-diff-baseline"),
            timeout=20.0,
            tier="core",
            visible_string_inventory=ROOT / "test/fixtures/render-diff/baseline-visible-strings.json",
            visible_string_exemptions=ROOT / "test/fixtures/render-diff/visible-string-exemptions.json",
        )

    def test_human_text_waits_ignore_visible_site_markers(self) -> None:
        begin = (
            b"\x1b]777;cadr-visible-branch;phase=begin;"
            b"site=VS-0000000000000001;branch=B-000000000001\x07"
        )
        end = (
            b"\x1b]777;cadr-visible-branch;phase=end;"
            b"site=VS-0000000000000001;branch=B-000000000001\x07"
        )
        output = bytearray(b"What's" + begin + b" New" + end)

        RENDER_DIFF.wait_for(
            -1,
            output,
            b"What's New",
            0.0,
            mock.Mock(),
            semantic=True,
        )
        RENDER_DIFF.wait_for_count(
            -1,
            output,
            b"What's New",
            1,
            0.0,
            mock.Mock(),
            semantic=True,
        )

        with self.assertRaisesRegex(RENDER_DIFF.HarnessFailure, "timed out"):
            RENDER_DIFF.wait_for(
                -1,
                output,
                b"What's New",
                0.0,
                mock.Mock(),
            )

    def test_checkpoint_waits_for_the_open_synchronized_render_frame(self) -> None:
        read_fd, write_fd = os.pipe()
        output = bytearray(b"\x1b[?2026hframe text")
        entered = threading.Event()
        completed = threading.Event()

        class LiveProcess:
            @staticmethod
            def poll() -> None:
                return None

        def wait_for_frame() -> None:
            entered.set()
            RENDER_DIFF.wait_for_complete_render(
                read_fd, output, 1.0, LiveProcess()
            )
            completed.set()

        worker = threading.Thread(target=wait_for_frame)
        try:
            worker.start()
            self.assertTrue(entered.wait(1.0))
            self.assertFalse(completed.is_set())
            os.write(write_fd, b"\x1b[?2026l")
            worker.join(1.0)
            self.assertFalse(worker.is_alive())
            self.assertTrue(completed.is_set())
            self.assertTrue(output.endswith(b"\x1b[?2026l"))
        finally:
            os.close(write_fd)
            os.close(read_fd)

    def test_agent_settled_wait_requires_a_post_submit_non_busy_frame(self) -> None:
        source = (ROOT / "scripts/render-diff.py").read_text(encoding="utf-8")
        branch = source.split('elif "waitForAgentSettled" in action:', 1)[1].split(
            'elif "checkpoint" in action:', 1
        )[0]

        self.assertIn("output.count(render_end) > settled_render_floor", branch)
        self.assertIn('b"Working..."', branch)
        self.assertIn("wait_for_count(", branch)
        self.assertIn("wait_for_complete_render(", branch)

    def test_agent_settled_accepts_cleanup_frame_completed_before_marker_poll(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cadr-render-settled-") as temporary:
            ready = Path(temporary) / "ready"
            ready.write_text("ready\nagent-settled\n", encoding="utf-8")
            output = bytearray(b"\x1b[?2026hsettled\x1b[?2026l")

            with mock.patch.object(RENDER_DIFF, "drain"), mock.patch.object(
                RENDER_DIFF,
                "read_ready",
                side_effect=AssertionError("must not wait for a nonexistent extra frame"),
            ):
                RENDER_DIFF.run_actions(
                    "cadr",
                    [{"waitForAgentSettled": True}],
                    -1,
                    output,
                    mock.Mock(),
                    1.0,
                    [],
                    ready,
                )

    def test_agent_settled_rejects_busy_frame_until_cleanup_frame_arrives(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cadr-render-settled-") as temporary:
            ready = Path(temporary) / "ready"
            ready.write_text("ready\nagent-settled\n", encoding="utf-8")
            output = bytearray(b"\x1b[?2026hWorking...\x1b[?2026l")
            observed: list[float] = []

            def finish_render(
                _fd: int,
                target: bytearray,
                timeout: float,
                _process: object,
            ) -> None:
                observed.append(timeout)
                target.extend(b"\x1b[?2026hsettled\x1b[?2026l")

            with mock.patch.object(RENDER_DIFF, "drain"), mock.patch.object(
                RENDER_DIFF,
                "read_ready",
                side_effect=finish_render,
            ):
                RENDER_DIFF.run_actions(
                    "cadr",
                    [{"waitForAgentSettled": True}],
                    -1,
                    output,
                    mock.Mock(),
                    1.0,
                    [],
                    ready,
                )

        self.assertTrue(observed)

    def test_pause_action_never_passes_a_negative_select_timeout(self) -> None:
        observed: list[float] = []

        with mock.patch.object(
            RENDER_DIFF.time,
            "monotonic",
            side_effect=[1.0, 1.005, 1.011, 1.012],
        ), mock.patch.object(
            RENDER_DIFF,
            "read_ready",
            side_effect=lambda _fd, _output, timeout, _process: observed.append(timeout),
        ):
            RENDER_DIFF.run_actions(
                "cadr",
                [{"pauseMs": 10}],
                -1,
                bytearray(),
                mock.Mock(),
                1.0,
                [],
            )

        self.assertEqual(observed, [0.0])

    def test_agent_settled_action_waits_on_the_driver_side_channel(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cadr-render-settled-") as temporary:
            ready = Path(temporary) / "ready"
            ready.write_text("ready\nagent-settled\n", encoding="utf-8")
            observed: list[float] = []

            def finish_render(
                _fd: int,
                output: bytearray,
                timeout: float,
                _process: object,
            ) -> None:
                observed.append(timeout)
                output.extend(b"\x1b[?2026hsettled\x1b[?2026l")

            with mock.patch.object(
                RENDER_DIFF,
                "read_ready",
                side_effect=finish_render,
            ), mock.patch.object(RENDER_DIFF, "drain"):
                RENDER_DIFF.run_actions(
                    "cadr",
                    [{"waitForAgentSettled": True}],
                    -1,
                    bytearray(),
                    mock.Mock(),
                    1.0,
                    [],
                    ready,
                )

        self.assertTrue(observed)

    def test_both_render_drivers_publish_agent_settled_side_channel_events(self) -> None:
        self.assertIn(
            "agent-settled",
            (ROOT / "test/fixtures/render-diff/cadr-driver.lisp").read_text(
                encoding="utf-8"
            ),
        )
        self.assertIn(
            "agent-settled",
            (ROOT / "test/fixtures/render-diff/pi-driver.ts").read_text(
                encoding="utf-8"
            ),
        )

    def test_session_capture_waits_for_the_complete_frame(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        scenario = next(
            item for item in manifest["scenarios"]
            if item["id"] == "commands-informational"
        )
        actions = scenario["actions"]
        checkpoint = next(
            index for index, action in enumerate(actions)
            if action.get("checkpoint") == "slash-session"
        )
        self.assertEqual(actions[checkpoint - 1], {"pauseMs": 80})
        self.assertEqual(actions[checkpoint - 2], {"waitFor": "Cache Re-billed:"})

    def test_parallel_tool_capture_waits_for_the_agent_end_frame(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        scenario = next(
            item for item in manifest["scenarios"]
            if item["id"] == "tools-significant-states"
        )
        actions = scenario["actions"]
        checkpoint = next(
            index for index, action in enumerate(actions)
            if action.get("checkpoint") == "parallel-tool-calls"
        )
        self.assertEqual(actions[checkpoint - 1], {"waitForAgentSettled": True})
        self.assertEqual(
            actions[checkpoint - 2], {"waitFor": "parallel calls observed."}
        )

    def test_every_significant_tool_state_waits_for_the_agent_end_frame(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        scenario = next(
            item for item in manifest["scenarios"]
            if item["id"] == "tools-significant-states"
        )
        actions = scenario["actions"]
        checkpoints = [
            index for index, action in enumerate(actions)
            if "checkpoint" in action
        ]
        self.assertEqual(8, len(checkpoints))
        for checkpoint in checkpoints:
            self.assertEqual(
                {"waitForAgentSettled": True},
                actions[checkpoint - 1],
                actions[checkpoint]["checkpoint"],
            )

    def test_stream_abort_capture_waits_for_the_agent_end_frame(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        scenario = next(
            item for item in manifest["scenarios"]
            if item["id"] == "stream-interrupt-queue"
        )
        actions = scenario["actions"]
        checkpoint = next(
            index for index, action in enumerate(actions)
            if action.get("checkpoint") == "stream-aborted"
        )
        self.assertEqual(actions[checkpoint - 1], {"waitForAgentSettled": True})
        self.assertEqual(actions[checkpoint - 2], {"waitFor": "Operation aborted"})

    def test_user_bash_running_capture_waits_for_a_complete_frame(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        scenario = next(
            item for item in manifest["scenarios"]
            if item["id"] == "user-bash-state-sweep"
        )
        actions = scenario["actions"]
        checkpoint = next(
            index for index, action in enumerate(actions)
            if action.get("checkpoint") == "user-bash-running"
        )
        self.assertEqual(actions[checkpoint - 1], {"pauseMs": 80})
        self.assertEqual(actions[checkpoint - 2], {"waitFor": "Running..."})

    def test_peer_session_directories_have_identical_visible_lengths(self) -> None:
        root = Path("/tmp/cadr-render-diff-fixed")
        pi = RENDER_DIFF.render_side_session_directory(root, "pi")
        cadr = RENDER_DIFF.render_side_session_directory(root, "cadr")
        self.assertEqual(len(str(pi)), len(str(cadr)))
        self.assertEqual(pi.name, "render-sessions")
        self.assertEqual(cadr.name, "render-sessions")

    def test_gate_captures_every_manifest_pair_before_real_analysis(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        expected = [
            (scenario["id"], dimension["id"], "both")
            for dimension in manifest["dimensions"]
            for scenario in manifest["scenarios"]
            if scenario.get("tier", "core") == "core"
        ]
        calls: list[tuple[str, str, str]] = []
        caches: list[Path] = []

        def record_capture(arguments: argparse.Namespace) -> int:
            calls.append((arguments.scenario, arguments.dimension, arguments.side))
            caches.append(arguments.cadr_cache)
            return 0

        with tempfile.TemporaryDirectory(prefix="cadr-render-gate-test-") as temporary:
            arguments = self.arguments(Path(temporary) / "captures")
            with mock.patch.object(RENDER_DIFF, "capture", side_effect=record_capture), mock.patch.object(
                RENDER_DIFF, "analyze", return_value=0
            ) as analyze:
                self.assertEqual(RENDER_DIFF.gate(arguments), 0)

        self.assertEqual(calls, expected)
        self.assertEqual(
            len(calls),
            len([s for s in manifest["scenarios"] if s.get("tier", "core") == "core"])
            * len(manifest["dimensions"]),
        )
        self.assertEqual(len(set(caches)), 1)
        self.assertEqual(caches[0], arguments.output.resolve() / ".cadr-cache")
        analyze.assert_called_once_with(arguments)

    def test_gate_never_analyzes_an_incomplete_capture_matrix(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cadr-render-gate-test-") as temporary:
            arguments = self.arguments(Path(temporary) / "captures")
            with mock.patch.object(
                RENDER_DIFF,
                "capture",
                side_effect=RENDER_DIFF.HarnessFailure("capture stopped"),
            ), mock.patch.object(RENDER_DIFF, "analyze") as analyze:
                with self.assertRaisesRegex(RENDER_DIFF.HarnessFailure, "capture stopped"):
                    RENDER_DIFF.gate(arguments)
        analyze.assert_not_called()

    def test_reachable_interface_registry_is_complete_against_fixed_baseline(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        registry = RENDER_DIFF.load_interface_registry(
            ROOT / "test/fixtures/render-diff/reachable-interfaces.json",
            manifest,
            ROOT,
        )

        inventory = RENDER_DIFF.load_baseline_interface_inventory(
            ROOT / "test/fixtures/render-diff/baseline-interface-inventory.json",
            ROOT,
            manifest["baselineCommit"],
        )
        self.assertEqual(len(inventory["slashCommands"]), 22)
        self.assertEqual(
            [entry["name"] for entry in registry["slashCommands"]],
            inventory["slashCommands"],
        )
        self.assertEqual(len(inventory["constructorSites"]), 22)
        self.assertEqual(
            sorted(registry["baselineConstructorSites"]),
            inventory["constructorSites"],
        )
        self.assertEqual(len(registry["uncoveredInterfaces"]), 0)
        self.assertEqual(
            {entry["id"] for entry in registry["significantStates"]},
            {
                "bash-output-line-limit",
                "bash-output-byte-limit",
                "bash-output-overlong-line",
                "bash-output-empty",
                "bash-nonzero-exit",
                "bash-timeout",
                "parallel-tool-calls",
                "tool-invalid-arguments",
                "compaction-manual",
                "compaction-threshold",
                "compaction-overflow",
            },
        )
        self.assertEqual(len(registry["uncoveredSignificantStates"]), 0)
        self.assertEqual(len(registry["excludedSignificantStates"]), 0)

    def test_fixed_baseline_inventory_supports_gitless_isolated_builds(self) -> None:
        manifest_path = ROOT / "test/fixtures/render-diff/scenarios.json"
        with mock.patch.object(
            RENDER_DIFF, "git_repository_has_commit", return_value=False
        ):
            manifest = RENDER_DIFF.load_manifest(manifest_path)
            registry = RENDER_DIFF.load_interface_registry(
                ROOT / "test/fixtures/render-diff/reachable-interfaces.json",
                manifest,
                ROOT,
            )
        self.assertEqual(len(registry["slashCommands"]), 22)
        self.assertEqual(len(registry["interfaces"]), 28)

    def test_reachable_interface_registry_fails_closed_for_new_commands_and_missing_captures(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        registry_path = ROOT / "test/fixtures/render-diff/reachable-interfaces.json"

        inventory = RENDER_DIFF.load_baseline_interface_inventory(
            registry_path.with_name("baseline-interface-inventory.json"),
            ROOT,
            manifest["baselineCommit"],
        )
        with mock.patch.object(
            RENDER_DIFF,
            "load_baseline_interface_inventory",
            return_value={
                **inventory,
                "slashCommands": [
                    *inventory["slashCommands"],
                    "new-reachable-command",
                ],
            },
        ):
            with self.assertRaisesRegex(
                RENDER_DIFF.HarnessFailure, "unregistered baseline slash command"
            ):
                RENDER_DIFF.load_interface_registry(
                    registry_path, manifest, ROOT
                )

        registry = RENDER_DIFF.load_interface_registry(
            registry_path, manifest, ROOT
        )
        incomplete = {
            **registry,
            "interfaces": [
                *registry["interfaces"],
                {
                    "id": "unseen-secondary-dialog",
                    "kind": "dialog",
                    "baselineEvidence": {
                        "path": "packages/coding-agent/src/modes/interactive/interactive-mode.ts",
                        "token": "showLoginAuthTypeSelector",
                    },
                    "capture": {
                        "scenario": "missing-scenario",
                        "checkpoint": "missing-checkpoint",
                    },
                },
            ],
        }
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure, "uncaptured reachable interface"
        ):
            RENDER_DIFF.validate_interface_registry(
                incomplete, manifest, ROOT
            )

        with mock.patch.object(
            RENDER_DIFF,
            "load_baseline_interface_inventory",
            return_value={
                **inventory,
                "constructorSites": [
                    *inventory["constructorSites"],
                    "packages/coding-agent/src/modes/interactive/interactive-mode.ts:9999:NewDialogComponent",
                ],
            },
        ):
            with self.assertRaisesRegex(
                RENDER_DIFF.HarnessFailure,
                "baseline interface construction-site registry drift",
            ):
                RENDER_DIFF.load_interface_registry(registry_path, manifest, ROOT)

    def test_significant_state_registry_fails_closed_for_missing_states_and_captures(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        registry_path = ROOT / "test/fixtures/render-diff/reachable-interfaces.json"
        registry = RENDER_DIFF.load_interface_registry(registry_path, manifest, ROOT)

        missing_state = {
            **registry,
            "significantStates": registry["significantStates"][:-1],
        }
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure, "significant-state registry drift"
        ):
            RENDER_DIFF.validate_interface_registry(missing_state, manifest, ROOT)

        missing_from_both = {
            **registry,
            "significantStateDomains": {
                **registry["significantStateDomains"],
                "tool-batch": [],
            },
            "significantStates": registry["significantStates"][:-1],
        }
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure, "significant-state domain registry drift"
        ):
            RENDER_DIFF.validate_interface_registry(missing_from_both, manifest, ROOT)

        uncaptured = {
            **registry,
            "significantStates": [
                {
                    **entry,
                    **(
                        {
                            "capture": {
                                "scenario": "missing-scenario",
                                "checkpoint": "missing-checkpoint",
                            }
                        }
                        if entry["id"] == "bash-output-byte-limit"
                        else {}
                    ),
                }
                for entry in registry["significantStates"]
            ],
        }
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure, "uncaptured significant state"
        ):
            RENDER_DIFF.validate_interface_registry(uncaptured, manifest, ROOT)

    def test_bash_output_path_normalization_is_bounded_to_product_temp_files(self) -> None:
        pi_path = b"Full output: /tmp/pi-bash-2ccded83dc83b1f8.log"
        cadr_path = b"Full output: /tmp/cadr-bash-3994869173-466576989544909805.log"
        unrelated = b"Full output: /tmp/custom-bash-2ccded83dc83b1f8.log"
        self.assertEqual(
            RENDER_DIFF.normalize_fixed_values(pi_path),
            RENDER_DIFF.normalize_fixed_values(cadr_path),
        )
        self.assertEqual(RENDER_DIFF.normalize_fixed_values(unrelated), unrelated)

    def test_direct_bash_spinner_normalization_is_exact_and_bounded(self) -> None:
        pi = (
            b"\x1b[38;2;181;189;104m\xe2\xa0\x8b\x1b[39m "
            b"\x1b[38;2;128;128;128mRunning... (escape/ctrl+c to cancel)"
        )
        cadr = (
            b"\x1b[38;2;181;189;104m\xe2\xa0\xb8\x1b[39m "
            b"\x1b[38;2;128;128;128mRunning... (escape/ctrl+c to cancel)"
        )
        unrelated = b"The model said: \xe2\xa0\xb8 Running..."
        self.assertEqual(
            RENDER_DIFF.normalize_fixed_values(pi),
            RENDER_DIFF.normalize_fixed_values(cadr),
        )
        self.assertEqual(RENDER_DIFF.normalize_fixed_values(unrelated), unrelated)

    def test_compaction_spinner_normalization_is_exact_and_bounded(self) -> None:
        prefix = b"\x1b[38;2;138;190;183m"
        suffixes = (
            b"Compacting context...",
            b"Auto-compacting... (escape to cancel)",
            b"Context overflow detected, Auto-compacting... (escape to cancel)",
        )
        for suffix in suffixes:
            pi = prefix + b"\xe2\xa0\x99\x1b[39m \x1b[38;2;128;128;128m" + suffix
            cadr = prefix + b"\xe2\xa0\x8b\x1b[39m \x1b[38;2;128;128;128m" + suffix
            self.assertEqual(
                RENDER_DIFF.normalize_fixed_values(pi),
                RENDER_DIFF.normalize_fixed_values(cadr),
            )
        unrelated = prefix + b"\xe2\xa0\x99\x1b[39m Model said: Auto-compacting..."
        self.assertEqual(RENDER_DIFF.normalize_fixed_values(unrelated), unrelated)

    def test_wrapped_session_directory_screen_normalization_is_exact_and_bounded(self) -> None:
        pi = (
            b"To resume this session: <PRODUCT> --session-dir /tmp/ca\n"
            b"dr-render-diff-abcdefgh/pi00/render-sessions --session fixed"
        )
        cadr = (
            b"To resume this session: <PRODUCT> --session-dir /tmp/\n"
            b"cadr-render-diff-abcdefgh/cadr/render-sessions --session fixed"
        )
        unrelated = (
            b"To resume this session: <PRODUCT> --session-dir /tmp/ca\n"
            b"dr-render-other-abcdefgh/pi00/render-sessions --session fixed"
        )

        self.assertEqual(
            RENDER_DIFF.normalized_screen(pi, "pi"),
            b"To resume this session: <PRODUCT> --session-dir <SESSION_DIR>"
            b" --session fixed",
        )
        self.assertEqual(
            RENDER_DIFF.normalized_screen(cadr, "cadr"),
            b"To resume this session: <PRODUCT> --session-dir <SESSION_DIR>"
            b" --session fixed",
        )
        self.assertEqual(RENDER_DIFF.normalized_screen(unrelated, "pi"), unrelated)

    def test_resume_session_id_normalization_is_bounded_to_the_resume_hint(self) -> None:
        session_id = b"019fcc98-34ce-7166-84e3-ee03d1bfb3b2"
        plain = b"To resume this session: cadr --session " + session_id
        wrapped = b"To resume this session: cadr --ses\nsion " + session_id
        with_directory = (
            b"To resume this session: cadr --session-dir <SESSION_DIR> --session "
            + session_id
        )
        wrapped_with_directory = (
            b"To resume this session: cadr --session-dir <SESSION_DIR> --ses\nsion "
            + session_id
        )
        ordinary_message = b"The response id is " + session_id

        self.assertEqual(
            RENDER_DIFF.normalize_fixed_values(plain),
            b"To resume this session: <PRODUCT> --session <SESSION_ID>",
        )
        self.assertEqual(
            RENDER_DIFF.normalize_fixed_values(wrapped),
            b"To resume this session: <PRODUCT> --ses\nsion <SESSION_ID>",
        )
        self.assertEqual(
            RENDER_DIFF.normalize_fixed_values(with_directory),
            b"To resume this session: <PRODUCT> --session-dir <SESSION_DIR> "
            b"--session <SESSION_ID>",
        )
        self.assertEqual(
            RENDER_DIFF.normalize_fixed_values(wrapped_with_directory),
            b"To resume this session: <PRODUCT> --session-dir <SESSION_DIR> "
            b"--ses\nsion <SESSION_ID>",
        )
        self.assertEqual(
            RENDER_DIFF.normalize_fixed_values(ordinary_message), ordinary_message
        )

    def test_wrapped_fatal_crash_values_are_normalized_only_in_crash_output(self) -> None:
        cadr = (
            b"Fatal error: forced render crash\n"
            b"Crash log: /tmp/cadr-render-diff-abcdefgh/cadr/h\n"
            b"ome/.cadr/crash/cadr-crash-3994918403-1601836-0.\nlog"
        )
        pi = (
            b"    at Object.crash (/tmp/cadr-render-diff-pi-74caa2649/"
            b"packages/coding-agent/test/goal15-rend\n"
            b"er-driver.ts:756:11)"
        )
        unrelated = (
            b"User text: /tmp/cadr-render-other-abcdefgh/cadr/h\n"
            b"ome/.cadr/crash/cadr-crash-3994918403-1601836-0.\nlog"
        )

        self.assertEqual(
            RENDER_DIFF.normalized_screen(cadr, "cadr"),
            b"Fatal error: forced render crash\n"
            b"Crash log: <HOME>/<PRODUCT_CONFIG>/crash/"
            b"cadr-crash-<CRASH_ID>.log",
        )
        self.assertEqual(
            RENDER_DIFF.normalized_screen(pi, "pi"),
            b"    at Object.crash (<PI_BASELINE>/packages/coding-agent/test/"
            b"goal15-render-driver.ts:<DRIVER_LINE>:<DRIVER_COLUMN>)",
        )
        self.assertEqual(
            RENDER_DIFF.normalized_screen(unrelated, "cadr"), unrelated
        )

    def test_screen_replay_ignores_the_users_tmux_configuration(self) -> None:
        def completed(command: list[str]) -> object:
            if "capture-pane" in command:
                output = b"screen\n"
            elif "display-message" in command:
                output = b"0,0,1\n"
            else:
                output = b""
            return RENDER_DIFF.subprocess.CompletedProcess(command, 0, output, b"")

        with tempfile.TemporaryDirectory(prefix="cadr-render-tmux-config-") as temporary:
            with mock.patch.object(RENDER_DIFF.shutil, "which", return_value="/usr/bin/tmux"), mock.patch.object(
                RENDER_DIFF.subprocess,
                "run",
                side_effect=lambda command, **_kwargs: completed(command),
            ) as run, mock.patch.object(RENDER_DIFF, "wait_for_path") as wait_for_path:
                RENDER_DIFF.tmux_screen(b"hello", 80, 24, Path(temporary))
                replay = (Path(temporary) / "replay.py").read_text(encoding="utf-8")

        wait_for_path.assert_called_once()
        self.assertIn("os.write(1, b'\\x1b[6n')", replay)
        self.assertIn("response.endswith(b'R')", replay)

        for call in run.call_args_list:
            command = call.args[0]
            self.assertEqual(["-f", "/dev/null"], command[3:5])

    def test_semantic_screen_discards_only_hidden_cursor_coordinates(self) -> None:
        hidden_pi = b"screen\n<CURSOR 48,19,0>\n"
        hidden_cadr = b"screen\n<CURSOR 0,16,0>\n"
        visible = b"screen\n<CURSOR 3,4,1>\n"

        self.assertEqual(
            RENDER_DIFF.normalized_screen(hidden_pi, "pi"),
            RENDER_DIFF.normalized_screen(hidden_cadr, "cadr"),
        )
        self.assertIn(
            b"<CURSOR 3,4,1>",
            RENDER_DIFF.normalized_screen(visible, "cadr"),
        )

    def test_full_tier_captures_core_and_full_scenarios(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        calls: list[str] = []
        with tempfile.TemporaryDirectory(prefix="cadr-render-full-test-") as temporary:
            arguments = self.arguments(Path(temporary) / "captures")
            arguments.tier = "full"
            with mock.patch.object(
                RENDER_DIFF,
                "capture",
                side_effect=lambda value: calls.append(
                    f"{value.scenario}:{value.side}"
                ) or 0,
            ), mock.patch.object(
                RENDER_DIFF, "ensure_baseline", return_value=Path(temporary) / "fixed"
            ), mock.patch.object(
                RENDER_DIFF,
                "prepare_instrumented_baseline",
                return_value=Path(temporary) / "instrumented",
            ), mock.patch.object(RENDER_DIFF, "analyze", return_value=0):
                self.assertEqual(RENDER_DIFF.gate(arguments), 0)
        self.assertEqual(
            len(calls), 2 * len(manifest["scenarios"]) * len(manifest["dimensions"])
        )
        self.assertEqual(sum(call.endswith(":both") for call in calls), len(calls) // 2)
        self.assertEqual(sum(call.endswith(":pi") for call in calls), len(calls) // 2)

    def test_visible_string_coverage_fails_closed_for_uncaptured_text(self) -> None:
        inventory = {
            "entries": [
                {
                    "id": "VS-0000000000000001",
                    "site": {"path": "visible.ts", "line": 1},
                    "sink": {"kind": "new:Text", "channel": "printable-visible"},
                    "branches": [{"id": "B-000000000001"}],
                }
            ]
        }
        manifest = {
            "baselineCommit": "fixed",
            "dimensions": [{"id": "wide"}],
            "scenarios": [{"id": "state"}],
        }
        with tempfile.TemporaryDirectory(prefix="cadr-visible-coverage-") as temporary:
            root = Path(temporary)
            (root / "state.wide.pi.raw").write_bytes(b"different text")
            (root / "state.wide.pi.checkpoints.json").write_text(
                '[{"id":"state","offset":14}]\n', encoding="utf-8"
            )
            exemptions = root / "exemptions.json"
            exemptions.write_text(
                '{"schemaVersion":3,"baselineCommit":"fixed","entries":[]}\n',
                encoding="utf-8",
            )
            (root / "analysis").mkdir()
            with self.assertRaisesRegex(
                RENDER_DIFF.HarnessFailure,
                "uncaptured baseline visible-string branches",
            ):
                RENDER_DIFF.analyze_visible_string_coverage(
                    inventory, manifest, {}, exemptions, root / "analysis"
                )

    def test_checked_visible_inventory_has_the_exact_fixed_baseline_branch_universe(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        inventory = json.loads(
            (ROOT / "test/fixtures/render-diff/baseline-visible-strings.json").read_text(
                encoding="utf-8"
            )
        )
        RENDER_DIFF.validate_visible_string_inventory(
            inventory, manifest["baselineCommit"]
        )
        self.assertEqual(707, len(inventory["entries"]))
        self.assertEqual(
            1228,
            sum(len(entry["branches"]) for entry in inventory["entries"]),
        )
        self.assertEqual(
            1200,
            sum(
                len(entry["branches"])
                for entry in inventory["entries"]
                if entry["sink"]["channel"] == "printable-visible"
            ),
        )
        self.assertEqual(
            28,
            sum(
                len(entry["branches"])
                for entry in inventory["entries"]
                if entry["sink"]["channel"] == "terminal-protocol"
            ),
        )
        self.assertEqual(219, len(inventory["sourceInventory"]))
        self.assertEqual(
            143,
            sum(
                entry["site"]["path"].startswith("packages/tui/")
                for entry in inventory["entries"]
            ),
        )

        needle_obligations = {}
        for needle in (
            "Output truncated. Full output:",
            "Sign in with an account",
            "Sign in with an API key",
            "Select authentication method:",
            "Model catalogs refreshed.",
            "to edit all queued messages",
        ):
            obligations = {
                (entry["id"], branch["id"])
                for entry in inventory["entries"]
                for branch in entry["branches"]
                if any(
                    segment.get("kind") == "literal"
                    and needle in segment.get("text", "")
                    for segment in branch["segments"]
                )
            }
            self.assertTrue(obligations, f"missing exact baseline-visible obligation: {needle}")
            needle_obligations[needle] = obligations
        self.assertEqual(
            len(needle_obligations),
            len({next(iter(value)) for value in needle_obligations.values()}),
            "each fixed runtime UI string must map to an independent obligation",
        )

    def test_visible_inventory_accepts_whitespace_and_slot_only_render_branches(self) -> None:
        def site(start: int) -> dict[str, object]:
            return {
                "path": "packages/tui/src/render.ts",
                "line": 1,
                "column": start,
                "start": start,
                "end": start + 1,
                "kind": "render-return",
                "nodeSha256": "a" * 64,
            }

        inventory = {
            "schemaVersion": 3,
            "baselineCommit": "fixed",
            "unresolvedDataflow": [],
            "entries": [
                {
                    "id": "VS-0000000000000001",
                    "site": site(1),
                    "sink": {"kind": "render-return", "channel": "printable-visible"},
                    "branches": [
                        {
                            "id": "B-000000000001",
                            "conditions": [],
                            "runtimeChoices": [],
                            "segments": [
                                {"kind": "literal", "text": " ", "stylePath": []}
                            ],
                        }
                    ],
                },
                {
                    "id": "VS-0000000000000002",
                    "site": site(2),
                    "sink": {"kind": "render-return", "channel": "printable-visible"},
                    "branches": [
                        {
                            "id": "B-000000000002",
                            "conditions": [],
                            "runtimeChoices": [],
                            "segments": [
                                {
                                    "kind": "slot",
                                    "expression": "renderedText",
                                    "stylePath": [],
                                }
                            ],
                        }
                    ],
                },
            ],
        }

        RENDER_DIFF.validate_visible_string_inventory(inventory, "fixed")

    def test_visible_inventory_rejects_any_unresolved_in_root_dataflow(self) -> None:
        inventory = json.loads(
            (ROOT / "test/fixtures/render-diff/baseline-visible-strings.json").read_text(
                encoding="utf-8"
            )
        )
        inventory["unresolvedDataflow"] = [
            {
                "path": "packages/tui/src/components/example.ts",
                "line": 7,
                "expression": "unknownProducer()",
                "reason": "in-root producer has no typed contract",
            }
        ]
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure,
            "contains unresolved dataflow",
        ):
            RENDER_DIFF.validate_visible_string_inventory(
                inventory, inventory["baselineCommit"]
            )

    def test_visible_string_capture_is_bound_to_instrumented_source_site(self) -> None:
        inventory = {
            "entries": [
                {
                    "id": "VS-0000000000000001",
                    "site": {"path": "visible.ts", "line": 7, "kind": "new:Text"},
                    "sink": {"kind": "new:Text", "channel": "printable-visible"},
                    "branches": [
                        {"id": "B-000000000001"},
                        {"id": "B-000000000002"},
                    ],
                }
            ]
        }
        manifest = {
            "baselineCommit": "fixed",
            "dimensions": [{"id": "wide"}, {"id": "narrow"}],
            "scenarios": [
                {"id": "state", "actions": [{"checkpoint": "rendered"}]}
            ],
        }
        with tempfile.TemporaryDirectory(prefix="cadr-visible-site-map-") as temporary:
            root = Path(temporary)
            exemptions = root / "exemptions.json"
            exemptions.write_text(
                '{"schemaVersion":3,"baselineCommit":"fixed","entries":[]}\n',
                encoding="utf-8",
            )
            analysis = root / "analysis"
            analysis.mkdir()
            begin = (
                b"\x1b]777;cadr-visible-branch;phase=begin;"
                b"site=VS-0000000000000001;branch=B-000000000001\x07"
            )
            end = (
                b"\x1b]777;cadr-visible-branch;phase=end;"
                b"site=VS-0000000000000001;branch=B-000000000001\x07"
            )
            marker = begin + b"visible" + end
            with self.assertRaisesRegex(
                RENDER_DIFF.HarnessFailure,
                "B-000000000002",
            ):
                RENDER_DIFF.analyze_visible_string_coverage(
                    inventory,
                    manifest,
                    {
                        "state/wide/rendered": marker,
                        "state/narrow/rendered": marker,
                    },
                    exemptions,
                    analysis,
                )
            with self.assertRaisesRegex(
                RENDER_DIFF.HarnessFailure, "unterminated visible-site branch marker"
            ):
                RENDER_DIFF.visible_branch_ids(begin, "broken")

    def test_visible_branch_effects_accept_crossing_typed_producer_lifetimes(self) -> None:
        def marker(phase: str, site: str, branch: str) -> bytes:
            return (
                f"\x1b]777;cadr-visible-branch;phase={phase};"
                f"site={site};branch={branch}\x07"
            ).encode()

        first = ("VS-0000000000000001", "B-000000000001")
        second = ("VS-0000000000000002", "B-000000000002")
        stream = b"".join(
            [
                marker("begin", *first),
                marker("begin", *second),
                b"visible",
                marker("end", *first),
                marker("end", *second),
            ]
        )

        self.assertEqual(
            RENDER_DIFF.visible_branch_effects(stream, "crossing-producers"),
            [(first, True), (second, True)],
        )

    def test_visible_string_exemption_is_bound_to_one_exact_branch(self) -> None:
        inventory = {
            "entries": [
                {
                    "id": "VS-0000000000000001",
                    "site": {"path": "visible.ts", "line": 7, "kind": "new:Text"},
                    "sink": {"kind": "new:Text", "channel": "printable-visible"},
                    "branches": [
                        {"id": "B-000000000001"},
                        {"id": "B-000000000002"},
                    ],
                }
            ]
        }
        manifest = {"baselineCommit": "fixed"}
        marker = (
            b"\x1b]777;cadr-visible-branch;phase=begin;"
            b"site=VS-0000000000000001;branch=B-000000000001\x07visible"
            b"\x1b]777;cadr-visible-branch;phase=end;"
            b"site=VS-0000000000000001;branch=B-000000000001\x07"
        )
        with tempfile.TemporaryDirectory(prefix="cadr-visible-branch-exemption-") as temporary:
            root = Path(temporary)
            exemptions = root / "exemptions.json"
            exemptions.write_text(
                json.dumps(
                    {
                        "schemaVersion": 3,
                        "baselineCommit": "fixed",
                        "entries": [
                            {
                                "id": "VS-0000000000000001",
                                "branchId": "B-000000000002",
                                "reason": "This exact false branch requires unavailable hardware.",
                                "obstacleKind": "unavailable-physical-device",
                                "baselineEvidence": {
                                    "path": "packages/tui/src/terminal.ts",
                                    "line": 147,
                                },
                                "probe": {
                                    "command": ["test", "-e", "/dev/fixture-device"],
                                    "expected": "exit 0 when the physical device exists",
                                    "observed": "exit 1 on the fixed Linux runner",
                                },
                                "userDecisionId": "USER-2026-08-05-GOAL17-EXEMPTION-001",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            analysis = root / "analysis"
            analysis.mkdir()
            RENDER_DIFF.analyze_visible_string_coverage(
                inventory,
                manifest,
                {"state/wide": marker},
                exemptions,
                analysis,
            )
            report = json.loads(
                (analysis / "visible-string-coverage.json").read_text(encoding="utf-8")
            )
            self.assertEqual(2, len(report))
            self.assertIsNone(report[0]["exemption"])
            self.assertIsNotNone(report[1]["exemption"])

            exemptions.write_text(
                json.dumps(
                    {
                        "schemaVersion": 3,
                        "baselineCommit": "fixed",
                        "entries": [
                            {
                                "id": "VS-0000000000000001",
                                "branchId": "B-000000000002",
                                "reason": "A persuasive paragraph must not be an exemption contract.",
                                "physicalObstacle": "There might be hardware somewhere else.",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                RENDER_DIFF.HarnessFailure,
                "invalid visible-string structured exemption",
            ):
                RENDER_DIFF.load_visible_string_exemptions(exemptions, "fixed")

    def test_terminal_protocol_obligations_are_separate_from_printable_coverage(self) -> None:
        inventory = {
            "entries": [
                {
                    "id": "VS-0000000000000001",
                    "site": {"path": "terminal.ts", "line": 1, "kind": "output:terminal.write"},
                    "sink": {"kind": "output:terminal.write", "channel": "terminal-protocol"},
                    "branches": [{"id": "B-000000000001"}],
                }
            ]
        }
        with tempfile.TemporaryDirectory(prefix="cadr-terminal-protocol-coverage-") as temporary:
            root = Path(temporary)
            exemptions = root / "exemptions.json"
            exemptions.write_text(
                '{"schemaVersion":3,"baselineCommit":"fixed","entries":[]}\n',
                encoding="utf-8",
            )
            analysis = root / "analysis"
            analysis.mkdir()
            RENDER_DIFF.analyze_visible_string_coverage(
                inventory,
                {"baselineCommit": "fixed"},
                {},
                exemptions,
                analysis,
            )
            report = json.loads(
                (analysis / "visible-string-coverage.json").read_text(encoding="utf-8")
            )
            self.assertEqual("terminal-protocol", report[0]["sink"]["channel"])

    def test_printable_marker_requires_a_terminal_cell_effect(self) -> None:
        inventory = {
            "entries": [
                {
                    "id": "VS-0000000000000001",
                    "site": {"path": "visible.ts", "line": 7, "kind": "new:Text"},
                    "sink": {"kind": "new:Text", "channel": "printable-visible"},
                    "branches": [{"id": "B-000000000001"}],
                }
            ]
        }
        begin = (
            b"\x1b]777;cadr-visible-branch;phase=begin;"
            b"site=VS-0000000000000001;branch=B-000000000001\x07"
        )
        end = (
            b"\x1b]777;cadr-visible-branch;phase=end;"
            b"site=VS-0000000000000001;branch=B-000000000001\x07"
        )
        with tempfile.TemporaryDirectory(prefix="cadr-visible-cell-effect-") as temporary:
            root = Path(temporary)
            exemptions = root / "exemptions.json"
            exemptions.write_text(
                '{"schemaVersion":3,"baselineCommit":"fixed","entries":[]}\n',
                encoding="utf-8",
            )
            analysis = root / "analysis"
            analysis.mkdir()
            with self.assertRaisesRegex(
                RENDER_DIFF.HarnessFailure,
                "without a terminal cell/effect",
            ):
                RENDER_DIFF.analyze_visible_string_coverage(
                    inventory,
                    {"baselineCommit": "fixed"},
                    {"state/wide": begin + end + b"unrelated text outside span"},
                    exemptions,
                    analysis,
                )
            RENDER_DIFF.analyze_visible_string_coverage(
                inventory,
                {"baselineCommit": "fixed"},
                {"state/wide": begin + b"\x1b[33mvisible\x1b[0m" + end},
                exemptions,
                analysis,
            )
            RENDER_DIFF.analyze_visible_string_coverage(
                inventory,
                {"baselineCommit": "fixed"},
                {
                    "state/wide": (
                        begin
                        + b"\x1b[2K"
                        + end
                        + begin
                        + b"visible"
                        + end
                    )
                },
                exemptions,
                analysis,
            )

    def test_terminal_protocol_disposition_cannot_hide_screen_content_differences(self) -> None:
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure,
            "cadr-defect disposition remains a gate failure",
        ):
            RENDER_DIFF.validate_result_adjudications(
                [
                    {
                        "key": "known-defect/wide/state",
                        "screenEqual": True,
                        "adjudication": {
                            "classes": ["D01"],
                            "kinds": ["cadr-defect"],
                        },
                    }
                ]
            )

        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure,
            "terminal-protocol-only disposition cannot admit screen differences",
        ):
            RENDER_DIFF.validate_result_adjudications(
                [
                    {
                        "key": "tree/wide/state",
                        "screenEqual": False,
                        "textGeometryEqual": False,
                        "adjudication": {
                            "classes": ["I01"],
                            "kinds": ["intentional-difference"],
                        },
                    }
                ]
            )

        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure,
            "screen-equal result carries a stale semantic disposition",
        ):
            RENDER_DIFF.validate_result_adjudications(
                [
                    {
                        "key": "stale/wide/state",
                        "screenEqual": True,
                        "adjudication": {
                            "classes": ["I01", "I02"],
                            "kinds": ["intentional-difference"],
                        },
                    }
                ]
            )

        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure,
            "terminal-protocol-only disposition cannot admit screen differences",
        ):
            RENDER_DIFF.validate_result_adjudications(
                [
                    {
                        "key": "screen/wide/state",
                        "screenEqual": False,
                        "textGeometryEqual": True,
                        "adjudication": {
                            "classes": ["I01"],
                            "kinds": ["intentional-difference"],
                        },
                    }
                ]
            )

        crash_result = {
            "key": "crash/wide/state",
            "screenEqual": False,
            "textGeometryEqual": False,
            "piScreenSha256": "pi-exact",
            "cadrScreenSha256": "cadr-exact",
            "adjudication": {
                "classes": ["I01", "I02"],
                "kinds": ["intentional-difference"],
            },
        }
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure,
            "screen-difference disposition lacks an exact semantic screen pair",
        ):
            RENDER_DIFF.validate_result_adjudications([crash_result])

        crash_result["adjudication"]["screenSha256"] = {
            "pi": "pi-exact",
            "cadr": "cadr-exact",
        }
        RENDER_DIFF.validate_result_adjudications([crash_result])

        crash_result["cadrScreenSha256"] = "unrelated-new-drift"
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure,
            "semantic screen pair drifted outside the exact I02 disposition",
        ):
            RENDER_DIFF.validate_result_adjudications([crash_result])

    def test_screen_disposition_schema_requires_every_exact_dimension_hash_pair(self) -> None:
        manifest = {
            "dimensions": [{"id": "wide"}, {"id": "narrow"}],
            "scenarios": [
                {"id": "crash", "actions": [{"checkpoint": "fatal"}]}
            ],
        }
        data = {
            "classes": {
                "I01": {"kind": "intentional-difference", "summary": "wire"},
                "I02": {"kind": "intentional-difference", "summary": "crash"},
            },
            "entries": [
                {
                    "scenario": "crash",
                    "checkpoint": "fatal",
                    "dimensions": ["wide", "narrow"],
                    "classes": ["I01", "I02"],
                    "screenSha256": {
                        "wide": {"pi": "a" * 64, "cadr": "b" * 64}
                    },
                }
            ],
        }
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure, "bind every declared dimension"
        ):
            RENDER_DIFF.expand_dispositions(data, manifest)

        data["entries"][0]["screenSha256"]["narrow"] = {
            "pi": "not-a-sha",
            "cadr": "d" * 64,
        }
        with self.assertRaisesRegex(
            RENDER_DIFF.HarnessFailure, "exact Pi/Cadr SHA-256 pair"
        ):
            RENDER_DIFF.expand_dispositions(data, manifest)

        data["entries"][0]["screenSha256"]["narrow"]["pi"] = "c" * 64
        expanded = RENDER_DIFF.expand_dispositions(data, manifest)
        self.assertEqual(
            {"wide", "narrow"},
            {key.split("/")[1] for key in expanded},
        )

    def test_visible_string_inventory_tracks_real_sinks_without_internal_status_data(self) -> None:
        import json

        inventory = json.loads(
            (ROOT / "test/fixtures/render-diff/baseline-visible-strings.json").read_text(
                encoding="utf-8"
            )
        )
        literals = {
            segment["text"]
            for entry in inventory["entries"]
            for branch in entry["branches"]
            for segment in branch["segments"]
            if segment["kind"] == "literal"
        }
        joined = "\n".join(literals)
        for expected in (
            "Session Tree", "Rename Session", "Project trust",
            "Fork from Message", "Model Configuration", "To resume this session:",
        ):
            self.assertIn(expected, joined)
        self.assertEqual(inventory["schemaVersion"], 3)
        self.assertEqual(len(inventory["entries"]), len({entry["id"] for entry in inventory["entries"]}))


class ReleaseVerificationContractTest(unittest.TestCase):
    def run_wrapper(
        self,
        *,
        verify_status: int = 0,
        full_status: int = 0,
        cwd: Path | None = None,
    ) -> tuple[subprocess.CompletedProcess[str], list[str]]:
        with tempfile.TemporaryDirectory(prefix="cadr-release-verify-") as temporary:
            root = Path(temporary)
            project = root / "project"
            scripts = project / "scripts"
            scripts.mkdir(parents=True)
            wrapper = scripts / "verify-release.sh"
            wrapper.write_bytes((ROOT / "scripts/verify-release.sh").read_bytes())
            wrapper.chmod(0o755)
            log = root / "calls.log"
            for name, label, status in (
                ("verify.sh", "verify", verify_status),
                ("test-render-diff-full.sh", "full", full_status),
            ):
                command = scripts / name
                command.write_text(
                    "#!/usr/bin/env bash\n"
                    "set -euo pipefail\n"
                    f"printf '%s\\n' {label} >> \"$CADR_RELEASE_TEST_LOG\"\n"
                    f"exit {status}\n",
                    encoding="utf-8",
                )
                command.chmod(0o755)
            working_directory = cwd or root / "unrelated-cwd"
            working_directory.mkdir(parents=True, exist_ok=True)
            environment = {**os.environ, "CADR_RELEASE_TEST_LOG": str(log)}
            result = subprocess.run(
                [str(wrapper)],
                cwd=working_directory,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
            return result, calls

    def test_release_verification_runs_default_gate_before_full_render_gate(self) -> None:
        result, calls = self.run_wrapper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["verify", "full"])

    def test_default_gate_failure_short_circuits_full_render_gate(self) -> None:
        result, calls = self.run_wrapper(verify_status=17)
        self.assertEqual(result.returncode, 17)
        self.assertEqual(calls, ["verify"])

    def test_full_render_gate_failure_propagates_nonzero(self) -> None:
        result, calls = self.run_wrapper(full_status=23)
        self.assertEqual(result.returncode, 23)
        self.assertEqual(calls, ["verify", "full"])

    def test_release_verification_resolves_the_project_from_any_cwd(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cadr-release-external-cwd-") as temporary:
            result, calls = self.run_wrapper(cwd=Path(temporary))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["verify", "full"])

    def test_default_verify_stays_core_while_release_wrapper_adds_full(self) -> None:
        default_verify = (ROOT / "scripts/verify.sh").read_text(encoding="utf-8")
        release_verify = (ROOT / "scripts/verify-release.sh").read_text(encoding="utf-8")
        self.assertIn('--tier core', default_verify)
        self.assertNotIn('test-render-diff-full.sh', default_verify)
        self.assertIn('set -euo pipefail', release_verify)
        self.assertLess(
            release_verify.index('scripts/verify.sh'),
            release_verify.index('scripts/test-render-diff-full.sh'),
        )
        self.assertNotIn('git tag', release_verify)
        self.assertNotIn('git push', release_verify)


if __name__ == "__main__":
    unittest.main()
