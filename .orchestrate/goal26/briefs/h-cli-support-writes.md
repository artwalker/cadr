GOAL: Drive the three open cli_support write metrics to ≤1.0× on fair Friend-MachineD remesure (prefer beat): write_overwrite, write_hello, write_empty. Keep bar ≤1.0×. Prefer product invent on atomic-write path; remeter already fair (product call only).

SCOPE: Exclusive worktree /tmp/cadr-g26-h-support-writes off current tip working tree (or tip commit + copy landed remeter/threads). Product write path only (e.g. atomic-file / atomic-write). Evidence /tmp/g26-support-writes-* and docs/benchmarks/goal26-evidence/cli_support-writes-invent/. Disposition patches for the three write metrics only.

CONTEXT:
- Parent landed threads+close met-beat and fair remeter. Writes still open: overwrite 3.329×, hello 5.760×, empty 10.994× (remesure7).
- Prior invent: posix exclusive open+write+rename hit 1.530 / 1.985 / 1.427 and was fully reverted (keep bar ≤1.0×). Next: re-land that, then drop handler-case off success path (~19µs). Empty still needs ~20µs more vs leftover ~42µs.
- Remesure: reuse /tmp/g26-h-support-remesure.sh pattern; --only-enforce the three write keys; SYNC_TIP_PY; slices unset; Friend-MachineD.
- Standing: /root/projects/cadr/.orchestrate/goal26/preferences.md
- Prior report: /tmp/g26-h-support-REPORT.md

ACCEPTANCE:
- Each write metric met-parity/met-beat or still open-parity with measured ratio + next step / gates.md proposal if invent exhausted. Never frozen-unreachable.
- Keep patches only for ≤1.0× keeps; full revert otherwise.
- /tmp/g26-h-support-writes-REPORT.md + decisions.tsv + patches for parent land.

VERIFY: remesure; print three write ratios

TIMEBOX: 180 minutes

FORBIDDEN: no gt/rebase/force-push; no leftover win; no silent freeze; no dirty tip; do not revert threads/close remeter keeps

REPORT: status, ratios table, patches, deviations, follow-ups

STANDING: read preferences.md verbatim and obey
