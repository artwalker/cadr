GOAL: Make websocket_stream.stream_roundtrip a fair paired remesure (same transport class on cadr and pi), then remesure with slices unset. If ratio still >1.0×, invent one product hypothesis toward ≤1.0× (prefer <1.0×). Leave patches for parent land. Do not claim met-* until fair remesure exists.

SCOPE: /tmp worktree off tip cadr-migration. May edit harness/pair scripts and (after fair remeter) product websocket path. May write docs/benchmarks/goal26-evidence/websocket_stream-*/ and /tmp/g26-websocket-*.{patch,tsv,json}. Must not dirty /root/projects/cadr tip mid-invent; leave patches for parent.

CONTEXT:
- Essence: docs/benchmarks/goal25-evidence/websocket_stream-freeze/essence.md (229× = TCP vs MockWebSocket)
- Charter: docs/acceptance/goal-v26.md
- Disposition row: docs/benchmarks/goal26-dispositions.tsv metric websocket_stream.stream_roundtrip
- Pair history: docs/performance.md websocket_stream; Pair 102
- Fair options (pick one and prove both sides match): (A) put pi on real loopback TCP like cadr; (B) add an in-process mock transport on cadr that matches MockWebSocket semantics and time that path as the paired product API. Do not mock only one side to fake a win.
- Baseline pi tip alignment Goal23 v0.85.1 d981de122

ACCEPTANCE:
- Written fair-ruler note under docs/benchmarks/goal26-evidence/websocket_stream-fair/ (or /tmp then parent copies) stating which option and why both sides match
- Friend-MachineD remesure n≥5, GOAL20_PART_O_SLICE and GOAL20_FLOOR_SLICE unset, --only-enforce websocket_stream.stream_roundtrip if available
- If ratio ≤1.0× after fair remeter alone: propose disposition met-parity or met-beat (no product keep required)
- If ratio >1.0×: at least one invent cycle (keep or full revert) with /tmp/g26-websocket-decisions.tsv; leave product keep patch only if remesure ≤1.0×
- Leave /tmp/g26-websocket-dispositions.patch updating only the websocket row (open-parity → met-* or still open-parity with next-step note). Never use frozen-unreachable.

VERIFY:
- unset GOAL20_PART_O_SLICE GOAL20_FLOOR_SLICE
- run the repo's Friend-MachineD paired remesure recipe used in Goal25 (search scripts / docs/performance.md); capture ratios.tsv
- python3 -c to print ratio from summary

TIMEBOX: 180 minutes. On expiry return partial fair-ruler status and stop.

FORBIDDEN: no gt/rebase/force-push; no dirty tip mid-invent; no RATIO_CEILINGS drop with speedup; no Goal 20–25 rewrite as incomplete; no leftover-only win; no one-sided mock

REPORT: status, worktree path, head SHA if any, fair option chosen, ratios before/after, patches, deviations, follow-ups

STANDING: read /root/projects/cadr/.orchestrate/goal26/preferences.md verbatim and obey
