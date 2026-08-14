# Goal 16 Part B: the product identity convergence proposal

Status: **Adjudicated item by item and implemented.** The fixed implementation
baseline is `3dbb58b895a1f732d6354233e91d6981b0a35c09`, and the Part A audit
commit is `dcba371ff`. All six items have been adjudicated item by item by the
user, and for B1 the overriding adjudication of 2026-08-05 governs; the fact
list is in
`docs/identity-audit.md`.

## 1. Boundary and invariants

This proposal handles only the product identity, upstream endpoint defaults and
the old environment variable namespace. The following invariants hold across
every implementation batch:

1. `origin=git@github.com:badlogic/pi-mono.git` is not changed; the canonical
   Cadr remote remains `backup=https://github.com/artwalker/cadr.git`.
2. The provider payload, session entries, tool results, the JSON/RPC wire, the
   default models, the default tools, the security model and the extension API
   are not changed.
3. No third-party dependency, network service, compatibility layer or telemetry
   is added.
4. Radius's registered client, API paths, wire/storage fields and protocol
   names are not renamed just because their strings contain `pi`.
5. Every value is first locked by an independent contract test, and only then
   is the production implementation changed; each batch is committed
   independently, verified in full independently, and can be rolled back
   independently.

## 2. Third-party attribution values already pre-adjudicated

These six groups of values were approved by the user in the Goal 16
specification; Part C implements them directly, and no repeated adjudication is
required:

| Contract | Current value | Target value | Baseline location | Minimal Cadr file surface |
|---|---|---|---|---|
| Version-check User-Agent | `pi/<version> (...)` | `cadr/<version> (...)` | Cadr residue, no need to keep it | `src/cadr-cli/support/resume-version-git.lisp` and its tests |
| OpenRouter attribution | `https://pi.dev` / `pi` | `https://github.com/artwalker/cadr` / `cadr` | The client attribution semantics of `packages/ai/src/providers/openrouter.ts` | `src/cadr-cli/support/headers.lisp` and its tests |
| NVIDIA billing origin | `Pi` | `cadr` | Provider-specific attribution field | Same as above |
| Cloudflare User-Agent | `pi-coding-agent` | `cadr-coding-agent` | Provider-specific client identifier | Same as above |
| OpenCode client | `pi` | `cadr` | Provider-specific client identifier | Same as above |
| xAI device-code referrer | `pi` | `cadr` | The device-code request of `packages/ai/src/auth/oauth/xai.ts` | `src/cadr-ai/oauth/providers/xai.lisp`, `test/cadr-ai/goal12-auth-test.lisp`, the live OAuth gate |

xAI's `client_id`, scope and token endpoint are all unchanged. Part C must
issue one real device authorization request; if the server rejects it because
of the referrer, stop that batch immediately, roll back the single value, and
re-adjudicate `referrer=pi` into an evidenced `retained under functional
constraint`; declaring success on the strength of a fixture is not allowed.

## 3. Decision B1: `/share` uses the Cadr viewer by default

### 3.1 The exact requirement and the facts

`src/cadr-cli/support/changelog-share.lisp:262-323` first hands the complete
session HTML to `gh gist create --public=false`, then splices the gist ID into
the viewer URL. The current default viewer is `https://pi.dev/session/`; that
is, storage is in a GitHub Gist, but reading and presenting the session depends
on upstream viewer code. This is a user-data egress boundary, not an ordinary
brand string.

### 3.2 Final adjudication (2026-08-05, overriding every earlier statement)

`/share` stays enabled by default, and the default viewer is fixed at
`https://cadr.dev/session/`; a non-empty `CADR_SHARE_VIEWER_URL` and an
explicit caller-supplied `viewer-base-url` override the default value in that
order. The viewer URL is held, together with the product slug, the display name
and the canonical repository URL, by the product identity constant group in
`src/cadr-ai/support/release.lisp`.

The successful-share output must display the viewer URL as well, so that the
user is clear about where the link points. The user has accepted with full
knowledge: before the cadr.dev page goes live, the command will create a Gist
and return a viewer link that is temporarily unreachable; once the page is
live, no change to Cadr is needed. This transitional period must not be used as
a reason to disable it by default, to fall back to pi.dev, or to add a
fallback.

### 3.3 Minimal implementation surface

- `src/cadr-cli/support/changelog-share.lisp`
- `test/cadr-cli/goal9-a2-workflows-test.lisp` and the tests where the existing
  share contracts live
- `README.md`, `CHANGELOG.md`

This batch does not implement the viewer page; once `cadr.dev` is live, all
that is needed is to deploy a compatible static page, and the share flow is not
rewritten.

### 3.4 Alternatives and the grounds for rejecting them

- **Keep the pi.dev default**: functionally continuous, but it keeps handing
  Cadr sessions to an upstream viewer that is not under this project's control,
  and neither the identity nor the trust boundary is closed; rejected.
- **Disabled by default**: the user explicitly requires `/share` to keep
  producing Cadr links; rejected.
- **Fall back to pi.dev because the page is not live yet**: it keeps handing
  Cadr sessions to the upstream viewer and usurps the upstream identity;
  rejected.
- **Change it to just the GitHub Gist URL**: it changes the baseline
  interaction, and a raw Gist is not a session viewer; rejected.

### 3.5 Rollback

This batch only needs the default viewer constant rolled back; the explicit
`CADR_SHARE_VIEWER_URL` path and the generated HTML are both unaffected.

## 4. Decision B2: the version check is disabled by default, with the Cadr endpoint configured explicitly

### 4.1 The exact requirement and the facts

`src/cadr-cli/sdk/cache-version.lisp:272-413` does a fixed GET to
`https://pi.dev/api/latest-version`, then compares upstream `0.83.x` against
Cadr `0.2.0`. The network request itself carries no session data, but the
objects compared are not the same product, so the result is necessarily wrong
semantically.

### 4.2 Proposed adjudication

Add one and only one configuration item, `CADR_VERSION_CHECK_URL`:

- unset or empty: the automatic version check is off and no network request is
  made;
- non-empty: query that URL, continuing to reuse the existing timeout, JSON
  normalization, version comparison and silent-network-failure semantics;
- when `CADR_OFFLINE` or `CADR_SKIP_VERSION_CHECK` is non-empty, no request is
  made even if the URL is configured;
- the internal Lisp functions are renamed to `get-latest-cadr-release`,
  `get-latest-cadr-version`, `check-for-new-cadr-version` and
  `normalize-latest-cadr-release`; no alias for the old symbols is kept.

`version.sexp` remains the single source for the current version. When
`cadr.dev` goes live in future, all that is needed is to provide a
contract-compatible endpoint and to decide whether to give it a default value.

### 4.3 Minimal implementation surface

- `src/cadr-cli/sdk/cache-version.lisp`
- `src/cadr-cli/support/resume-version-git.lisp`
- `src/cadr-cli/package.lisp`
- the existing version/cache tests, `README.md`, `CHANGELOG.md`

### 4.4 Alternatives and the grounds for rejecting them

- **Keep querying pi.dev**: it would misreport an upstream release as a Cadr
  update; rejected.
- **Hard-code cadr.dev immediately**: the target is not available yet, and cold
  start would produce a meaningless request; rejected.
- **Delete the version check**: the baseline capability still has to be
  restored in future, and deleting it would turn a temporary lack of service
  into permanent crippling; rejected.
- **Keep the `*-pi-*` aliases**: this is an identity error in the
  internal/Lisp API at the 0.2 stage, and the project's rules do not keep
  compatibility by default; an alias would make the identity gate exempt the
  old names permanently; rejected.

### 4.5 Rollback

Rolling back this batch restores the old endpoint; it changes neither the local
configuration files nor the session format.

## 5. Decision B3: hard-cut the 14 `PI_*` environment variables to `CADR_*`

### 5.1 Proposed adjudication

**No compatibility period, no reading of the old names, no deprecation warning
printed.** The exact mapping is as follows:

| Old name | New name |
|---|---|
| `PI_CACHE_RETENTION` | `CADR_CACHE_RETENTION` |
| `PI_CONFIG_DIR` | `CADR_CONFIG_DIR` |
| `PI_EVAL_ARTIFACT_DIR` | `CADR_EVAL_ARTIFACT_DIR` |
| `PI_EXPERIMENTAL` | `CADR_EXPERIMENTAL` |
| `PI_MODEL` | `CADR_EVAL_MODEL` |
| `PI_OFFLINE` | `CADR_OFFLINE` |
| `PI_PROVIDER` | `CADR_EVAL_PROVIDER` |
| `PI_RADIUS_SERVER_URL` | `CADR_RADIUS_SERVER_URL` |
| `PI_RADIUS_URL` | `CADR_RADIUS_URL` |
| `PI_SERVER_CADR_PATH` | `CADR_SERVER_CADR_PATH` |
| `PI_SERVER_DIR` | `CADR_SERVER_DIR` |
| `PI_SHARE_VIEWER_URL` | `CADR_SHARE_VIEWER_URL` |
| `PI_SKIP_VERSION_CHECK` | `CADR_SKIP_VERSION_CHECK` |
| `PI_TIMING` | `CADR_TIMING` |

The impact is that local shell/service configurations using these old names
must be migrated in one go. The grounds: the project already removed the
`PI_CL_*` transitional compatibility in 0.2.0, and the README explicitly calls
that migration the only namespace break; adding a silent alias again would
restore a second decision source, contradicting this goal's single-source
objective. A deprecation warning is likewise a new mechanism the baseline does
not have, which both creates an extra output channel and cannot eliminate the
old names, so it is not introduced.

### 5.2 Minimal implementation surface

- `src/cadr-ai/providers/bedrock.lisp`
- `src/cadr-cli/tool-manager.lisp`, `src/cadr-cli/support/html.lisp`,
  `src/cadr-cli/support/timings.lisp`, `src/cadr-cli/sdk/cache-version.lisp`
- `src/cadr-evals/harness.lisp`, `src/cadr-evals/reporter.lisp`
- `src/cadr-server/config.lisp`, `src/cadr-server/radius.lisp`,
  `src/cadr-server/rpc-process.lisp`
- the corresponding tests, the build/process harness, `README.md`,
  `CHANGELOG.md`

The `PI_OFFLINE` that `scripts/render-diff.py` sets and clears for the fixed
TypeScript baseline, and the `PI_CODING_AGENT_DIR` of
`scripts/goal11-cold-start.py`, which points at the baseline checkout, are not
in the migration surface and are kept.

### 5.3 Alternatives and the grounds for rejecting them

- **Cadr first, PI as fallback**: it keeps letting the old identity govern
  runtime behavior, and the identity gate cannot fail closed; rejected.
- **A one-release warning period**: the project has no promised `PI_*` Cadr
  public contract, and it would add a warning mechanism that does not exist in
  the baseline; rejected.
- **Rewrite shell/service configurations automatically**: it steps outside the
  repository's control surface and may break the user's environment; rejected.

### 5.4 Rollback

Each system can be rolled back independently, batch by batch; the migration
only reads the environment and writes no user file, so there is no data
rollback.

## 6. Decision B4: replace the remaining free identity values as one group

The proposal is to approve as one group the free values newly found by Part A
and those named by the specification; these involve neither authentication nor
an external schema:

| Current value | Target value | Location / impact |
|---|---|---|
| `/changelog`'s `earendil-works/pi` | `https://github.com/artwalker/cadr` | `src/cadr-cli/support/changelog-share.lisp:135-161`; a link in the user's browser, `origin` untouched |
| `pi-wsl-clip-` | `cadr-wsl-clip-` | `src/cadr-cli/interactive/clipboard.lisp:323-329`; temporary file name |
| The notify example's title `Pi` | `Cadr` | `examples/extensions/notify.lisp:28`; desktop notification |
| localStorage `pi-share:v1:sidebar-width` | `cadr-share:v1:sidebar-width` | `src/cadr-agent/export-html/template.js:1666`; the browser preference resets once |
| synthetic tool call ID `pi_tool_load_` | `cadr_tool_load_` | `src/cadr-ai/providers/openai.lisp:201-207`; provider/session ID, the algorithm and the payload unchanged |
| `Radius Pi` / `cadr-radius-pi-` | `Radius instance` / `cadr-radius-instance-` | `src/cadr-server/radius.lisp:468,553,568,579,627`; log and thread names, the remote fields unchanged |

The exported HTML's `pi-url-params` and `pi-share-base-url` are not replaced
directly in this group: the final B1 adjudication changes only the viewer URL,
these two meta names are still the existing browser-integration contract, and
they stay in the allowlist exactly; when the viewer contract is upgraded in
future, both ends migrate atomically, so that changing only one end cannot
cause a silent failure.

The minimal file surface is limited to the production files the Part A table
points at, the corresponding existing tests, and README/CHANGELOG. No new
third-party asset, endpoint or protocol field falls within the authorization.

The alternative "change only the values the user can see" is rejected: session
IDs, temporary files and thread names are uncommon, but they still enter the
log/persistence/debug surface; keeping them would go on producing a
half-changed state. The whole group can be rolled back by one free-identity
batch commit, and existing session IDs are not migrated.

## 7. Decision B5: the functional-contract and provenance allowlist

The proposal is to confirm the following retentions one by one; they are not
"missed changes":

| Retained value | Grounds | Conditions for lifting it in future |
|---|---|---|
| Radius `pi-gateway` | The 2026-08-04 live discovery returned the same `clientId` and scope | Radius registers a Cadr client |
| `radius.pi.dev` | A real Radius provider/presence endpoint; both the root and discovery return HTTP 200 | Radius formally changes domain |
| Radius `/pis/*`, `radiusPiId` | The remote API, and the existing storage/RPC schema | The server side and the migration plan are upgraded together |
| `pi-messages` | The name of the Radius wire dialect | The protocol is formally renamed and there is a compatible migration |
| The package.json manifest key `pi` | The baseline extension ecosystem's schema | The ecosystem publishes a new schema and migrates |
| The `@earendil-works/pi-coding-agent` detector | The eval specifically identifies legacy TS extension output | That eval objective is cancelled |
| The generated `pi-ai` provenance | The fixed catalog's source | It is regenerated and the source changes |
| `aligned with pi ...` | The release alignment declaration | The project no longer releases against that baseline |
| Historical announcements, the selector's provenance docstring | Real history / internal provenance | The corresponding historical component or the provenance requirement is deleted |
| The pi in the render diff, the payload export and the baseline scripts | Fixed reference input | The baseline project is replaced |
| The pi in docs/tests/fixtures explicitly marked as baseline/migration | Audit and cross-implementation-comparison evidence | The corresponding evidence is retired |

The allowlist must be registered by exact path, line contract or fixed string;
directory-level passes are forbidden.

## 8. Decision B6: the single source and the implementation batches

### 8.1 The single source

Reuse `src/cadr-ai/support/release.lisp`; do not create a new `cadr-core`
product policy layer. The architecture already states that the latter carries
only failure-safety primitives with no product semantics. The release module
adds private constants for the product slug, the display name and the canonical
repository URL, and the attribution values derived from them; `cadr-cli`/server
keep reading from `cadr-ai` exactly as they read `cadr-release-identity` today.
**No public export is added**, so that internal brand constants are not
expanded into a stable Lisp API.

Environment variable names and configurable endpoints are held by each feature
owner, but the tests must assert that they start with `CADR_` and that no
upstream fallback exists; these are configuration contracts and do not
duplicate the product display text.

### 8.2 The Part C batches

1. **C1: the identity source and the pre-adjudicated attribution** — release
   identity, UA/header, xAI; commit after a real xAI device-code request.
2. **C2: the endpoint policy** — implement share and the version check per
   B1/B2; do not mix it with the environment migration.
3. **C3: the environment variable hard cut** — update the 14 variables and the
   process harness, grouped by system.
4. **C4: the remaining free values** — repository link, temporary file, HTML
   storage, synthetic ID, Radius wording, example.
5. **C5: documentation closeout** — README, CHANGELOG, architecture and the
   acceptance report; record the approved differences and the migration table
   item by item.

Each batch goes red first and green after, running `./scripts/test-cl.sh` and
the relevant live/harness; once source is involved, rebuild the root binary and
run `./scripts/verify.sh`, and the binary's timestamp must be newer than the
last source change.

### 8.3 The Part D gate

Add a mechanical scanner and a tracked exact allowlist, covering the
outward-facing values in `src/`, `examples/`, the release scripts and
README/CHANGELOG; a new hit for `pi`, `pi.dev`, the upstream repository or
`PI_*` fails if it has no exact disposition. `verify.sh` runs both the
synthetic self-test and the real whole tree, and the real hit count must equal
the allowlist's total. `docs/development-policy.md` gains a standing rule,
"product identity has a single source".

## 9. Item-by-item adjudication requested

1. **B1**: `/share` uses `https://cadr.dev/session/` by default, overridden
   only by a non-empty `CADR_SHARE_VIEWER_URL` or an explicit argument; the
   temporarily-unreachable state before the page goes live is accepted with
   full knowledge.
2. **B2**: the version check is disabled by default when there is no
   `CADR_VERSION_CHECK_URL`; a request is made only once it is configured.
3. **B3**: hard-cut the 14 `PI_*`, with no alias and no warning compatibility
   period.
4. **B4**: replace the free identity values of section 6 as a whole group; the
   viewer metas stay for now as an exact contract, per B1.
5. **B5**: confirm the functional/provenance allowlist of section 7 item by
   item.
6. **B6**: reuse the release identity as the private single source, and
   implement according to the C1→C5 and D batches and file boundaries.

All six items above have now been adjudicated; the implementation evidence is
in `docs/acceptance/goal-v16.md`.
