"""Single owner of the fixed pi baseline anchor (goal 18 L2.1).

BASELINE at the repository root holds one line:

    <full-commit> <release-tag> <distance>

Scripts, source files, fixture stamps, and document references all
derive from these values.  `python3 scripts/baseline-anchor.py check`
fails closed when any operational reference disagrees or the recorded
release/distance no longer matches `git describe`.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_baseline(root: Path = ROOT) -> dict[str, str]:
    path = root / "BASELINE"
    if not path.is_file():
        raise SystemExit("baseline anchor: BASELINE file is missing")
    fields = path.read_text(encoding="ascii").split()
    if (
        len(fields) != 3
        or not re.fullmatch(r"[0-9a-f]{40}", fields[0])
        or not re.fullmatch(r"v\d+\.\d+\.\d+", fields[1])
        or not re.fullmatch(r"\d+", fields[2])
    ):
        raise SystemExit(
            "baseline anchor: BASELINE must be '<full-commit> <vX.Y.Z> <distance>'"
        )
    return {
        "commit": fields[0],
        "release": fields[1],
        "distance": fields[2],
        "short": fields[0][:9],
    }


def describe(commit: str, root: Path = ROOT) -> tuple[str, str]:
    result = subprocess.run(
        ["git", "-C", str(root), "describe", "--tags", commit],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()
    match = re.fullmatch(r"(v\d+\.\d+\.\d+)-(\d+)-g[0-9a-f]+", result)
    if not match:
        if re.fullmatch(r"v\d+\.\d+\.\d+", result):
            # Exact tag: zero commits ahead.
            return result, "0"
        raise SystemExit(f"baseline anchor: cannot describe {commit}: {result}")
    return match.group(1), match.group(2)


HEX_RUN = re.compile(r"[0-9a-f]{7,40}")


def commit_referenced(text: str, commit: str) -> bool:
    """True when text contains the commit or a >=7-hex-char prefix of it.

    A plain substring test only catches the full 40-character form; the
    short forms (9 characters in cache-directory names, 7+ anywhere else)
    escaped it.  A maximal hex run inside a longer digest does not start
    with the commit prefix, so SHA-256 literals do not false-positive.
    """
    return any(
        commit.startswith(match.group(0)) for match in HEX_RUN.finditer(text)
    )


def check(root: Path = ROOT) -> None:
    values = read_baseline(root)
    release, distance = describe(values["commit"], root)
    problems = []
    if (release, distance) != (values["release"], values["distance"]):
        problems.append(
            f"BASELINE says {values['release']}+{values['distance']} but "
            f"git describe says {release}+{distance}"
        )
    manifest = json.loads(
        (root / "test/fixtures/render-diff/scenarios.json").read_text()
    )
    if manifest.get("baselineCommit") != values["commit"]:
        problems.append("scenarios.json baselineCommit disagrees with BASELINE")
    for fixture in (
        root / "test/fixtures/render-diff"
    ).glob("*.json"):
        data = json.loads(fixture.read_text())
        stamp = data.get("baselineCommit")
        if stamp is not None and stamp != values["commit"]:
            problems.append(f"{fixture.name} baselineCommit disagrees with BASELINE")
    readme = (root / "README.md").read_text(encoding="utf-8")
    expected_identity = (
        f"aligned with pi {values['release']} "
        f"(+{values['distance']}, {values['short']})"
    )
    if expected_identity not in readme:
        problems.append("README version line disagrees with BASELINE")
    release_source = (root / "src/cadr-ai/support/release.lisp").read_text(
        encoding="utf-8"
    )
    if "read-baseline-anchor" not in release_source:
        problems.append("release.lisp no longer derives from BASELINE")
    # Denominator (expanded 2026-08-14, previously scripts/*.py only): every
    # file under scripts/ regardless of extension, so a hardcode cannot
    # escape into .sh/.mjs/.ts or the next new extension.  Comments count:
    # the match is textual, and a comment telling a human to type the old
    # hash goes stale exactly the way code does.  Do NOT extend this scan to
    # src/ or test/: provenance citations of the form "pi@<short-sha>
    # file.ts:1-2" are mandated there by the development policy; they cite
    # the baseline, they do not configure it, and scanning them would turn
    # ~194 legitimate lines red.
    for script in sorted((root / "scripts").rglob("*")):
        if not script.is_file() or script.is_symlink():
            continue
        if "__pycache__" in script.parts or script.suffix == ".pyc":
            continue
        if script.name in {"baseline-anchor.py", "check-baseline-anchor.py"}:
            continue
        text = script.read_text(encoding="utf-8", errors="replace")
        if commit_referenced(text, values["commit"]):
            problems.append(
                f"{script.relative_to(root).as_posix()} hardcodes the baseline commit"
            )
    for stale in re.findall(r"[0-9a-f]{40}", readme):
        if stale != values["commit"] and stale not in {
            # git object ids referenced as immutable history
        }:
            pass  # README narrative hashes are checked by the identity line only
    if problems:
        raise SystemExit("baseline anchor: " + "; ".join(problems))
    print(
        "baseline anchor: "
        f"commit={values['commit']} release={values['release']} "
        f"distance={values['distance']} — all operational references agree"
    )


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "check":
        check()
    else:
        for key, value in read_baseline().items():
            print(f"{key}={value}")
