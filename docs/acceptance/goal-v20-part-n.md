# Goal 20 Part N — status

Date: 2026-08-13. Partial landing with L/M.

| Mechanism | Status |
|---|---|
| N0 introspect ledger locations | not started (Part F subset) |
| N1 MOP slot enum for providers | done: `provider-definition-compared-slots` |
| N2 load-and-probe | used for xAI classifier |
| N2.5 slynk | same query as load-and-probe; lock is FiveAM not a pasted snapshot |
| N2.6 compile WARNING gate | `scripts/cadr-compile-warnings.py`; `release.lisp` toplevel fix |
| N2.7 sb-cover | done: `docs/acceptance/goal-v20-sb-cover.md`; driver `scripts/goal20-cover.sh`; trace runbook in `docs/profiling.md` |
| N2.8 types | deferred to K |
| N2.9 sb-sprof | deferred to H |

`release.lisp` no longer wraps `defparameter` in `multiple-value-bind`.
