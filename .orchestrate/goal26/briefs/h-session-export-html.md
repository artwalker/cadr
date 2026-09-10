GOAL: Invent product session_export_html.to_html until Friend-MachineD ratio ≤1.0× (prefer beat). Fair remeter already ~2.331× (13867.6/5948.2 µs). Leave keep patch only if remesure ≤1.0×.

SCOPE: Exclusive worktree /tmp/cadr-g26-h-export off tip. Product src for export-session-html / templates / JSON path. Evidence /tmp/g26-export-* and docs/benchmarks/goal26-evidence/session_export_html-invent/. Disposition patch only that metric.

CONTEXT:
- Essence: docs/benchmarks/goal25-evidence/session_export_html-freeze/essence.md
- Baseline 2.331× gate PASS; html_chars 555702 vs 547028 booked size gap
- Remesure lever pattern /tmp/g26-h-websocket-remesure.sh; --only-enforce session_export_html.to_html; REUSE pi.json when only cadr changes; slices unset
- Standing: /root/projects/cadr/.orchestrate/goal26/preferences.md

ACCEPTANCE:
- Friend-MachineD remesure after invent ≤1.0× → met-parity or met-beat + keep patch
- If invent exhausts: leave open-parity + decisions; optional gates.md proposal for accepted-runtime-gap (no silent freeze)
- /tmp/g26-h-export-REPORT.md + decisions.tsv + patches

VERIFY: remesure; print ratio

TIMEBOX: 180 minutes

FORBIDDEN: no gt/rebase/force-push; no leftover win; no silent freeze; no dirty tip; no RATIO_CEILINGS+speedup

REPORT: status, ratios, patches, deviations, follow-ups

STANDING: read preferences.md verbatim and obey
