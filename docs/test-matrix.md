# Gate denominators (Goal 20 Part M)

<!-- GOAL20_TEST_CHECKS systems=9 checks=17157 pass=17157 skip=0 fail=0 -->

Date: 2026-08-13. Recount: read this file against `scripts/verify.sh`.
`scripts/test-cl.sh` rewrites the `GOAL20_TEST_CHECKS` comment after a green
nine-system run and fails when the committed count drifted. Do not edit it
by hand.

Each deterministic `verify.sh` stage must answer three questions. "N/N"
without that answer is an undeclared denominator.

| Gate | Checks | Does not check | A pass means | Rest covered by |
|---|---|---|---|---|
| `test-cl.sh` (Nine-system FiveAM) | Isolated HOME, all packaged FiveAM files | Live provider I/O; render-diff screens; compile WARNING count | Every assertion in those suites held this run | render-diff, live stages, cadr-compile-warnings |
| `write-test-check-anchor.py` | `GOAL20_TEST_CHECKS` equals this run's systems/checks/pass/skip/fail | Whether those assertions are the *right* assertions | The committed FiveAM total is this run's total | Adding tests without committing the comment |
| `check-code-organization.py` | File placement vs exemptions | Behaviour; Lisp-ification status | Listed files sit where the manifest says | source-parity, Part I |
| `check-product-identity.py` | Token allowlist | Runtime strings not in the allowlist scan | No unallowlisted product-token in scanned files | baseline-string-reachability |
| `render-diff.py gate --tier core` | Semantic-screen SHA pairs + I01/I04 adjudications for core scenarios | Full-tier scenarios; whether a green pair is the *right* picture | Every core checkpoint is aligned or has a live disposition | full-tier gate; Part L reverse scan |
| `tool-result-diff.py` | Tool-result byte contract vs baseline | TUI chrome around those results | Listed tool results match after normalize | render-diff |
| `event-diff.py` | Session event stream vs baseline | TUI | Listed events match | render-diff |
| `goal11-performance-gate.py` | Absolute ceilings + 3 pi ratios | Self-history (Part A, not enabled); non-TUI packages | No ceiling breach; ratios hold on same-machine | Part A/H once enabled |
| `baseline-string-reachability.py` | Named baseline literals have a cadr producer | cadr-only leaks; "is this the right picture" | Each listed literal is live in the named file | cadr-visible-output-origin |
| `cadr-visible-output-origin.py` | Unformatted Lisp tokens on cadr screens | Baseline-string presence | No NIL / `#<` / `#S(` on scanned cadr screens | FiveAM goal20-l-custom-entry-* |
| `cadr-compile-warnings.py` | cadr-owned compile WARNING == 0; unallowlisted muffle | STYLE-WARNING fail-closed; notes; third-party | No new cadr WARNING | STYLE-WARNING ledger (count only) |
| provider slot enum (FiveAM) | Every `provider-definition` slot compared or uniquely excluded; `default-model` compared; xAI is `grok-4.5` | Login *control flow* | Table fields are complete | `classify-post-login-model` FiveAM |

provider-matrix after N1: compared slots come from `sb-mop:class-slots`. Exclusion count is 1 (`baseline-source`). Compared count is the rest. Exclusion count is not allowed to exceed compared count.

`baseline-visible-strings` 672/672 remains **drive completeness of the pi construction suite**, not cadr consistency. Declared here so that number cannot be cited as cadr parity.
