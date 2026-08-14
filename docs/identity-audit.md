# Goal 16 product-identity whole-tree audit

Status: the Part A audit is complete and Part C has been implemented per user
adjudication; the fixed audit code baseline is
`3dbb58b895a1f732d6354233e91d6981b0a35c09`. This file records facts and verdicts
only; it does not authorize the Part C implementation.

## 1. Scope and method

The audit covers every tracked file that reaches the release image, a runtime
request, a user artifact, or a development/acceptance entry point: `src/`,
`examples/`, `scripts/`, the root ASDF/build files, the README, the CHANGELOG
and CI. `docs/`, the tests and the fixtures are checked separately as
provenance / cross-implementation-comparison retained items, and baseline
wording is not misjudged as product self-identification.

The mechanical enumeration uses the following set, rather than hand-picked files:

```sh
rg -n --hidden -i '(\bpi\b|\bPI_[A-Z]|pi\.dev|badlogic|earendil-works|pi-mono|pi-ai|pi-coding|pi-gateway|pi-wsl)' \
  .github examples src scripts *.asd README.md CHANGELOG.md
rg -o --no-filename '\bPI_[A-Z0-9_]+' src | sort -u
rg -n 'https://github\.com/(badlogic|earendil-works|artwalker)' \
  README.md CHANGELOG.md src examples scripts .github
git remote -v
```

The second command actually yields **14** distinct production environment
variables, not the 15 with duplicates in the specification's initial survey. The
mathematical constant `pi`, the substring inside `API_KEY`, and language built-in
symbols in vendor syntax tables have all been excluded. What the verdicts mean:

- `must replace`: a freely changeable Cadr self-identification or namespace;
- `retained under functional constraint`: the value belongs to an external
  protocol / a registered client, and changing it would directly break a
  verified contract;
- `legitimately retained`: baseline provenance, an alignment declaration,
  migration, or a fixed cross-implementation-comparison input;
- `low priority`: visible only inside the implementation, but it should still be
  renamed in the same batch to eliminate the half-changed state;
- `already compliant`: already Cadr's identity, serving as a positive example
  for the gate.

## 2. Identity anchors that are already compliant

| Location | Current value and who sees it | Verdict | Grounds |
|---|---|---|---|
| `src/cadr-ai/support/release.lisp:3-21` | `cadr 0.2.0 · aligned with pi ...`; the user, `--version`, Radius | `already compliant` | The product name is Cadr; the second half is a deliberate baseline alignment declaration. A single source for the version already exists. |
| `src/cadr-cli/system-prompt.lisp:4` | `You are cadr`; the model | `already compliant` | The model-side identity is correct. |
| `src/cadr-ai/oauth/pkce.lisp:52,303` | OpenAI `originator=cadr`; OpenAI | `already compliant` | Adjudicated in Goal 9 and verified against real OAuth. |
| `src/cadr-ai/oauth/page.lisp:3-4` | Cadr's own cons-cell SVG; the user's browser | `already compliant` | It no longer uses pi brand assets. |
| `src/cadr-cli/bootstrap/sessions.lisp:1341` | `cadr-session-<ISO>_<uuid>.html`; user files | `already compliant` | The product prefix is correct. |
| `src/cadr-cli/support/resume-version-git.lisp:4-47` | `cadr --session ...`; stdout after exit | `already compliant` | The CLI name is correct. |
| `src/cadr-core/paths.lisp` (owner), `src/cadr-cli/migration.lisp` (migration) | `~/.cadr/agent/`; the user's disk | `already compliant` | From Goal 18 on the layout is aligned with the baseline's `~/.pi/agent/`; every path is derived from the single cadr-core owner. |
| Git remote `backup` | `https://github.com/artwalker/cadr.git`; the maintainer | `already compliant` | The canonical repository. `origin=git@github.com:badlogic/pi-mono.git` is the upstream sync remote and, per the specification, is not changed. |

These anchors are still scattered across several packages; Part C must make the
reusable product slug, display name and canonical repository URL derive from the
existing single release-identity source, and must stop copying the strings.

## 3. Identifiers sent to third-party services

| Location | Current value | Who sees it | Verdict | Grounds and target value |
|---|---|---|---|---|
| `src/cadr-cli/support/resume-version-git.lisp:80-85` | `pi/<version> (...; sbcl/...)` | the version-check service | `must replace` (adjudicated) | A pure User-Agent, freely changeable; target `cadr/<version> (...)`. The function name `pi-user-agent` is renamed in the same batch. |
| `src/cadr-cli/support/headers.lisp:29` | `HTTP-Referer: https://pi.dev` | OpenRouter | `must replace` (adjudicated) | Usage attribution, not authentication; until `cadr.dev` is live the target is the canonical repository `https://github.com/artwalker/cadr`. |
| `src/cadr-cli/support/headers.lisp:30` | `X-OpenRouter-Title: pi` | OpenRouter | `must replace` (adjudicated) | Target `cadr`. |
| `src/cadr-cli/support/headers.lisp:35` | `X-BILLING-INVOKE-ORIGIN: Pi` | NVIDIA | `must replace` (adjudicated) | Billing attribution, not authentication; target `cadr`. |
| `src/cadr-cli/support/headers.lisp:44` | `User-Agent: pi-coding-agent` | Cloudflare | `must replace` (adjudicated) | Target `cadr-coding-agent`. |
| `src/cadr-cli/support/headers.lisp:53-54` | `x-opencode-client: pi` | OpenCode | `must replace` (adjudicated) | The session ID header is unchanged; the client target is `cadr`. |
| `src/cadr-ai/oauth/providers/xai.lisp:132-140` | device code `referrer=pi` | xAI | `must replace` (adjudicated) | The client ID and scope are unchanged, the referrer target is `cadr`; Part C must issue one real device-code request. |
| `src/cadr-ai/auth/radius-cloudflare.lisp:4-16`, `src/cadr-ai/oauth/providers/radius.lisp:8-10,24-31,48-55,87-115` | OAuth `client_id=pi-gateway` | Radius | `retained under functional constraint` | Measured on 2026-08-04, `GET https://radius.pi.dev/v1/oauth` returned HTTP 200, and discovery explicitly returns `clientId:"pi-gateway"`, the corresponding token/device endpoints and the `gateway offline_access` scope; this is a registered client ID, not a free attribution field. |

The five groups of attribution values — User-Agent, OpenRouter, NVIDIA,
Cloudflare, OpenCode — and the xAI referrer were pre-adjudicated by the user in
the Goal 16 specification, and no longer wait on a value-level adjudication.
Radius is the only third-party client identifier in this audit that has to be
retained on the grounds of a registration contract.

## 4. Upstream service endpoints and data flows

| Location | Current value and data flow | Verdict | Grounds |
|---|---|---|---|
| `src/cadr-cli/support/changelog-share.lisp:252-260,262-323` | `/share` first uploads the complete session HTML to a GitHub Gist with `gh gist create --public=false`, then produces `https://pi.dev/session/#<gist-id>`. The URL fragment is not sent with the first HTTP request, but the upstream viewer's browser code can obtain the gist ID and read the session. | `requires adjudication` | `CADR_SHARE_VIEWER_URL` already exists, but the old `PI_SHARE_VIEWER_URL` is still read and the default still points upstream. It involves sending a session outward and upstream page code; the default value must not be chosen unilaterally. |
| `src/cadr-cli/sdk/cache-version.lisp:272-359,388-413` | GET `https://pi.dev/api/latest-version`, sending the current version and an OS/SBCL/architecture User-Agent, reads the upstream package release and compares it against Cadr `0.2.0`. | `requires adjudication` | No session data, but the semantics are wrong: an upstream `0.83.x` is not a Cadr update. The URL is currently hard-coded and there is no Cadr URL configuration. |
| `src/cadr-ai/providers/definitions.lisp:647-664` | The Radius provider defaults to `https://radius.pi.dev`, protocol `:pi-messages`. | `retained under functional constraint` | This is the real provider endpoint of the service named Radius, not Cadr's own site. Measured on 2026-08-04, both the root path and `/v1/oauth` returned HTTP 200. `RADIUS_GATEWAY_URL` may override the model gateway. |
| `src/cadr-server/radius.lisp:151-166` | cadr-server presence defaults to `https://radius.pi.dev/v1/`, overridable by `CADR_RADIUS_SERVER_URL` or `CADR_RADIUS_URL`. | `retained under functional constraint` | The same Radius API; the code actually calls `machines/*` and `pis/*` for registration/heartbeat/disconnect. The old `PI_RADIUS_*` fallback is deleted separately under the environment-variable item. |

`/share` does not POST directly to pi.dev; the actual storage is a GitHub Gist.
But handing the session to upstream viewer code to process is still an external
trust boundary, and "the fragment does not reach the server" must not be used to
play it down.

## 5. Production environment variables: the complete list of 14

| Old variable | Location | Current precedence | Target name | Verdict and impact |
|---|---|---|---|---|
| `PI_CACHE_RETENTION` | `src/cadr-ai/providers/bedrock.lisp:338-348` | sole name | `CADR_CACHE_RETENTION` | `must replace`; Bedrock long cache configuration. |
| `PI_CONFIG_DIR` | `src/cadr-server/config.lisp:16-24` | fallback behind `CADR_CONFIG_DIR` | `CADR_CONFIG_DIR` | `must replace`; the old name is compatibility only. |
| `PI_EVAL_ARTIFACT_DIR` | `src/cadr-evals/reporter.lisp:23-31` | fallback behind `CADR_EVAL_ARTIFACT_DIR` | `CADR_EVAL_ARTIFACT_DIR` | `must replace`; the old name is compatibility only. |
| `PI_EXPERIMENTAL` | `src/cadr-cli/support/html.lisp:46-51` | fallback behind `CADR_EXPERIMENTAL` | `CADR_EXPERIMENTAL` | `must replace`; the old name is compatibility only. |
| `PI_MODEL` | `src/cadr-evals/harness.lisp:92-100` | fallback behind `CADR_EVAL_MODEL` | `CADR_EVAL_MODEL` | `must replace`; eval selection only. |
| `PI_OFFLINE` | `src/cadr-cli/tool-manager.lisp:26-28`, `src/cadr-cli/sdk/cache-version.lisp:323-331,388-399` | sole name | `CADR_OFFLINE` | `must replace`; controls tool downloads and the version check. |
| `PI_PROVIDER` | `src/cadr-evals/harness.lisp:83-91` | fallback behind `CADR_EVAL_PROVIDER` | `CADR_EVAL_PROVIDER` | `must replace`; eval selection only. |
| `PI_RADIUS_SERVER_URL` | `src/cadr-server/radius.lisp:153-158` | fallback behind `CADR_RADIUS_SERVER_URL` | `CADR_RADIUS_SERVER_URL` | `must replace`; the old name is compatibility only. |
| `PI_RADIUS_URL` | `src/cadr-server/radius.lisp:159-164` | fallback behind `CADR_RADIUS_URL` | `CADR_RADIUS_URL` | `must replace`; the old name is compatibility only. |
| `PI_SERVER_CADR_PATH` | `src/cadr-server/rpc-process.lisp:259-264` | fallback behind `CADR_SERVER_CADR_PATH` | `CADR_SERVER_CADR_PATH` | `must replace`; the old name is compatibility only. |
| `PI_SERVER_DIR` | `src/cadr-server/config.lisp:10-15` | fallback behind `CADR_SERVER_DIR` | `CADR_SERVER_DIR` | `must replace`; the old name is compatibility only. |
| `PI_SHARE_VIEWER_URL` | `src/cadr-cli/support/changelog-share.lisp:252-260` | ahead of `CADR_SHARE_VIEWER_URL` — the old name takes precedence instead | `CADR_SHARE_VIEWER_URL` | `must replace`; there is also a precedence inversion. |
| `PI_SKIP_VERSION_CHECK` | `src/cadr-cli/sdk/cache-version.lisp:388-399` | sole name | `CADR_SKIP_VERSION_CHECK` | `must replace`; depends on the version-check default adjudication. |
| `PI_TIMING` | `src/cadr-cli/support/timings.lisp:3-4` | sole name | `CADR_TIMING` | `must replace`; startup timing. |

The `PI_CODING_AGENT_DIR` in `scripts/goal11-cold-start.py` and the `PI_OFFLINE`
in `scripts/render-diff.py` are used only to clean up / drive the fixed
TypeScript baseline environment; they are not Cadr production variables and are
ruled `legitimately retained`.

## 6. Repository links and the remaining residue

| Location | Current value | Who sees it | Verdict | Grounds and target |
|---|---|---|---|---|
| `src/cadr-cli/support/changelog-share.lisp:135-161` | `/changelog` rewrites relative links and badlogic/earendil links to `https://github.com/earendil-works/pi` | the user's browser | `must replace` | The target is unified as `https://github.com/artwalker/cadr`; the private repository may currently require a login, but the URL does not change once it is public. `origin` must not be changed. |
| `src/cadr-cli/interactive/clipboard.lisp:323-329` | `pi-wsl-clip-<uuid>.png` | the temporary directory / diagnostics | `must replace` | Target `cadr-wsl-clip-<uuid>.png`. |
| `examples/extensions/notify.lisp:28` | notification title `Pi` | the user's desktop | `must replace` | Target `Cadr`. The examples are part of the shipped user surface too, and must not be missed by the scan. |
| `src/cadr-agent/export-html/template.js:1666` | localStorage `pi-share:v1:sidebar-width` | the exported HTML / the browser | `must replace` | Target `cadr-share:v1:sidebar-width`; it only resets the existing browser-side width preference. |
| `src/cadr-agent/export-html/template.js:23,1098` | meta `pi-url-params`, `pi-share-base-url` | the exported HTML / the upstream viewer iframe | `retained under functional constraint (conditional)` | The Cadr exporter does not generate these meta tags; the comments and the sole consumer in the whole tree show that they are injected by the current upstream viewer. If the pi.dev viewer is kept, the names must be kept; if the viewer is disabled or repointed, they should be changed to `cadr-*` together with the new viewer. |
| `src/cadr-ai/providers/openai.lisp:201-207` | synthetic call ID `pi_tool_load_<hash>` | the provider, the session | `must replace` | It takes no part in authentication; target `cadr_tool_load_<hash>`. |
| `src/cadr-server/radius.lisp:468,553,568,579` | user/log copy `Radius Pi` | stderr / logs | `must replace` | This is free copy, not wire; target `Radius instance`. |
| `src/cadr-server/radius.lisp:627` | thread `cadr-radius-pi-<id>` | the debugger / the thread list | `low priority` | A half-changed state; target `cadr-radius-instance-<id>`. |
| `src/cadr-cli/sdk/cache-version.lisp:299-403`, `src/cadr-cli/package.lisp:118-121` | exported symbols such as `get/check-latest-pi-*` | the Lisp API / internal | `must replace` | The feature will query Cadr releases; target `*-cadr-*`, keeping no upstream-name alias, unless the user separately requires one in Part B. |
| `src/cadr-cli/support/resume-version-git.lisp:80` | the `pi-user-agent` function name | internal | `low priority` | Changed to `cadr-user-agent` in the same batch as the UA value. |

## 7. Upstream/external contracts that must be retained

| Location | What is retained | Verdict | Specific grounds |
|---|---|---|---|
| `src/cadr-ai/auth/radius-cloudflare.lisp:13`, `src/cadr-ai/oauth/providers/radius.lisp:9` | `pi-gateway` | `retained under functional constraint` | Radius live discovery explicitly declares the registered client ID; renaming it would make all three token flows — authorization code, device code and refresh — use an unregistered client. |
| `src/cadr-server/radius.lisp:535,639,698` | `pis/*` API path | `retained under functional constraint` | The resource path of the remote Radius API; not a local product name. |
| `src/cadr-server/protocol.lisp:44`, `src/cadr-server/storage.lisp:83-114` | `radiusPiId` | `retained under functional constraint` | The local wire/persistence field for the object ID that Radius returns; renaming it would break the existing `instances.json` and the server RPC. |
| `src/cadr-ai/provider.lisp:38,117-118`, `src/cadr-ai/providers/pi-messages.lisp`, `src/cadr-ai/providers/definitions.lisp:650-651` | the `pi-messages` protocol name | `legitimately retained` | It refers to the upstream wire dialect that Radius uses, like `openai-responses`; it is not Cadr calling itself pi. |
| `src/cadr-cli/packages/manifest.lisp:9-29,128` | the `"pi"` manifest key in package.json | `retained under functional constraint` | The external manifest schema of the baseline extension ecosystem; renaming it would make the extensions/skills/prompts/themes of every existing package undiscoverable. The function name `read-package-pi-manifest` accurately describes that external schema. |
| `src/cadr-evals/suites.lisp:239-246` | `@earendil-works/pi-coding-agent` | `legitimately retained` | Used only to detect whether a generated extension still references the legacy TypeScript API; it is an audit input, not an identity. |
| `src/cadr-ai/models.generated.lisp:1`, `src/cadr-ai/image-models.generated.lisp:1` and the corresponding refresh scripts | the `pi-ai 0.83.0` source comment | `legitimately retained` | Auditable provenance for the fixed catalog. |
| `src/cadr-ai/support/release.lisp:10-21` | `aligned with pi v0.84.1 (+0, 53fa77ccd)` | `legitimately retained` | A version-relationship declaration; the specification explicitly requires it to be retained. |
| `src/cadr-cli/interactive/components/announcement.lisp:3-40` | `pi has joined Earendil` and the original blog URL | `legitimately retained` | This is a ported historical announcement component describing an upstream event that already happened on 2026-04-08; changing it to Cadr would manufacture a false history, and it is not enabled in the default interface. |
| `src/cadr-cli/interactive/selectors/common.lisp:118,128` | the `Pi Text component` docstring | `legitimately retained` | It only explains internally its cross-implementation-comparison origin and layout semantics. |
| `scripts/render-diff.py`, `scripts/goal11-pi-baseline-bench.mjs`, `scripts/export-ts-payloads.ts`, `cadr-evals.asd:30` | the pi baseline name, the fixed commit/package | `legitimately retained` | Cross-implementation-comparison and provenance inputs; replacing them would leave the gates with nothing to check. |
| pi references in the README, the CHANGELOG, `docs/` and tests/fixtures that are explicitly written as "original/aligned/baseline/migration" | upstream explanation | `legitimately retained` | Outward identity and provenance acknowledgement must be distinguished; the identity gate needs an item-by-item allowlist and must not delete them globally. |

## 8. Conclusion

The audit found no second attribution field that has registration-allowlist
evidence; apart from the Radius client/API contracts, every value that calls
itself pi outwardly should be replaced. The problem is not confined to the five
places the specification lists: there are 14 environment variables, and the
audit additionally found the exported HTML storage/meta, the notification
example, the provider synthetic call ID, the Radius free copy and the exported
Lisp API names.

Part C's gate must be fail-closed: when `pi` / an upstream domain / an upstream
repository name newly appears in the product source, only the item-by-item
allowlist that corresponds to section 7 of this file may pass; a directory-level
or regex-level blanket exemption must not be used to swallow future residue
along with it.

## 9. Part C implementation dispositions (2026-08-05)

| Batch | Disposition | Commit |
|---|---|---|
| C1 | The identity constant group for the product slug, display name, canonical repository and default viewer moved into `release.lisp`; the third-party UA/headers and the xAI referrer were unified as Cadr. A real xAI device-code request returned HTTP 200. | `cc4f1f0e0` |
| C2 | The `/share` default viewer was changed to `https://cadr.dev/session/`, with support for a `CADR_SHARE_VIEWER_URL` override and the viewer stated explicitly in the output; the version check was changed to be enabled only when `CADR_VERSION_CHECK_URL` is non-empty. | `ac23e11bb` |
| C3 | The 14 production `PI_*` names were hard-switched to `CADR_*` per the approved mapping, with no alias, warning or old-name fallback. | `af8612d95` |
| C4 | The changelog repository, the WSL temporary file, the notification title, the exported storage key, the synthetic tool ID and the Radius free copy were all changed to Cadr; the external protocols and the baseline provenance were left untouched. | `5eb36c930` |

The old environment variables in the current production source are down to zero;
the Radius client/API/wire, the extension manifest, the catalog provenance, the
fixed-baseline tooling and the `aligned with pi` declaration continue to be
retained exactly as section 7 specifies. Part D freezes that boundary into a
tracked allowlist, a synthetic self-test and a real tree scan, and does not treat
this audit text as a runtime exemption.

## 10. Goal 17 fixed-baseline gate extension re-review (2026-08-05)

Goal 17 extended the presentation, tool result and event cross-implementation
comparisons into three real fixed-baseline drivers, and brought them into
`verify.sh`. Those drivers must distinguish the `pi` and the `cadr` side
precisely in code, start the upstream process, recognize upstream path/identity
strings, and inject `PI_OFFLINE` into the upstream subprocess only; that wording
is a cross-implementation-comparison input, not Cadr self-identification or a
runtime compatibility entry point.

The organizational split also moved the baseline-provenance comments for the
config selector, direct user bash and package update, but it did not change the
product identity. The Goal 17 wrap-up deleted the obsolete Pi-side
scheduling-heuristic comment and the corresponding disposition; after Goal 17
added the fixed-baseline construction driver, the real tree is
**353 hits, 316 exact
dispositions, 1 digest-locked opaque file**. The allowlist still locks the full
text and the occurrence count line by line; any addition, deletion, move or
change in count fails closed, and there is no directory-level exemption.
