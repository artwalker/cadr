# Goal 9 live-test gate placement proposal

Status: **Items 1–3 have been approved by the user one by one; the test entry
points and the complete summary were implemented in `e779ee828`. Part D's
`verify.sh` lands in the already-fixed Part D under the approved rules.**

Fixed baseline: `earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`,
checkout `/tmp/cadr-parity-74caa2649`. Every baseline `file:line` in this
document refers to that commit.

## 1. Problem and boundaries

After the OAuth order-dependency fix, the OAuth live gate passed in all three
consecutive reruns by the advisor, but the full results were:

| run | known checks | known fail | conclusion |
|---:|---:|---:|---|
| 1 | 6436 | 5 | DeepSeek self-extension live failed; ASDF did not continue to the protocol suite |
| 2 | 6933 | 0 | passed |
| 3 | 6933 | 0 | passed |

The advisor did not give the per-round pass/skip numbers for the three rounds in
the adjudication input, and this document does not reverse-engineer them and
pass them off as raw output. This set of three rounds can only prove that real
model behavior varies; it cannot serve as evidence of deterministic
repeatability.

This proposal adjudicates only the organization, the exit semantics and the
acceptance location of the live tests. It does not modify:

1. the production implementation of providers, the agent, extensions or tools;
2. the prompts, assertions, models, temperature, retry or tool surface of the
   live tests;
3. the credential storage, refresh and isolation mechanisms;
4. the availability-gate semantics when there is no credential;
5. any third-party dependency.

## 2. What baseline pi actually does

### 2.1 The live blocks sit in the ordinary Vitest suite

The baseline root `test` runs the `test` of every workspace:
`package.json:33-34`. The entry point of `packages/ai` is a plain `vitest --run`:
`packages/ai/package.json:59`.

The real provider blocks use `describe.skipIf(!KEY)`. For example DeepSeek is at
`packages/ai/test/stream.test.ts:448-472`; when a credential is present, five
real calls enter the ordinary suite, and one of them declares `{ retry: 3 }`.
The coding-agent's real session-branching test likewise sits in the ordinary
suite and is gated by `describe.skipIf(!API_KEY)`:
`packages/coding-agent/test/agent-session-branching.test.ts:27-55`.

The baseline's run semantics are therefore:

- no credential: the corresponding live block skips;
- credential present and the final assertion fails: Vitest returns non-zero and
  the enclosing `npm test` fails;
- `skipIf` only solves availability; it does not turn a real LLM into a
  deterministic test.

### 2.2 The official CI does not actually run provider live

The baseline PR/push CI runs install, build, check and `npm test` at
`.github/workflows/ci.yml:32-42`, but the workflow injects no provider key and
no `auth.json`. The release workflow also runs `npm test` at
`.github/workflows/build-binaries.yml:253-263`, likewise without provider
credentials.

Verification command:

```text
rg -n 'ANTHROPIC_API_KEY|OPENAI_API_KEY|DEEPSEEK_API_KEY|OPENAI_CODEX|PI_AUTH_JSON' \
  .github/workflows/ci.yml .github/workflows/build-binaries.yml
(no output; exit 1)
```

The conclusion must be stated in two layers: a baseline live failure does block
in a **local `npm test` that has credentials**; but in the **official
CI/release test job** at the fixed commit there are no credentials, all the live
blocks skip, and therefore they do not block the official CI. "They are written
in the ordinary suite" must not be used to derive "the official CI has actually
verified live".

## 3. The current problem in Cadr

Currently `scripts/test-cl.sh:19-26` runs eight ASDF test systems in sequence.
The networked live files are mixed into the ordinary systems:

| system | live file | current consequence |
|---|---|---|
| `cadr-ai/tests` | `test/cadr-ai/live-provider-test.lisp` | provider variation can terminate the whole run at the first system |
| `cadr-cli/tests` | `test/cadr-cli/live-test.lisp` | CLI/OAuth variation prevents storage/server/evals/protocol |
| `cadr-evals/tests` | `test/cadr-evals/live-evals-test.lisp` | agent-behavior variation prevents protocol |

Although the name of `test/cadr-cli/live-auth-test.lisp` contains `live`, it
uses only a temporary auth store and network stubs; it is a deterministic
regression and must remain in the ordinary suite.

This organization is stricter than the baseline's official CI: DeepSeek and
Codex OAuth credentials are permanently present on this machine, so
`test-cl.sh` executes live every time; one failing behavioral LLM smoke then
leaves the subsequent deterministic suites without a result. The "full checks"
figure itself therefore varies with model output, and cannot serve as a stable
engineering gate.

## 4. User adjudication

### 4.1 Adjudication one: separate the deterministic and live entry points

The user approved, and it has been implemented:

1. `./scripts/test-cl.sh` only runs the offline deterministic FiveAM suites; the
   networked provider live files move out of the three ordinary ASDF test
   systems into separate live systems;
2. a single new entry point `./scripts/test-live.sh` orchestrates only the
   credential-gated FiveAM live systems, and does not duplicate assertions or
   parse model text in the shell;
3. `live-auth-test.lisp` stays in the deterministic CLI suite;
4. with no credential it still skips item by item and prints the reason,
   semantically isomorphic to the baseline's `skipIf(!KEY)`.

This is a test entry-point mechanism added relative to the fixed baseline, and
it is registered in the README difference list. The official baseline CI already
separates deterministic CI from live in fact by "not supplying credentials";
Cadr merely turns that implicit boundary into an auditable explicit entry point.

### 4.2 Adjudication two: the blocking scope of a live failure

The user approved, and the following two-layer semantics have been implemented:

- a live failure must not change the result of `test-cl.sh`, and must not
  prevent deterministic suites that have not yet run;
- `test-live.sh` must finish running every enabled provider/surface before
  summarizing, and if any enabled item fails the final exit is `1`; the
  remaining live results must not be lost when the first package fails;
- a failure must not be automatically turned into a skip/warning, and must not
  be automatically rerun over and over until it goes green;
- a given live failure can only be explicitly adjudicated by the user as "accept
  the external variation" or "product blocker"; it must not be overwritten by a
  later green run.
- the summary lists item by item the items run, the items skipped and the
  reason, and the failed items with their complete failure output; every failure
  must additionally be labelled `suspected product defect`, `suspected model-output variance` or
  `cannot determine`, together with the grounds for the judgement.

The dedicated live command keeps a real non-zero signal, and runs all eight
items before its final exit, so that the separation does not degenerate into
hiding red lights.

### 4.3 Adjudication three: Goal 9 Part D and the pre-release gate

The user approved: Part D's `scripts/verify.sh` executes in the following fixed
stages and reports them separately:

```text
deterministic FiveAM -> isolated build -> deterministic process/PTY smoke
                     -> credential-gated live FiveAM -> live TUI smoke
```

Rules:

1. the first three stages are repeatable hard gates;
2. the DeepSeek and Codex OAuth registered as available on this machine must
   actually execute and must not be skipped; other providers continue to skip on
   availability;
3. when the live stage fails, `verify.sh` finally exits `1`, but it must first
   collect all the live results; the release is blocked by default unless the
   user explicitly accepts that particular complete report;
4. the release report lists both the deterministic and the live table, and
   merging them into a single "all green" figure is forbidden;
5. when CI has no credential it proves only the deterministic gate, isomorphic
   to the baseline's official CI; the README/report must state the live coverage
   that the local `verify.sh` has over and above CI.

Lifting the release block can only be done by the user's explicit confirmation
after seeing the complete live report; the script must not judge any failure
ignorable on its own. That wiring is still left to Part D per the fixed scope,
and no half-finished `verify.sh` is created early this time.

### 4.4 Established rules: evidence language and numeric discipline

The user has already established the following permanent rules directly this
round, without waiting for this proposal to be approved:

1. "N green runs in a row" may only describe a deterministic entry point that
   contains no real network/LLM call;
2. `checks / pass / skip / fail` must be listed for every single run; if any one
   number is missing, the run may only be marked as an "incomplete record", and
   must not be back-computed and then passed off as raw output;
3. multi-round live results are written as "N runs in total: X pass / Y fail /
   Z skip", with the complete numbers listed for every round; any fail must be
   kept, and a later pass must not overwrite it;
4. a combined `verify.sh` that includes live may only declare "the per-stage
   results", and must not serve as deterministic evidence;
5. the provider/model, the credential-gate state, the run time and the failure
   surface must be recorded, but writing credentials, tokens, complete sensitive
   responses or the user's auth contents is forbidden.

This directly revokes the earlier incorrect basis that called the five-run
streak containing live a deterministic all-green.

## 5. Actual implementation and unfreezing scope

Only tests and documentation were actually modified:

```text
cadr-ai.asd
cadr-cli.asd
cadr-evals.asd
cadr-live-tests.asd                # new aggregate live system
scripts/test-live.sh                 # new
test/cadr-live-support.lisp
test/cadr-live/{package,runner}.lisp # new
test/cadr-ai/live-provider-test.lisp
test/cadr-cli/live-test.lisp
test/cadr-evals/live-evals-test.lisp
test/*/live-package.lisp             # new dedicated FiveAM suites
test/cadr-cli/live-gate-test.lisp    # deterministic runner/report regression
docs/test-matrix.md
docs/architecture.md
docs/open-questions.md
docs/proposals/goal-v9-live-test-gating.md
README.md
docs/acceptance/goal-v9-part-b.md
scripts/verify.sh                    # implemented only in the established Part D
```

All of `src/` is frozen; no third-party dependency is added. If the
implementation requires modifying any production file, changing a live
assertion, or introducing automatic fault tolerance/retry, it goes back to
blocked immediately.

## 6. Options considered and rejected

| Option | Reason for rejection |
|---|---|
| Keep the status quo and record the sporadic failures as flaky | LLM behavior variation is not a timing bug; the subsequent deterministic suites are still truncated |
| Retry until green and only then count it as passing | Hides the failure rate and keeps manufacturing the illusion of "all green" |
| Relax the self-extension assertions | Would weaken live coverage, and this proposal has no authority to change test semantics |
| Make a live failure only a warning and always exit 0 | The red light is marginalized, and no real constraint can form before release |
| Delete the behavioral live tests from the repository | Loses the real agent/tool/extension closed-loop evidence |
| Inject real credentials in CI only | The baseline CI does not do this; token rotation, cost and external variation would contaminate the deterministic CI |
| Keep merging the live and the deterministic figures | checks would change with where the run aborts, making coverage regressions incomparable |

## 7. Implementation acceptance

`./scripts/test-cl.sh` gives completely identical results five times in a row:

| run | checks | pass | skip | fail |
|---:|---:|---:|---:|---:|
| 1 | 6921 | 6921 | 0 | 0 |
| 2 | 6921 | 6921 | 0 | 0 |
| 3 | 6921 | 6921 | 0 | 0 |
| 4 | 6921 | 6921 | 0 | 0 |
| 5 | 6921 | 6921 | 0 | 0 |

After `./scripts/test-live.sh` runs all eight items in full, the result is
`32 checks / 31 pass / 1 skip / 0 fail`. Seven items actually executed: DeepSeek
provider stream, DeepSeek print, OpenAI Codex OAuth CLI, DeepSeek/Codex eval,
DeepSeek self-extension, DeepSeek repository repair; Anthropic multi-turn
explicitly skipped because `ANTHROPIC_API_KEY is not set`. There was no failed
item, so this round has no failure output and no nature judgement; the
summarizer's failure output, its three judgement classes, its not truncating
midway and its non-zero exit are locked by deterministic regressions.

These five rounds prove only the deterministic gate; the single live result is
ledgered separately and is not merged into "the full run is all green".
