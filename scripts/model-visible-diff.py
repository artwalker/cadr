#!/usr/bin/env python3
"""Cross-implementation model-visible skills-block differential.

OQ-G20-MODEL-VISIBLE-TEXT-GATE first slice. Diff the skills block cadr
formats against packages/coding-agent/src/core/skills.ts on the pinned
baseline (not the unused agent harness formatter).

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


def read_baseline_commit() -> str:
    text = (ROOT / "BASELINE").read_text(encoding="utf-8").strip()
    return text.split()[0]


def baseline_cache_path() -> Path:
    sha = read_baseline_commit()
    return Path(f"/tmp/cadr-render-diff-pi-{sha[:9]}")


def ensure_baseline_cache(cache: Path) -> Path:
    if (cache / "packages/coding-agent/src/core/skills.ts").is_file():
        return cache
    # Prefer sibling checkout when already at pin, else fail with guidance.
    sibling = Path("/root/projects/pi-mono")
    skills = sibling / "packages/coding-agent/src/core/skills.ts"
    if skills.is_file():
        return sibling
    raise SystemExit(
        f"model-visible-diff: baseline skills.ts not found in {cache} or {sibling}"
    )


def escape_xml(value: str) -> str:
    return xml.sax.saxutils.escape(value, {'"': "&quot;", "'": "&apos;"})


def format_skills_coding_agent(skill: dict) -> str:
    """Mirror packages/coding-agent/src/core/skills.ts formatSkillsForPrompt."""
    lines = [
        "",
        "",
        "The following skills provide specialized instructions for specific tasks.",
        "Use the read tool to load a skill's file when the task matches its description.",
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


def capture_cadr_skills_block(skill: dict) -> str:
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
       (formatted (cadr-agent::format-skills-for-system-prompt (list skill))))
  (write-string "<<<CADR-SKILLS-BEGIN>>>")
  (write-string formatted)
  (write-string "<<<CADR-SKILLS-END>>>")
  (terpri))
"""
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
    stdout = completed.stdout
    begin = "<<<CADR-SKILLS-BEGIN>>>"
    end = "<<<CADR-SKILLS-END>>>"
    start = stdout.rfind(begin)
    stop = stdout.rfind(end)
    if start < 0 or stop < 0 or stop < start:
        raise RuntimeError(f"cadr skills markers missing; stdout={stdout!r}")
    return stdout[start + len(begin) : stop]


def run_gate(artifacts: Path) -> int:
    doc = json.loads(SCENARIOS.read_text(encoding="utf-8"))
    artifacts.mkdir(parents=True, exist_ok=True)
    (artifacts / "denominator.json").write_text(
        json.dumps(doc["denominator"], indent=2) + "\n", encoding="utf-8"
    )
    ensure_baseline_cache(baseline_cache_path())
    failures = []
    for scenario in doc["scenarios"]:
        skill = scenario["skill"]
        cadr_text = capture_cadr_skills_block(skill)
        pi_text = format_skills_coding_agent(skill)
        broken = format_skills_harness_variant(skill)
        case_dir = artifacts / scenario["id"]
        case_dir.mkdir(parents=True, exist_ok=True)
        (case_dir / "cadr.skills.txt").write_text(cadr_text, encoding="utf-8")
        (case_dir / "pi.skills.txt").write_text(pi_text, encoding="utf-8")
        (case_dir / "broken-harness.skills.txt").write_text(broken, encoding="utf-8")
        if cadr_text != pi_text:
            failures.append(f"{scenario['id']}: cadr skills block != pinned coding-agent formatter")
        if broken == pi_text:
            failures.append(
                f"{scenario['id']}: validity proof collapsed; harness variant matches pi"
            )
        if broken == cadr_text:
            failures.append(
                f"{scenario['id']}: validity proof collapsed; cadr matches harness variant"
            )
    report = {"failures": failures, "ok": not failures}
    (artifacts / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
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
