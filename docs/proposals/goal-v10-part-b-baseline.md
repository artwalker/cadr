# Goal 10 Part B baseline adjudication proposal

Status: **The user has adjudicated: Part B is suspended waiting for `v0.84.0`; execute the zero-dependency Part C first.**

## 0. User adjudication (2026-08-01)

This document preserves the facts and options as they stood when it was first
blocked; the adjudication below supersedes the execution recommendations of
sections 4 and 5:

1. Do not lock `v0.83.0`: it regresses 38 commits behind the current baseline,
   which does not meet the goal of tracking the newest.
2. Do not make an exception and lock `origin/main@4488ad55c`: upstream is
   continuously refactoring the session storage layer and the server protocol, and
   an in-development commit is not taken as the new baseline.
3. The order is adjusted to `Part C → Part B (waiting for v0.84.0) → Part D → Part E`.
   Part C depends only on the accepted Part A repository and the Goal 9 Part D
   `verify.sh`; the existing constraint "Part B must come before Part D" remains
   unchanged.
4. If `v0.84.0` still has not been released once Part C is finished, pause and
   report; the lock must not be changed to HEAD on one's own initiative.
5. The minimal cryptographic surface listed in section 3 is pre-authorized: the
   bearer-token digest must reuse the pure-Lisp `sha256-bytes` at
   `src/cadr-ai/oauth.lisp:63`; the fixed-length byte comparison uses a loop that
   does not exit early, and introduces no new algorithm or dependency. Tests must
   cover the correct token, a wrong token, differing lengths, concurrent
   handshakes, logs/errors not leaking the token, and a fixed vector for the socket
   suffix. If a new cryptographic dependency is needed, or the file scope listed in
   the proposal is exceeded, become blocked again.

## 1. The exact conflict

Goal 10 requires all of the following at the same time:

1. the baseline locks the latest stable release tag at execution time, and does not
   lock the tip of a development branch;
2. continue tracking the newest from the Goal 9 baseline
   `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`;
3. fill in the named increments: client, composable server, fullscreen transcript,
   scrollbar, UI mode, and so on.

The authoritative remote state on 2026-08-01 makes the three impossible to hold at
once. The GitHub Latest release is still `v0.83.0`, its tag commit is
`845d6ff1f6643aba440341cce877ce1c43ebbc39`, released at
`2026-07-29T22:30:33Z`. The current canonical baseline is already 38 commits after
that tag; upstream `origin/main` is `4488ad55c18f07ae89a489096c90de8667b3adfb`,
which is a further 99 commits after the current baseline and 137 commits after the
tag.

So locking `v0.83.0` is not "tracking the newest"; it regresses the accepted
baseline by 38 commits, and the capabilities Goal 10 names are not in that release
either. Section 1.1 of goal-v10 already pre-adjudicated this: when the gap between
tag and HEAD is too large and the target capabilities exist only at HEAD, it must
become blocked, and the lock must not be changed to HEAD on one's own initiative.

Authoritative re-check:

```text
GitHub Latest: v0.83.0
tag hash:       845d6ff1f6643aba440341cce877ce1c43ebbc39
current base:   74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
upstream HEAD:  4488ad55c18f07ae89a489096c90de8667b3adfb
v0.83.0..current: 38 commits
current..HEAD:    99 commits
v0.83.0..HEAD:   137 commits
```

GitHub Release: `https://github.com/earendil-works/pi/releases/tag/v0.83.0`.

## 2. Size of the HEAD increment and its behavioral surface

| Range | commits | files | diff |
|---|---:|---:|---:|
| `v0.83.0..74caa2649` | 38 | 122 | `+7042/-1089` |
| `74caa2649..origin/main` | 99 | 200 | `+15724/-2627` |
| `v0.83.0..origin/main` | 137 | 287 | `+22556/-3506` |

The test denominator grows from the current baseline's 363 package `*.test.ts`
files to 385 at HEAD; `74caa2649..HEAD` has 51 affected test files (23 added, 27
modified, 1 deleted). The additions are distributed as agent 1, AI 1, client 6,
coding-agent 6, server 7, TUI 2. Top-level packages grow from 8 to 9, with
`packages/client` added.

An audit of the actual diff gives the main behavioral surfaces as:

- transport-neutral client, Unix socket, request correlation, session lease,
  backpressure;
- composable protocol server, token handshake, snapshot/progress, session
  attachment, socket permissions and safe cleanup of stale inodes;
- tightening of protocol v2 fields/discriminated unions;
- repository/store/search, reader/fork, per-session queue, JSONL/SQLite/FTS5
  session-storage refactor;
- fullscreen transcript, nested ScrollView, transient/draggable scrollbar, wheel
  routing, Kitty crop, spaces in settings search;
- coding-agent UI mode, remote session controller, auth reload lock, Wayland
  clipboard;
- Fireworks Kimi K3 reasoning, per-account isolation of the Codex WebSocket,
  Google/Anthropic stream corrections.

No new external direct npm dependency was added; the added manifest edges are only
the internal client/protocol, and `brace-expansion` is a patch upgrade of an
existing dependency. `wl-paste` is an optional runtime command and does not
constitute a new package dependency, but at implementation time it must enter the
divergence/runtime-environment documentation.

## 3. Separate cryptographic adjudication

If the user adjudicates that HEAD is to be tracked, the composable server still
cannot be built directly:

- `origin/main:packages/server/src/server.ts:34-35` takes a SHA-256 digest of the
  bearer token;
- the same file at `:257-258` uses `timingSafeEqual` to compare the client token
  digest;
- `packages/server/src/transports/unix/listener.ts:307-309` additionally uses
  SHA-256 to generate the 8-hex suffix of the owned socket path.

The existing authorization covers PKCE, AWS HMAC-SHA256, and the RS256/OpenSSL
path; it does not automatically authorize a new server bearer-token
digest/constant-time compare. Under Goal 10 blocked category `(b)`, this must be
adjudicated separately. The minimal Lisp path is to add no dependency, reuse the
existing SHA-256 primitive, and add a fixed-length byte-vector constant-time
compare; tests must lock the correct token, a wrong token, inputs of differing
lengths, concurrent handshakes, logs/errors not leaking the token, and a fixed
vector for the socket suffix. If the implementation needs to expand to a new
cryptographic dependency or other files, become blocked again.

## 4. Routes and trade-offs

### Route 1: wait for `v0.84.0` (recommended for approval)

Keeps the "only lock a stable release tag" adjudication and the scope Goal 10 names
unchanged. After upstream releases, query GitHub Latest again, record the actual
tag/hash, and then do a complete incremental audit from `74caa2649`. The advantage
is a baseline that is stable, communicable, and does not regress; the cost is that
Part B/C/D/E cannot continue before the release appears.

The cryptography must still be approved item by item when the new release actually
contains the composable server; it must not obtain authorization automatically
because a release was waited for.

### Route 2: make a one-time exception and lock `origin/main@4488ad55c`, and authorize the minimal cryptographic surface

Obtains the capabilities Goal 10 names immediately, but explicitly revokes this
goal's "only lock a release tag" rule once; HEAD is a development snapshot, and
upstream may still keep changing during the 99-commit port. If approved, the
baseline is fixed at the commit hash above rather than a floating `main`, and the
section 3 token digest/constant-time compare and socket suffix SHA-256 must be
explicitly approved at the same time; otherwise it stays blocked.

### Route 3: lock `v0.83.0` (rejected)

Formally satisfies "the latest stable tag", but in substance regresses 38 commits,
loses 11 accepted test files and the Goal 9 increment, and cannot realize the
capabilities this goal names. It violates the "do not shrink scope" and "track the
newest" goals, and should not be chosen.

## 5. Request for item-by-item user adjudication

1. Baseline: approve Route 1, waiting for `v0.84.0`, or Route 2, an exceptional lock
   on the current HEAD?
2. If Route 2 is approved: is the minimal cryptographic implementation surface of
   section 3 approved?
3. If waiting is chosen: after `v0.84.0` is released, the actual
   tag/hash/dependency/cryptography diff must be re-resolved; the figures in this
   document serve only as evidence for this blockage, and do not pre-authorize
   unknown changes in a future release.

Before the adjudications above, Part B does not create an old-tag checkout and does
not rewrite fixtures/parity; because the Part order is fixed, Part C must not be
implemented ahead of time either.
