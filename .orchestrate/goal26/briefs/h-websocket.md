GOAL: Invent product websocket path on fair remeter until websocket_stream.stream_roundtrip ≤1.0× (prefer <1.0×). Remeter already landed on tip. Re-apply TCP_NODELAY as first keep candidate if remesure still ≤3.05× or better, then hunt remaining gap in connect-http-stream. Leave keep patch only if remesure ≤1.0×.

SCOPE: /tmp worktree off tip. Product src under src/cadr-ai/ (websocket / http stream). Evidence under /tmp/g26-websocket-invent-* and docs/benchmarks/goal26-evidence/websocket_stream-invent/. Update only the websocket row in goal26-dispositions.tsv via patch. No dirty tip mid-invent.

CONTEXT:
- Fair remeter on tip: scripts/goal20-paired-paths.mjs (pi loopback TCP). Evidence: docs/benchmarks/goal26-evidence/websocket_stream-fair/
- Fair baseline 14.47×. TCP_NODELAY alone got 3.05× then reverted (brief forbade keep above 1.0× during pilot). Parent now allows keep if remesure ≤1.0×; intermediate keeps that still leave open-parity should stay reverted unless parent says otherwise. Prefer stacking: land NODELAY only when combined path hits ≤1.0×, OR leave NODELAY in worktree for multi-knife remesure then one keep patch if final ≤1.0×.
- Follow-up from pilot: remaining ~3× after NODELAY in connect-http-stream (get-host-by-name, handshake SHA1, secure-random-bytes).
- Remesure lever: /tmp/g26-websocket-remesure.sh pattern; REUSE pi.json when only cadr changes; slices unset; --only-enforce websocket_stream.stream_roundtrip.
- Standing: /root/projects/cadr/.orchestrate/goal26/preferences.md

ACCEPTANCE:
- Friend-MachineD remesure after invent: ratio ≤1.0× → disposition met-parity or met-beat + product keep patch
- If invent exhausts above 1.0×: leave open-parity with decision log; optional gates.md proposal for accepted-runtime-gap (do not silent-freeze)
- /tmp/g26-h-websocket-REPORT.md + /tmp/g26-h-websocket-decisions.tsv + patches for parent

VERIFY: unset GOAL20_PART_O_SLICE GOAL20_FLOOR_SLICE; remesure; print ratio from summary

TIMEBOX: 180 minutes

FORBIDDEN: no gt/rebase/force-push; no mock-only fake parity; no leftover win; no Goal 20–25 rewrite; no RATIO_CEILINGS+speedup same commit

REPORT: status, ratios, patches, deviations, follow-ups

STANDING: read preferences.md verbatim and obey
