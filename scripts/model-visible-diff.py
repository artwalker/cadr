#!/usr/bin/env python3
"""Cross-implementation model-visible text differential.

OQ-G20-MODEL-VISIBLE-TEXT-GATE. Diffs skills blocks and the custom
system-prompt branch against packages/coding-agent on the pinned
baseline.

Denominator: test/fixtures/model-visible-diff/scenarios.json.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.sax.saxutils


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test/fixtures/model-visible-diff"
SCENARIOS = FIXTURES / "scenarios.json"


def escape_xml(value: str) -> str:
    return xml.sax.saxutils.escape(value, {'"': "&quot;", "'": "&apos;"})


def format_skills_coding_agent(
    skills, file_read_tool: str = "read"
) -> str:
    """Mirror packages/coding-agent/src/core/skills.ts formatSkillsForPrompt."""
    if isinstance(skills, dict):
        skills = [skills]
    if not skills:
        return ""
    load_line = (
        "Use the read tool to load a skill's file when the task matches its description."
        if file_read_tool == "read"
        else "Use bash to load a skill's file when the task matches its description."
    )
    lines = [
        "",
        "",
        "The following skills provide specialized instructions for specific tasks.",
        load_line,
        "When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.",
        "",
        "<available_skills>",
    ]
    for skill in skills:
        lines.extend(
            [
                "  <skill>",
                f"    <name>{escape_xml(skill['name'])}</name>",
                f"    <description>{escape_xml(skill['description'])}</description>",
                f"    <location>{escape_xml(skill['filePath'])}</location>",
                "  </skill>",
            ]
        )
    lines.append("</available_skills>")
    return "\n".join(lines)


def format_skills_harness_variant(skill: dict) -> str:
    """The pre-9e06ab61c / unused agent harness wording (defect class)."""
    lines = [
        "The following skills provide specialized instructions for specific tasks.",
        "Read the full skill file when the task matches its description.",
        "When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.",
        "",
        "<available_skills>",
        "  <skill>",
        f"    <name>{escape_xml(skill['name'])}</name>",
        f"    <description>{escape_xml(skill['description'])}</description>",
        f"    <location>{escape_xml(skill['filePath'])}</location>",
        "  </skill>",
        "</available_skills>",
    ]
    return "\n".join(lines)


def skill_file_read_tool(selected_tools: list[str]) -> str | None:
    if "read" in selected_tools:
        return "read"
    if "bash" in selected_tools:
        return "bash"
    return None


def format_custom_system_prompt(scenario: dict) -> str:
    """Mirror packages/coding-agent/src/core/system-prompt.ts customPrompt branch."""
    tools = scenario.get("selectedTools") or ["read", "bash", "edit", "write"]
    cwd = scenario["cwd"].replace("\\", "/")
    prompt = scenario["customPrompt"]
    append = scenario.get("appendSystemPrompt")
    if append:
        prompt += f"\n\n{append}"
    context_files = scenario.get("contextFiles") or []
    if context_files:
        prompt += "\n\n<project_context>\n\n"
        prompt += "Project-specific instructions and guidelines:\n\n"
        for entry in context_files:
            prompt += (
                f'<project_instructions path="{entry["path"]}">\n'
                f'{entry["content"]}\n'
                "</project_instructions>\n\n"
            )
        prompt += "</project_context>\n"
    tool = skill_file_read_tool(tools)
    skills = scenario.get("skills") or []
    if tool and skills:
        prompt += format_skills_coding_agent(skills, tool)
    prompt += f"\nCurrent working directory: {cwd}\n"
    return prompt


def format_custom_system_prompt_broken(scenario: dict) -> str:
    """Drop the trailing newline on the cwd line (custom-branch defect class)."""
    text = format_custom_system_prompt(scenario)
    suffix = f"\nCurrent working directory: {scenario['cwd'].replace(chr(92), '/')}\n"
    if not text.endswith(suffix):
        raise RuntimeError("custom-prompt broken variant could not locate cwd suffix")
    return text[: -len(suffix)] + suffix[:-1]


def _run_lisp(lisp: str) -> str:
    env = os.environ.copy()
    env["HOME"] = "/root"
    env.pop("ASDF_OUTPUT_TRANSLATIONS", None)
    env.pop("XDG_CACHE_HOME", None)
    ql = env.get("QUICKLISP_SETUP", "/root/quicklisp/setup.lisp")
    with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False) as handle:
        handle.write(lisp)
        path = handle.name
    try:
        completed = subprocess.run(
            [
                "sbcl",
                "--noinform",
                "--non-interactive",
                "--load",
                ql,
                "--load",
                path,
            ],
            check=True,
            capture_output=True,
            text=True,
            env=env,
            cwd=str(ROOT),
        )
    finally:
        os.unlink(path)
    return completed.stdout


def _extract_marker(stdout: str, begin: str, end: str) -> str:
    start = stdout.rfind(begin)
    stop = stdout.rfind(end)
    if start < 0 or stop < 0 or stop < start:
        raise RuntimeError(f"markers missing; stdout={stdout!r}")
    return stdout[start + len(begin) : stop]


def capture_cadr_skills_block(skill: dict, file_read_tool: str = "read") -> str:
    tool_arg = ":read" if file_read_tool == "read" else ":bash"
    lisp = f"""
(asdf:load-asd (truename "{ROOT}/cadr-core.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-ai.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-agent.asd"))
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (asdf:load-system "cadr-agent"))
(let* ((skill (cadr-agent::make-skill
               :name {json.dumps(skill['name'])}
               :description {json.dumps(skill['description'])}
               :content "x"
               :file-path {json.dumps(skill['filePath'])}))
       (formatted (cadr-agent::format-skills-for-system-prompt
                   (list skill) {tool_arg})))
  (write-string "<<<CADR-SKILLS-BEGIN>>>")
  (write-string formatted)
  (write-string "<<<CADR-SKILLS-END>>>")
  (terpri))
"""
    return _extract_marker(
        _run_lisp(lisp), "<<<CADR-SKILLS-BEGIN>>>", "<<<CADR-SKILLS-END>>>"
    )


def capture_cadr_custom_system_prompt(scenario: dict) -> str:
    tools = scenario.get("selectedTools") or ["read", "bash", "edit", "write"]
    skills = scenario.get("skills") or []
    context_files = scenario.get("contextFiles") or []
    skill_forms = " ".join(
        f'(cadr-agent:make-skill :name {json.dumps(skill["name"])} '
        f':description {json.dumps(skill["description"])} '
        f':content "x" :file-path {json.dumps(skill["filePath"])})'
        for skill in skills
    )
    context_forms = " ".join(
        f'(list :path {json.dumps(entry["path"])} '
        f':content {json.dumps(entry["content"])})'
        for entry in context_files
    )
    append = scenario.get("appendSystemPrompt")
    append_form = (
        f':append-system-prompt {json.dumps(append)}' if append else ""
    )
    selected_form = " ".join(json.dumps(name) for name in tools)
    lisp = f"""
(asdf:load-asd (truename "{ROOT}/cadr-core.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-ai.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-agent.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-tui.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-storage.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-protocol.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-cli.asd"))
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (asdf:load-system "cadr-cli"))
(let ((formatted
        (cadr-cli:build-system-prompt
         :custom-prompt {json.dumps(scenario["customPrompt"])}
         {append_form}
         :selected-tools (list {selected_form})
         :context-files (list {context_forms})
         :skills (list {skill_forms})
         :cwd {json.dumps(scenario["cwd"])})))
  (write-string "<<<CADR-CUSTOM-BEGIN>>>")
  (write-string formatted)
  (write-string "<<<CADR-CUSTOM-END>>>")
  (terpri))
"""
    return _extract_marker(
        _run_lisp(lisp), "<<<CADR-CUSTOM-BEGIN>>>", "<<<CADR-CUSTOM-END>>>"
    )


def run_skills_scenario(scenario: dict, case_dir: Path, failures: list[str]) -> None:
    skill = scenario["skill"]
    file_read_tool = scenario.get("fileReadTool", "read")
    cadr_text = capture_cadr_skills_block(skill, file_read_tool)
    baseline_text = format_skills_coding_agent(skill, file_read_tool)
    broken = format_skills_harness_variant(skill)
    (case_dir / "cadr.skills.txt").write_text(cadr_text, encoding="utf-8")
    (case_dir / "baseline.skills.txt").write_text(baseline_text, encoding="utf-8")
    (case_dir / "broken-harness.skills.txt").write_text(broken, encoding="utf-8")
    if cadr_text != baseline_text:
        failures.append(
            f"{scenario['id']}: cadr skills block != pinned coding-agent formatter"
        )
    if broken == baseline_text:
        failures.append(
            f"{scenario['id']}: validity proof collapsed; harness variant matches baseline"
        )
    if broken == cadr_text:
        failures.append(
            f"{scenario['id']}: validity proof collapsed; cadr matches harness variant"
        )


def run_custom_prompt_scenario(
    scenario: dict, case_dir: Path, failures: list[str]
) -> None:
    cadr_text = capture_cadr_custom_system_prompt(scenario)
    baseline_text = format_custom_system_prompt(scenario)
    broken = format_custom_system_prompt_broken(scenario)
    (case_dir / "cadr.custom-prompt.txt").write_text(cadr_text, encoding="utf-8")
    (case_dir / "baseline.custom-prompt.txt").write_text(
        baseline_text, encoding="utf-8"
    )
    (case_dir / "broken-cwd-newline.custom-prompt.txt").write_text(
        broken, encoding="utf-8"
    )
    if cadr_text != baseline_text:
        failures.append(
            f"{scenario['id']}: cadr custom prompt != pinned system-prompt.ts branch"
        )
    if broken == baseline_text:
        failures.append(
            f"{scenario['id']}: validity proof collapsed; broken cwd newline matches baseline"
        )
    if broken == cadr_text:
        failures.append(
            f"{scenario['id']}: validity proof collapsed; cadr matches broken cwd newline"
        )


def capture_cadr_compaction_prompts() -> dict[str, str]:
    lisp = f"""
(asdf:load-asd (truename "{ROOT}/cadr-core.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-ai.asd"))
(asdf:load-asd (truename "{ROOT}/cadr-agent.asd"))
(let ((*standard-output* (make-broadcast-stream))
      (*error-output* (make-broadcast-stream)))
  (asdf:load-system "cadr-agent"))
(dolist (pair
         (list
          (list "system" cadr-agent::+compaction-summarization-system-prompt+)
          (list "prompt" cadr-agent::+compaction-summarization-prompt+)
          (list "update" cadr-agent::+compaction-update-summarization-prompt+)))
  (destructuring-bind (label text) pair
    (format t "<<<~A-BEGIN>>>~A<<<~A-END>>>~%" label text label)))
"""
    stdout = _run_lisp(lisp)
    return {
        label: _extract_marker(stdout, f"<<<{label}-BEGIN>>>", f"<<<{label}-END>>>")
        for label in ("system", "prompt", "update")
    }


def run_compaction_prompts_scenario(
    scenario: dict, case_dir: Path, failures: list[str]
) -> None:
    cadr = capture_cadr_compaction_prompts()
    baseline = {
        "system": (FIXTURES / "baseline-compaction-system-prompt.txt").read_text(
            encoding="utf-8"
        ),
        "prompt": (
            FIXTURES / "baseline-compaction-summarization-prompt.txt"
        ).read_text(encoding="utf-8"),
        "update": (FIXTURES / "baseline-compaction-update-prompt.txt").read_text(
            encoding="utf-8"
        ),
    }
    broken = {
        "system": baseline["system"].replace(
            "ONLY output the structured summary.",
            "ONLY output the structured summary!",
            1,
        ),
        "prompt": baseline["prompt"].replace(
            "Keep each section concise.",
            "Keep each section concise!",
            1,
        ),
        "update": baseline["update"].replace(
            "Keep each section concise.",
            "Keep each section concise!",
            1,
        ),
    }
    for key in ("system", "prompt", "update"):
        (case_dir / f"cadr.{key}.txt").write_text(cadr[key], encoding="utf-8")
        (case_dir / f"baseline.{key}.txt").write_text(
            baseline[key], encoding="utf-8"
        )
        (case_dir / f"broken.{key}.txt").write_text(broken[key], encoding="utf-8")
        if cadr[key] != baseline[key]:
            failures.append(
                f"{scenario['id']}: cadr compaction {key} != pinned baseline fixture"
            )
        if broken[key] == baseline[key]:
            failures.append(
                f"{scenario['id']}: validity proof collapsed; broken {key} matches baseline"
            )
        if broken[key] == cadr[key]:
            failures.append(
                f"{scenario['id']}: validity proof collapsed; cadr {key} matches broken"
            )


def run_gate(artifacts: Path) -> int:
    doc = json.loads(SCENARIOS.read_text(encoding="utf-8"))
    artifacts.mkdir(parents=True, exist_ok=True)
    (artifacts / "denominator.json").write_text(
        json.dumps(doc["denominator"], indent=2) + "\n", encoding="utf-8"
    )
    failures: list[str] = []
    for scenario in doc["scenarios"]:
        case_dir = artifacts / scenario["id"]
        case_dir.mkdir(parents=True, exist_ok=True)
        kind = scenario.get("kind", "skills-block")
        if kind == "skills-block":
            run_skills_scenario(scenario, case_dir, failures)
        elif kind == "custom-prompt":
            run_custom_prompt_scenario(scenario, case_dir, failures)
        elif kind == "compaction-prompts":
            run_compaction_prompts_scenario(scenario, case_dir, failures)
        else:
            failures.append(f"{scenario['id']}: unknown kind {kind!r}")
    report = {"failures": failures, "ok": not failures}
    (artifacts / "report.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    if failures:
        for item in failures:
            print(f"model-visible-diff FAIL: {item}", file=sys.stderr)
        return 1
    print("model-visible-diff: OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts", type=Path, required=True)
    args = parser.parse_args()
    return run_gate(args.artifacts)


if __name__ == "__main__":
    raise SystemExit(main())
