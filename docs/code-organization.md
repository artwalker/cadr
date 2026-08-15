# Code organization ledger

<!-- GOAL20_LISPIFICATION_LEDGER baseline=53fa77ccd8a279eb87e92294ef3687b03ff80112 files=293 lines=121105 assets=5 unevaluated=225 needs-rewrite=29 no-rewrite=39 in-progress=0 done=0 -->

This ledger answers a different question from the four parity ledgers: not
whether Cadr matches pi, but whether a maintainer can predict where code belongs
and whether one user-visible decision has one owner.

## 1. Audit boundary and method

The Goal 14 draft recorded 135 production files.  Goal 13 added five approved
export assets and three crash/cleanup files; Goal 14 B3 then added the six-file
`cadr-core` leaf, B1 extracted eight interactive leaf owners, B2 replaced
the remaining selector monolith with eight selector owners, B4 replaced
eight mixed CLI service files with 38 domain owners, B5 split CLI bootstrap
and RPC command handling into eleven cohesive owners, B6 replaced the two
interactive controller/component monoliths with seventeen responsibility owners,
and B7 replaced three reusable TUI monoliths with sixteen protocol-ordered
owners. B8 replaced three agent session/storage/loop monoliths with thirteen
owners, B9 replaced the extension-host monolith with eight owners, B10
replaced four mixed AI files with seventeen exact owners, and B11 replaced
five mixed provider/authentication files with 25 exact owners. Silently
retaining any earlier denominator would omit exactly the source boundaries this
goal is supposed to police, so this ledger covers all 298 current files.

- 293 Lisp files, 121,105 lines, 4,976 top-level definitions.
- 5 static export assets, 4,275 lines.
- 298 production files and 125,380 physical lines in total.
- A top-level definition is a column-zero form beginning with `def*` or
  `define-*`; static assets therefore have zero.
- `pass` means one predictable responsibility; `pass · large` means the same but
  large for a stated structural reason; `should split` means unrelated responsibilities
  share a file.  No current whole file merits `should merge`: the tiny files are package,
  protocol, adapter, or load-order boundaries rather than arbitrary fragments.

Goal 20 Part I locked the Lisp-ification denominator on 2026-08-14 (UTC 2026-08-13T18:36:11Z, Friend-MachineD). The draft snapshot (280 files / 115,621 lines, mermaid excluded) is not this lock.

```sh
find src -name '*.lisp' | wc -l
# 293
find src -name '*.lisp' -print0 | sort -z | xargs -0 wc -l | tail -1
# 121105 total
```

Every current `src/**/*.lisp` row starts at `pending evaluation`. The five export assets are `n/a` (`n/a` is outside the closed state set) and are outside the Lisp-ification denominator. Line counts in this ledger are newline counts (`wc -l`); `highlight.min.js` has no trailing newline, so `physical_line_count` is one higher on that file only. Progress is `0/293` files, `0/121,105` lines. Closed states: `pending evaluation` / `evaluated-rewrite needed` / `evaluated-no rewrite` / `rewriting` / `done`.

The audit used file contents and top-level forms, not LOC alone.  In particular,
large protocol codecs and generated/assets files remain intact, while smaller
files with unrelated facilities fail.

## 2. Per-file ledger
### 2.1 `cadr-agent`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-agent/branch-summarization.lisp` | 187 | 11 | Prepare a session branch and ask the model for its branch summary. | pass | pending evaluation | — | — |
| `src/cadr-agent/summarization.lisp` | 86 | 4 | Own the shared conversation-summary prompt, request, and retry contract. | pass | pending evaluation | — | — |
| `src/cadr-agent/compaction.lisp` | 860 | 33 | Estimate context, choose a cut point, and execute the compaction lifecycle. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/conditions.lisp` | 43 | 9 | Define agent-layer condition types. | pass | pending evaluation | — | — |
| `src/cadr-agent/execution-env.lisp` | 884 | 55 | Implement the replaceable filesystem/process execution environment used by tools and harnesses. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/export-html/template.css` | 1,066 | 0 | Provide the exact vendored baseline stylesheet embedded in offline session exports. | pass · large | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/export-html/template.html` | 55 | 0 | Provide the exact HTML shell embedded in offline session exports. | pass | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/export-html/template.js` | 1,864 | 0 | Provide the exact vendored baseline browser renderer embedded in session exports. | pass · large | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/export-html/vendor/highlight.min.js` | 1,212 | 0 | Vendor the approved Highlight.js browser asset byte-for-byte. | pass · large | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/export-html/vendor/marked.min.js` | 78 | 0 | Vendor the approved Marked browser asset byte-for-byte. | pass | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/extensions/api.lisp` | 373 | 31 | Validate active APIs, copy extension values, and project event payloads/results. | pass | pending evaluation | — | — |
| `src/cadr-agent/extensions/commands.lisp` | 296 | 11 | Invoke extension commands and expand registered prompt templates. | pass | pending evaluation | — | — |
| `src/cadr-agent/extensions/context.lisp` | 705 | 76 | Define extension host/context state, cancellation, and all context/UI actions. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/extensions/lifecycle.lisp` | 779 | 18 | Validate, merge, and dispatch the complete frozen extension lifecycle. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/extensions/providers.lisp` | 523 | 21 | Project extension tools, messages, and session-local provider overlays into an agent. | pass | pending evaluation | — | — |
| `src/cadr-agent/extensions/registration.lisp` | 812 | 53 | Define bundles, registries, frozen events, and extension authoring macros. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/extensions/rendering.lisp` | 257 | 17 | Own extension failure notices, Markdown/message/tool rendering, and shortcuts. | pass | pending evaluation | — | — |
| `src/cadr-agent/extensions/snapshot.lisp` | 405 | 12 | Build immutable extension snapshots and replace active bundles safely. | pass | pending evaluation | — | — |
| `src/cadr-agent/file-mutation-queue.lisp` | 84 | 10 | Serialize mutations to the same resolved file. | pass | pending evaluation | — | — |
| `src/cadr-agent/loop/agent-loop.lisp` | 444 | 8 | Own the public prompt/steer/follow-up entrypoints and outer agent lifecycle. | pass | pending evaluation | — | — |
| `src/cadr-agent/loop/events.lisp` | 169 | 17 | Emit and normalize agent lifecycle, stream, queue, and tool events. | pass | pending evaluation | — | — |
| `src/cadr-agent/loop/tool-execution.lisp` | 481 | 19 | Execute tool batches with hooks, restarts, termination, updates, and abort state. | pass | pending evaluation | — | — |
| `src/cadr-agent/loop/turns.lisp` | 392 | 15 | Prepare, stream, retry, compact, and finalize one agent turn. | pass | pending evaluation | — | — |
| `src/cadr-agent/messages.lisp` | 243 | 24 | Convert agent-specific message envelopes and file-operation summaries to model-facing messages. | pass | pending evaluation | — | — |
| `src/cadr-agent/package.lisp` | 447 | 1 | Declare the public `cadr-agent` package surface. | pass | pending evaluation | — | — |
| `src/cadr-agent/proxy.lisp` | 229 | 9 | Translate proxy-provider events into native agent stream events. | pass | pending evaluation | — | — |
| `src/cadr-agent/resources.lisp` | 741 | 30 | Load, validate, substitute, and format prompts and skills as agent resources. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/runtime.lisp` | 435 | 28 | Own agent event emission, queued steering/follow-up input, mutation state, abort, and shutdown. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/schema.lisp` | 833 | 18 | Validate JSON Schema definitions and tool arguments with local reference support. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/session/codec.lisp` | 571 | 30 | Encode, decode, validate, and identify session entries and metadata. | pass | pending evaluation | — | — |
| `src/cadr-agent/session/discovery.lisp` | 154 | 5 | Discover, list, continue, and resolve session files. | pass | pending evaluation | — | — |
| `src/cadr-agent/session/export-html.lisp` | 455 | 24 | Embed assets and export a session as baseline-compatible offline HTML. | pass | pending evaluation | — | — |
| `src/cadr-agent/session/journal.lisp` | 648 | 29 | Create, append, branch, label, and inspect the live JSONL session journal. | pass | pending evaluation | — | — |
| `src/cadr-agent/session/migration.lisp` | 563 | 11 | Validate and migrate v1/v2/v3 session logs with atomic replacement. | pass | pending evaluation | — | — |
| `src/cadr-agent/sqlite-storage.lisp` | 860 | 33 | Implement the SQLite session-storage and repository backend. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/storage/harness.lisp` | 495 | 31 | Adapt session-storage backends to harness session lifecycle operations. | pass | pending evaluation | — | — |
| `src/cadr-agent/storage/jsonl.lisp` | 536 | 21 | Implement JSONL session storage and repository backends. | pass | pending evaluation | — | — |
| `src/cadr-agent/storage/memory.lisp` | 372 | 20 | Implement in-memory session storage and repository backends. | pass | pending evaluation | — | — |
| `src/cadr-agent/storage/protocol.lisp` | 122 | 24 | Define storage/repository metadata, generic protocols, and shared errors. | pass | pending evaluation | — | — |
| `src/cadr-agent/tool.lisp` | 318 | 23 | Define tool registry, execution bindings, validation, and prepared outcomes. | pass · large | pending evaluation | — | — |
| `src/cadr-agent/truncate.lisp` | 283 | 31 | Implement baseline-compatible bounded head/tail/line truncation and its result contract. | pass | pending evaluation | — | — |

### 2.2 `cadr-ai`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-ai/auth.lisp` | 204 | 16 | Serialize, atomically persist, redact, and refresh provider credentials. | pass | needs-rewrite | OAuth reserved-key list hand-copied at :85-87 and :110-113; one +reserved-keys+ constant removes the duplicate wire-schema decision. | 20 |
| `src/cadr-ai/capabilities/event-stream.lisp` | 61 | 6 | Implement the producer/consumer event stream and terminal-result protocol. | pass | needs-rewrite | nconc-append emulates Array.push at :25-26 under a mutex; a head/tail queue is O(1) with identical FIFO order. | 20 |
| `src/cadr-ai/capabilities/grammar-tools.lisp` | 133 | 10 | Resolve deferred tools and strict/grammar constrained-sampling metadata. | pass | needs-rewrite | Same representation decision hand-copied twice with inverse key conventions (:45-64); one normalizing accessor suffices. | 20 |
| `src/cadr-ai/capabilities/image-runtime.lisp` | 117 | 18 | Register image APIs and own the mutable image provider/model runtime. | pass | no-rewrite | append-to-end at :41 is a cold path bounded by provider count; the catch-all at :100-117 is the baseline-mandated error-object contract via handler-case. | 20 |
| `src/cadr-ai/capabilities/proxy-config.lisp` | 77 | 5 | Resolve HTTP proxy and NO_PROXY policy for target URLs. | pass | no-rewrite | Cascaded and-checks at :14-23 mirror TS ?. chains, but proxy selection and error text are baseline-observable; explicit position arithmetic matches pi without a new dep. | 20 |
| `src/cadr-ai/capabilities/session-resources.lisp` | 34 | 5 | Register and clean session-owned provider transport resources. | pass | no-rewrite | Module-level registry at :5-7 is genuinely process-global; mutex-scoped snapshot and per-cleanup handler-case already Lisp-shaped. | 20 |
| `src/cadr-ai/capabilities/streaming-json.lisp` | 162 | 11 | Provide stable JavaScript-compatible hashes and repair partial streaming JSON. | pass | no-rewrite | Manual index loop at :76-107 is forced by the 6-char \uXXXX lookahead and the JS-semantics hash contract; case/format/handler-case used where Lisp helps. | 20 |
| `src/cadr-ai/conditions.lisp` | 44 | 12 | Define provider-layer condition types. | pass | no-rewrite | retryable-p slot mirrors a JS flag, but the hierarchy with message-only :report is the Lisp-native replacement for instanceof chains and matches String(err) output. | 20 |
| `src/cadr-ai/crash.lisp` | 269 | 16 | Redact secrets and report fatal conditions through a private crash-log boundary. | pass | needs-rewrite | #-sbcl branch at :255-269 dead-duplicates the #+sbcl boundary in an SBCL-only project; six keyword params hand-forwarded across three defuns. | 20 |
| `src/cadr-ai/crypto.lisp` | 367 | 14 | Implement SigV4 canonicalization/signing and service-account JWT signing. | pass · large | no-rewrite | Manual pad loop at :37-40 is RFC 2104 test-vector locked; the unwind-protect FFI ladder is canonical CFFI and openssl-check owns return-code checking. | 20 |
| `src/cadr-ai/image-models.generated.lisp` | 173 | 1 | Hold generated image-model catalog data. | pass · large | no-rewrite | Generated artifact pinned to the baseline catalog; the -1000000.0d0 price sentinels are data, not code shape. | 20 |
| `src/cadr-ai/images.lisp` | 222 | 8 | Build OpenRouter image requests and normalize generated-image results. | pass | no-rewrite | Tail-append at :142-145/:156-160 preserves the baseline-mandated block order on a wire-bounded list; failure mapping uses the condition system. | 20 |
| `src/cadr-ai/json.lisp` | 576 | 27 | Parse and serialize bounded JSON plus common content/data-URL helpers. | pass · large | no-rewrite | Index-walking number DFA at :52-100 transcribes RFC 8259; exact-rational round-trip is a genuine Lisp advantage TS doubles cannot express. | 20 |
| `src/cadr-ai/model-data.lisp` | 398 | 26 | Validate model-data artifacts/manifests and generate deterministic catalog fixtures. | pass · large | needs-rewrite | Sorted group->model traversal with the duplicate invariant hand-copied at :35-43 and :231-243; one walker with an error channel. | 20 |
| `src/cadr-ai/models.generated.lisp` | 8,711 | 1 | Hold the generated model metadata catalog; the generator is its owner. | pass · large | no-rewrite | Generated data artifact (1219 entries, one uniform schema); shape changes belong to the generator, not this file. | 20 |
| `src/cadr-ai/models.lisp` | 288 | 22 | Define model metadata/catalog operations, thinking-level resolution, and cost calculation. | pass | no-rewrite | nth-on-list at :216-226 is over a fixed 7-element ordinal constant and directly expresses the baseline nearest-level search; rest is defstruct+registry+conditions. | 20 |
| `src/cadr-ai/oauth/callback.lisp` | 316 | 11 | Parse manual/callback authorization input and own the loopback callback lifecycle. | pass | needs-rewrite | Behavioral dispatch on string-equal display names at :92-109 while the module already has keyword dispatch elsewhere; one metadata-dispatch owner. | 20 |
| `src/cadr-ai/oauth/openai-anthropic.lisp` | 288 | 12 | Exchange, refresh, and orchestrate the browser OAuth flows shared by OpenAI Codex and Anthropic. | pass | needs-rewrite | login-openai-oauth and login-anthropic-oauth (:184-288) hand-copy the whole PKCE flow despite sharing the metadata struct. | 20 |
| `src/cadr-ai/oauth/page.lisp` | 149 | 6 | Render the branded OAuth callback success and error pages. | pass | needs-rewrite | string-equal provider dispatch at :127-141 re-decides what callback.lisp:92-115 already decides; no single owner. | 20 |
| `src/cadr-ai/oauth/pkce.lisp` | 322 | 36 | Own OAuth metadata plus the SHA-256, Base64URL, PKCE, state, and authorization-URL primitives. | pass | no-rewrite | Hand-indexed SHA-256 at :165-195 is spec-locked 32-bit arithmetic; dep policy bars ironclad, so test-vector transcription is correct. | 20 |
| `src/cadr-ai/oauth/providers/anthropic.lisp` | 16 | 1 | Project the Anthropic browser OAuth flow into the runtime callback contract. | pass | no-rewrite | 16-line adapter; closure wrappers at :7-16 are precisely the seam keeping the login flow decoupled. | 20 |
| `src/cadr-ai/oauth/providers/github-copilot.lisp` | 138 | 13 | Implement GitHub Copilot device login, token exchange, refresh, and model filtering. | pass | no-rewrite | RFC 8628 code lists at :117-118 are wire tokens; the single-owner fix belongs to oauth-poll-token defaults, not this file. | 20 |
| `src/cadr-ai/oauth/providers/kimi.lisp` | 58 | 6 | Implement Kimi Coding device login and credential refresh. | pass | no-rewrite | Poll vocabulary at :43-44 is wire constants; owner fix lives in oauth-poll-token (xai.lisp:91), not here. | 20 |
| `src/cadr-ai/oauth/providers/openai-device.lisp` | 199 | 7 | Implement OpenAI Codex device authorization, polling, and runtime login selection. | pass | no-rewrite | string= on OpenAI wire error codes at :116-123 is the baseline-verbatim contract; cancellation via dynamic binding is already Lisp-native. | 20 |
| `src/cadr-ai/oauth/providers/openrouter.lisp` | 89 | 7 | Implement OpenRouter PKCE login, key exchange, and refresh. | pass | no-rewrite | Empty-string-as-null at :42-43 is forced by the shared auth.json round-trip contract. | 20 |
| `src/cadr-ai/oauth/providers/radius.lisp` | 126 | 9 | Implement Radius browser/device login and gateway-scoped credential refresh. | pass | needs-rewrite | Fourth hand copy of the device-authorization parse decision at :32-42 (no numberp guard); fold into the shared parser. | 20 |
| `src/cadr-ai/oauth/providers/xai.lisp` | 184 | 17 | Implement xAI device authorization, polling, and refresh over the shared OAuth request boundary. | pass | no-rewrite | member/string= over wire error lists at :112-120 are protocol constants; file already uses dynamic vars and &key test seams. | 20 |
| `src/cadr-ai/package.lisp` | 475 | 2 | Declare the public `cadr-ai` package surface and HTTP injection seam. | pass | no-rewrite | The export barrel mirrors index.ts, but one defpackage is CL's one-owner API inventory; scattering :export would create N owners. | 20 |
| `src/cadr-ai/auth/bedrock.lisp` | 216 | 12 | Resolve Bedrock credentials, profiles, regions, and ARN-derived configuration. | pass | needs-rewrite | nth 2/nth 3 tuple access on a list at :203-207; destructuring-bind with a stringp guard is behavior-identical. | 20 |
| `src/cadr-ai/auth/device-code.lisp` | 211 | 10 | Own generic cancellable device-code polling, validation, and credential parsing. | pass | needs-rewrite | Two hand copies of one parse decision at :126-154 and :183-211; a shared parse-device-authorization with keyword options. | 20 |
| `src/cadr-ai/auth/github-copilot.lisp` | 66 | 3 | Parse GitHub device authorization and resolve Copilot endpoint/model metadata. | pass | needs-rewrite | Third hand copy of the same device-parse decision at :3-21; folds into the device-code.lisp shared parser. | 20 |
| `src/cadr-ai/auth/radius-cloudflare.lisp` | 115 | 4 | Validate Radius configuration and materialize Radius/Cloudflare endpoints. | pass | needs-rewrite | Hardcoded "pi-gateway"/scope at :13-15 duplicate the constants in radius.lisp:9-10 — one client-identity decision, two owners. | 20 |
| `src/cadr-ai/auth/vertex.lisp` | 212 | 8 | Resolve Google Vertex credentials and exchange service-account access tokens. | pass | no-rewrite | string= dispatch on method ids at :31-53 is the baseline prompt-flow contract; injected probes and data-driven specs are Lisp-native. | 20 |
| `src/cadr-ai/provider.lisp` | 799 | 75 | Define provider protocol classes plus common request, retry, history, stream, and error machinery. | pass · large | no-rewrite | append-content-block at :470-474 emulates push, but the list position IS the content-index contract; CLOS generics and constructor macro used elsewhere. | 20 |
| `src/cadr-ai/providers/anthropic.lisp` | 610 | 16 | Implement Anthropic Messages request, response, cache, tool, and stream semantics. | pass · large | needs-rewrite | Manual index loop with O(n) nth at :188-235; a tail/pop traversal is byte-identical and O(n). | 20 |
| `src/cadr-ai/providers/google.lisp` | 405 | 17 | Implement Google Generative AI request, thinking, response, and stream semantics. | pass · large | needs-rewrite | The gemini-3 sniff decision hand-copied at :49-51 and :74-78 while sibling predicates exist at :111-128. | 20 |
| `src/cadr-ai/providers/azure-openai.lisp` | 241 | 12 | Adapt Azure, Copilot, and Cloudflare OpenAI-compatible endpoints and headers. | pass | needs-rewrite | The 8-keyword build-request protocol hand-recopied through two delegation layers (:66-75, :214-221); &rest/apply is the CLOS idiom. | 20 |
| `src/cadr-ai/providers/bedrock.lisp` | 927 | 32 | Implement Bedrock Converse payloads, SigV4 request metadata, event reduction, and complete responses. | pass · large | needs-rewrite | The ~20-line sigv4 authorization multiple-value-bind hand-copied at :566-587 and :604-624, differing only in the credential plist. | 20 |
| `src/cadr-ai/providers/codex.lisp` | 35 | 1 | Adapt the OpenAI Codex Responses request contract. | pass | no-rewrite | Post-build remhash at :28-33 reuses the OpenAI builder and applies a two-key delta — the correct reuse shape, not a copy. | 20 |
| `src/cadr-ai/providers/mistral.lisp` | 98 | 4 | Adapt Mistral Conversations reasoning and tool-call identifiers. | pass | needs-rewrite | Session/cache-affinity decision hand-copied at :75-78 vs :90-93 plus a duplicated hash-input branch; bind once in the let*. | 20 |
| `src/cadr-ai/providers/pi-messages.lisp` | 254 | 6 | Implement pi Messages request rewriting and event/response reduction. | pass | needs-rewrite | nth per stream event at :181/:197 while a hash keyed by the same index exists at :170-172; store blocks in it. | 20 |
| `src/cadr-ai/providers/vertex.lisp` | 130 | 2 | Adapt Google Vertex endpoints and signed request construction. | pass | no-rewrite | {location} substring sniffing at :7 is the baseline base-URL config contract; credential fallback is or/let* idiom with signaled errors. | 20 |
| `src/cadr-ai/providers/openai-completions.lisp` | 851 | 31 | Implement OpenAI-compatible Chat Completions request, response, tool, and stream semantics. | pass · large | needs-rewrite | Magic +100000 key namespacing with nth lookups at :652/:695/:702/:748; store the block object in block-indices instead. | 20 |
| `src/cadr-ai/providers/openai.lisp` | 763 | 17 | Implement OpenAI Responses request, response, tool, reasoning, and stream semantics. | pass · large | needs-rewrite | openai-stream-block does nth random access per delta at :507-515; block-indices can hold the block object. | 20 |
| `src/cadr-ai/providers/definitions.lisp` | 1,035 | 14 | Validate and own the complete 38-provider declaration matrix and environment inputs. | pass · large | needs-rewrite | +provider-definition-row-keys+ at :929-935 hand-copies 22 slot names that sb-mop already derives at :36-42. | 20 |
| `src/cadr-ai/providers/registry.lisp` | 157 | 2 | Instantiate declared providers through the appropriate native protocol class. | pass | no-rewrite | Five metadata-or-fallback ifs at :124-148 share a shape but are five distinct decisions — the explicit chain is the auditable parity contract. | 20 |
| `src/cadr-ai/providers/runtime-projection.lisp` | 288 | 15 | Project provider declarations into session-local auth, OAuth, model, and dispatch callbacks. | pass | needs-rewrite | The structured-API-key strategy set enumerated three times (:26-28, :32-35, :62-63/:80); a strategy table makes the claimed single owner real. | 20 |
| `src/cadr-ai/runtime/faux-provider.lisp` | 604 | 33 | Implement the deterministic faux provider, queued responses, and transcript serializer. | pass | needs-rewrite | Thinking/text/tool-call branches at :500-592 triplicate one emit skeleton; collapse into one helper parameterized on block constructor. | 20 |
| `src/cadr-ai/runtime/models.lisp` | 834 | 50 | Own mutable provider/model/auth state, refresh, lookup, and request dispatch. | pass · large | needs-rewrite | The models-runtime-error wrapping decision hand-copied 8+ times (:281-570); one error-wrapping macro removes it. | 20 |
| `src/cadr-ai/sse.lisp` | 101 | 5 | Parse Server-Sent Events from text or binary streams. | pass | no-rewrite | Sentinel read loop at :91-97 transcribes the WHATWG line protocol; field dispatch has one owner and failures signal typed errors. | 20 |
| `src/cadr-ai/support/grammar-coercion.lisp` | 227 | 13 | Coerce and validate grammar-tool JSON values against schemas. | pass | no-rewrite | string= type dispatch at :57-66/:80-121 is external JSON Schema vocabulary the baseline compares verbatim. | 20 |
| `src/cadr-ai/support/overflow.lisp` | 78 | 5 | Classify context-overflow errors from status and usage evidence. | pass | no-rewrite | String fragment tables at :3-27 are provider wire error messages; case-insensitive substring match is the baseline heuristic. | 20 |
| `src/cadr-ai/support/release.lisp` | 96 | 18 | Read the single version source and format the aligned release identity. | pass | no-rewrite | Format-built copy at :75-96 is byte-locked to baseline auth-guidance.ts with citations; wrappers implement the single-owner identity. | 20 |
| `src/cadr-ai/support/retry.lisp` | 177 | 9 | Classify retryable assistant failures and execute the bounded retry policy. | pass | needs-rewrite | The abort-during-wait block is copied verbatim at :147-159 and :163-175; one local function removes it. | 20 |
| `src/cadr-ai/support/threads.lisp` | 6 | 1 | Delegate bounded thread cleanup to the B3 core policy owner. | pass | no-rewrite | A 3-line facade forwarder keeping cadr-core the owner; nothing TS-shaped exists to rewrite. | 20 |
| `src/cadr-ai/support/token-estimation.lisp` | 170 | 14 | Estimate message, tool, image, and context token usage. | pass | no-rewrite | utf16-code-unit-length at :11-13 counts UTF-16 units because that is the JS-semantics baseline heuristic, not an index-loop habit. | 20 |
| `src/cadr-ai/support/uuid.lisp` | 65 | 4 | Generate monotonic UUIDv7 identifiers from random octets. | pass | no-rewrite | Manual byte assembly at :38-58 is RFC 9564 UUIDv7 layout; ldb packing is the idiomatic CL encoding of a fixed wire format. | 20 |
| `src/cadr-ai/transport/aws-event-stream.lisp` | 222 | 10 | Decode AWS event-stream frames and issue Bedrock event requests. | pass | no-rewrite | Manual offset walking and CRC32 at :18-83 are a byte-fixed frame format; dep policy bars new libs, failures are signaled conditions. | 20 |
| `src/cadr-ai/transport/http.lisp` | 858 | 41 | Implement abortable native HTTP/TLS transport, framing, and normalized errors. | pass · large | needs-rewrite | Default-port elision decided twice (:496-504 helper vs :568-581 inline); timeout handler clauses triplicated at :760-787. | 20 |
| `src/cadr-ai/types.lisp` | 230 | 22 | Define provider/model/message/content/tool/event value types and safe printers. | pass | needs-rewrite | make-assistant-message at :141-166 re-declares 12 keywords with zero added logic; make the defstruct constructor carry the name directly. | 20 |
| `src/cadr-ai/websocket.lisp` | 620 | 41 | Implement OpenAI Codex WebSocket framing, pooling, continuation, and provider dispatch. | pass · large | no-rewrite | json-value-equal-p at :403-404 matches the baseline's own JSON.stringify cache-admission comparison; hand-rolled SHA-1 justified by the dep policy. | 20 |

### 2.3 `cadr-cli`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-cli/arguments.lisp` | 734 | 23 | Parse, validate, resolve, and document the CLI argument contract. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/bootstrap/auth.lisp` | 176 | 2 | Project provider-owned authentication options into the native CLI login command. | pass | pending evaluation | — | — |
| `src/cadr-cli/bootstrap/commands.lisp` | 2,551 | 8 | Construct the agent controller and dispatch CLI modes and slash-command output through one frontend sink. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/bootstrap/main.lisp` | 319 | 4 | Handle package/credential preflight, parse arguments, and enter the selected CLI path. | pass | pending evaluation | — | — |
| `src/cadr-cli/bootstrap/sessions.lisp` | 1,942 | 45 | Resolve, create, switch, fork, export, and mutate CLI sessions and their tree lifecycle. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/bootstrap/settings.lisp` | 808 | 17 | Resolve agent directories, trust, settings, resources, runtime reload, and the effective system prompt. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/bootstrap/tools.lisp` | 89 | 8 | Construct the baseline tool set and its prompt metadata. | pass | pending evaluation | — | — |
| `src/cadr-cli/build-support.lisp` | 14 | 2 | Supply the native-image save arguments and executable entry point. | pass | pending evaluation | — | — |
| `src/cadr-cli/config.lisp` | 288 | 20 | Resolve legacy CLI provider configuration and auth commands. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/atomic-write.lisp` | 5 | 1 | Retain the CLI compatibility entry point while delegating atomic replacement to `cadr-core`. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/changelog-share.lisp` | 342 | 10 | Strip terminal styling, parse changelogs, and publish the resulting session share. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/event-bus.lisp` | 40 | 5 | Own the process-local event bus and its error sink. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/external-editor.lisp` | 20 | 1 | Round-trip text through the configured external editor. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/file-watcher.lisp` | 69 | 6 | Poll one file signature and close its worker through bounded cleanup. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/headers.lisp` | 81 | 4 | Merge provider attribution and request header sources. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/html.lisp` | 63 | 5 | Escape and validate HTML-facing strings and shell quoting. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/model-help.lisp` | 18 | 6 | Construct provider/model login help and missing-model diagnostics. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/paths.lisp` | 119 | 6 | Parse file URLs and normalize user path input without changing caller display policy. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/resume-version-git.lisp` | 227 | 9 | Format resume commands and parse versioned Git sources. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/shell-process.lisp` | 132 | 12 | Discover shell configuration and manage detached process trees. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/threads.lisp` | 6 | 1 | Retain the CLI cleanup entry point while delegating policy to `cadr-core`. | pass | pending evaluation | — | — |
| `src/cadr-cli/support/timings.lisp` | 46 | 6 | Record and print opt-in startup timing namespaces. | pass | pending evaluation | — | — |
| `src/cadr-cli/crash.lisp` | 59 | 4 | Bind CLI-specific secret discovery and redaction into the fatal-condition boundary. | pass | pending evaluation | — | — |
| `src/cadr-cli/extensions/commands.lisp` | 56 | 3 | Dispatch extension commands and prompt-template expansion. | pass | pending evaluation | — | — |
| `src/cadr-cli/extensions/discovery.lisp` | 212 | 11 | Define extension source/manager records and discover precedence-ordered sources. | pass | pending evaluation | — | — |
| `src/cadr-cli/extensions/installer.lisp` | 211 | 9 | Validate, stage, clone, and install opt-in extension packages. | pass | pending evaluation | — | — |
| `src/cadr-cli/extensions/loader.lisp` | 702 | 20 | Own extension/infrastructure output sinks, local dependency loading, UI wiring, and reload lifecycle. | pass | pending evaluation | — | — |
| `src/cadr-cli/extensions/llama/client.lisp` | 472 | 25 | Implement llama-server HTTP operations and progress polling. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/extensions/llama/extension.lisp` | 464 | 17 | Bind llama commands and catalog refresh into the extension API. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/extensions/llama/huggingface.lisp` | 290 | 14 | Search and inspect Hugging Face GGUF artifacts. | pass | pending evaluation | — | — |
| `src/cadr-cli/extensions/llama/provider.lisp` | 322 | 11 | Project llama-server as a session-local native provider. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/components/loaders.lisp` | 150 | 14 | Own dynamic-border and bordered-loader component primitives. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/components/countdown.lisp` | 90 | 7 | Own deterministic countdown timer state, rendering, and ticking. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/components/armin.lisp` | 269 | 16 | Own the Armin animated component and its frame lifecycle. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/components/daxnuts.lisp` | 168 | 14 | Own the Daxnuts animated component and its frame lifecycle. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/components/announcement.lisp` | 41 | 2 | Compose the Earendil announcement component. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/clipboard.lisp` | 449 | 22 | Own platform clipboard text/image discovery, reading, and writes. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/footer.lisp` | 536 | 23 | Own footer path/usage/status projection and asynchronous Git branch data. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/images.lisp` | 290 | 9 | Inspect and process interactive image bytes under model limits. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/state.lisp` | 298 | 12 | Own mutable TUI entry, overlay, status, theme, and root-state records. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/status.lisp` | 456 | 26 | Own startup input, status projection, render coordination, spinners, and account warnings. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/syntax.lisp` | 1,106 | 33 | Implement baseline-compatible deterministic syntax highlighting. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/theme.lisp` | 215 | 11 | Detect, resolve, export, and discover interactive themes. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/themes.lisp` | 388 | 12 | Watch, validate, and apply live TUI theme files and terminal theme changes. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/tool-render-session.lisp` | 61 | 3 | Own incremental tool-render session state and projection. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/user-bash.lisp` | 213 | 9 | Render and update direct user bash executions independently of agent tool calls. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/transcript.lisp` | 1,087 | 29 | Project every session entry and assistant/user/custom transcript component. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/tool-rendering.lisp` | 996 | 23 | Project agent tool calls/results and reduce agent events into TUI state. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/entries.lisp` | 916 | 34 | Own append, replacement, invalidation, and status-entry mutation. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/pending-messages.lisp` | 63 | 3 | Render and restore queued steering and follow-up input. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/frame.lisp` | 238 | 4 | Compose transcript, status, widgets, overlays, editor, and footer into one frame. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/extension-ui.lisp` | 762 | 34 | Bridge extension UI requests and custom components into the live TUI. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/autocomplete.lisp` | 332 | 15 | Construct command/path autocomplete and extension shortcut routing. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/controller.lisp` | 2,902 | 20 | Own the interactive lifecycle, slash-command routing, input loop, and cleanup. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/selectors/common.lisp` | 394 | 27 | Own composable selector chrome, viewport/count, input, fuzzy matching, and wrap navigation. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/selectors/sessions.lisp` | 1,473 | 48 | Search, mutate, navigate, and render resumable session trees. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/selectors/tree.lisp` | 1,812 | 57 | Filter, navigate, edit, and render the branching session tree overlay. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/selectors/settings.lisp` | 936 | 27 | Edit settings and theme submenus through the shared selector frame. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/selectors/auth.lisp` | 624 | 25 | Select authentication methods/providers and collect API keys. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/selectors/models.lisp` | 1,316 | 62 | Search, choose, scope, enable, and order models. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/selectors/trust.lisp` | 293 | 10 | Choose and persist project trust decisions. | pass | pending evaluation | — | — |
| `src/cadr-cli/interactive/selectors/fork.lisp` | 147 | 7 | Choose the user-message boundary for a forked session. | pass | pending evaluation | — | — |
| `src/cadr-cli/media.lisp` | 1,277 | 56 | Decode, orient, resample, and encode PNG/JPEG image bytes under model limits. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/migration.lisp` | 509 | 29 | Safely migrate the legacy user-data directory with explicit consent. | pass | pending evaluation | — | — |
| `src/cadr-cli/models/auth-storage.lisp` | 376 | 24 | Serialize locked auth-store updates and runtime credential overrides. | pass | pending evaluation | — | — |
| `src/cadr-cli/models/credential-print.lisp` | 634 | 20 | Parse and execute the one-shot credential-print command without exposing secrets. | pass | pending evaluation | — | — |
| `src/cadr-cli/models/login-selection.lisp` | 75 | 4 | Classify post-login default-model selection into the baseline four branches. | pass | pending evaluation | — | — |
| `src/cadr-cli/models/matching.lisp` | 413 | 17 | Resolve exact, partial, scoped, and globbed model selections. | pass | pending evaluation | — | — |
| `src/cadr-cli/models/registry.lisp` | 799 | 34 | Build, refresh, authenticate, and project the cohesive runtime model registry. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/models/store.lisp` | 168 | 8 | Read and mutate provider-scoped `models.json` entries. | pass | pending evaluation | — | — |
| `src/cadr-cli/modes/print.lisp` | 590 | 17 | Render agent events for print and JSON command-line modes. | pass | pending evaluation | — | — |
| `src/cadr-cli/modes/rpc/commands.lisp` | 478 | 3 | Validate and dispatch the closed RPC command set through the shared response sink. | pass | pending evaluation | — | — |
| `src/cadr-cli/modes/rpc/jsonl.lisp` | 123 | 16 | Read/write and validate the RPC JSONL envelope. | pass | pending evaluation | — | — |
| `src/cadr-cli/modes/rpc/mode.lisp` | 96 | 3 | Own RPC line dispatch, event subscription, stream lifetime, and shutdown. | pass | pending evaluation | — | — |
| `src/cadr-cli/modes/rpc/models.lisp` | 221 | 13 | Project, select, and cycle RPC models and thinking levels. | pass | pending evaluation | — | — |
| `src/cadr-cli/modes/rpc/prompt-bash.lisp` | 225 | 7 | Start, steer, abort, and observe RPC prompt and bash work. | pass | pending evaluation | — | — |
| `src/cadr-cli/modes/rpc/sessions.lisp` | 283 | 10 | Create, switch, fork, compact, and inspect RPC sessions and trees. | pass | pending evaluation | — | — |
| `src/cadr-cli/modes/rpc/ui.lisp` | 301 | 11 | Bridge extension UI requests to RPC dialogs with cancellation and timeout. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/output-accumulator.lisp` | 199 | 17 | Accumulate split UTF-8 process output into a bounded tail and spill file. | pass | pending evaluation | — | — |
| `src/cadr-cli/packages/config-selector.lisp` | 1,524 | 70 | Own the standalone config selector, resource projection, and scoped persistence interaction. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/packages/commands.lisp` | 764 | 9 | Parse package commands and execute help/list/install/update/remove workflows. | pass | pending evaluation | — | — |
| `src/cadr-cli/packages/manifest.lisp` | 186 | 5 | Parse package manifests and project resource paths. | pass | pending evaluation | — | — |
| `src/cadr-cli/packages/settings.lisp` | 214 | 10 | Persist, remove, deduplicate, and materialize configured package records. | pass | pending evaluation | — | — |
| `src/cadr-cli/packages/source.lisp` | 348 | 13 | Parse and canonicalize npm, Git, SSH, and local package sources. | pass | pending evaluation | — | — |
| `src/cadr-cli/package.lisp` | 289 | 1 | Declare the public `cadr-cli` package surface. | pass | pending evaluation | — | — |
| `src/cadr-cli/remote-repl.lisp` | 67 | 8 | Manage the opt-in Slynk server and active-agent binding. | pass | pending evaluation | — | — |
| `src/cadr-cli/repl.lisp` | 112 | 4 | Run the basic line-oriented REPL mode. | pass | pending evaluation | — | — |
| `src/cadr-cli/resource-loader.lisp` | 365 | 13 | Discover and reload scoped prompts, skills, themes, context, and extensions. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/sdk/agent-session.lisp` | 474 | 16 | Construct and expose the in-process agent-session facade. | pass | pending evaluation | — | — |
| `src/cadr-cli/sdk/cache-version.lisp` | 490 | 27 | Detect cache anomalies, restore proxy state, and perform release/version checks. | pass | pending evaluation | — | — |
| `src/cadr-cli/sdk/model-service.lisp` | 355 | 19 | Implement the SDK model runtime and shared atomic credential path. | pass | pending evaluation | — | — |
| `src/cadr-cli/sdk/resource-service.lisp` | 367 | 13 | Implement reloadable SDK resource discovery and overrides. | pass | pending evaluation | — | — |
| `src/cadr-cli/sdk/session-manager.lisp` | 107 | 8 | Resolve, create, continue, open, and list SDK sessions. | pass | pending evaluation | — | — |
| `src/cadr-cli/sdk/session-runtime.lisp` | 277 | 15 | Own replaceable SDK session services and runtime disposal. | pass | pending evaluation | — | — |
| `src/cadr-cli/sdk/settings-service.lisp` | 181 | 20 | Adapt persistent and in-memory settings to the SDK contract. | pass | pending evaluation | — | — |
| `src/cadr-cli/sdk/system-prompt.lisp` | 213 | 5 | Build the SDK system prompt and extension-aware provider stream. | pass | pending evaluation | — | — |
| `src/cadr-cli/settings/config-values.lisp` | 198 | 15 | Resolve environment and command-backed configuration values and JSON merges. | pass | pending evaluation | — | — |
| `src/cadr-cli/settings/manager.lisp` | 496 | 27 | Own layered settings reload, mutation, defaults, and keybindings. | pass | pending evaluation | — | — |
| `src/cadr-cli/settings/trust.lisp` | 216 | 13 | Persist and resolve inherited project-trust decisions. | pass | pending evaluation | — | — |
| `src/cadr-cli/system-prompt.lisp` | 53 | 4 | Resolve the default, replacement, and appended system prompt. | pass | pending evaluation | — | — |
| `src/cadr-cli/tool-manager.lisp` | 286 | 25 | Locate, download, extract, and quarantine optional host tools. | pass | pending evaluation | — | — |
| `src/cadr-cli/tools/bash.lisp` | 590 | 23 | Execute bash with live output, process-group abort/timeout, truncation, and tool wrapping. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/tools/edit.lisp` | 753 | 31 | Match replacements and produce/apply exact edit diffs. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/tools/find.lisp` | 101 | 3 | Implement the bounded find tool. | pass | pending evaluation | — | — |
| `src/cadr-cli/tools/glob.lisp` | 213 | 13 | Implement recursive globbing with parseable gitignore rules. | pass | pending evaluation | — | — |
| `src/cadr-cli/tools/grep.lisp` | 308 | 6 | Implement bounded regex/literal grep with context. | pass | pending evaluation | — | — |
| `src/cadr-cli/tools/ls.lisp` | 100 | 3 | Implement the bounded directory-listing tool. | pass | pending evaluation | — | — |
| `src/cadr-cli/tools/path.lisp` | 324 | 31 | Normalize tool paths/arguments/errors and serialize file mutations. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/tools/read.lisp` | 152 | 2 | Implement the bounded line-oriented read tool. | pass | pending evaluation | — | — |
| `src/cadr-cli/tools/write.lisp` | 71 | 3 | Implement the UTF-8 write tool and baseline result count. | pass | pending evaluation | — | — |
| `src/cadr-cli/truncation.lisp` | 79 | 12 | Adapt agent truncation results to the CLI tool-result detail contract. | pass | pending evaluation | — | — |
| `src/cadr-cli/extensions/llama/ui.lisp` | 759 | 35 | Render the interactive llama.cpp manager surface: context labels, model descriptions, compact counts, the framed selector, live Hugging Face search, and cancellable progress. | pass · large | pending evaluation | — | — |
| `src/cadr-cli/interactive/selectors/login-dialog.lisp` | 279 | 13 | Own the login dialog frame, OAuth/device-code sections, and manual authorization input. | pass | pending evaluation | — | — |
| `src/cadr-cli/packages/update-checks.lisp` | 293 | 14 | Run background package update checks with process-group isolation and the candidate scan. | pass | pending evaluation | — | — |

### 2.4 `cadr-evals`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-evals/artifacts.lisp` | 168 | 11 | Validate, hash, persist, and reference eval artifacts. | pass | pending evaluation | — | — |
| `src/cadr-evals/harness-table.lisp` | 359 | 17 | Define eval harness rows/tables, canonical group keys, and iteration wrappers. | pass · large | pending evaluation | — | — |
| `src/cadr-evals/harness.lisp` | 730 | 29 | Run a coding-agent eval lifecycle and normalize transcript, usage, and cleanup. | pass · large | pending evaluation | — | — |
| `src/cadr-evals/main.lisp` | 154 | 5 | Parse eval CLI arguments, dispatch suites, and validate result shape. | pass | pending evaluation | — | — |
| `src/cadr-evals/package.lisp` | 100 | 2 | Declare the public eval package and session snapshot artifact name. | pass | pending evaluation | — | — |
| `src/cadr-evals/reporter.lisp` | 308 | 14 | Persist eval case records and finish a harness report. | pass · large | pending evaluation | — | — |
| `src/cadr-evals/suites.lisp` | 479 | 21 | Define the smoke and extension-authoring eval suites and judges. | pass · large | pending evaluation | — | — |
| `src/cadr-evals/summary.lisp` | 733 | 31 | Pair observations, compute correctness/efficiency summaries, and render comparison reports. | pass · large | pending evaluation | — | — |

### 2.5 `cadr-protocol`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-protocol/cbor.lisp` | 508 | 37 | Encode and decode bounded RFC 8949 CBOR values. | pass · large | pending evaluation | — | — |
| `src/cadr-protocol/codec.lisp` | 121 | 10 | Compose message validation, CBOR, and framing into incremental client/server codecs. | pass | pending evaluation | — | — |
| `src/cadr-protocol/framing.lisp` | 145 | 15 | Encode and incrementally decode bounded length-prefixed frames. | pass | pending evaluation | — | — |
| `src/cadr-protocol/package.lisp` | 33 | 1 | Declare the public `cadr-protocol` package surface. | pass | pending evaluation | — | — |
| `src/cadr-protocol/schema.lisp` | 620 | 33 | Validate and parse every protocol v2 client/server message shape. | pass · large | pending evaluation | — | — |

### 2.6 `cadr-server`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-server/config.lisp` | 45 | 6 | Resolve server state, auth, instance, and socket paths. | pass | pending evaluation | — | — |
| `src/cadr-server/handler.lisp` | 101 | 1 | Dispatch one local server request to supervisor operations. | pass | pending evaluation | — | — |
| `src/cadr-server/ipc.lisp` | 317 | 14 | Serve and call the framed Unix-socket server transport. | pass · large | pending evaluation | — | — |
| `src/cadr-server/main.lisp` | 211 | 10 | Parse server CLI operations and run server or stream-client entry points. | pass | pending evaluation | — | — |
| `src/cadr-server/package.lisp` | 59 | 1 | Declare the public `cadr-server` package surface. | pass | pending evaluation | — | — |
| `src/cadr-server/protocol.lisp` | 49 | 5 | Encode/decode the server control-plane JSON messages. | pass | pending evaluation | — | — |
| `src/cadr-server/radius.lisp` | 737 | 43 | Manage opt-in Radius registration, heartbeat, recovery, and redacted token use. | pass · large | pending evaluation | — | — |
| `src/cadr-server/rpc-process.lisp` | 417 | 26 | Own one child `cadr --mode rpc` process, pending calls, event/UI callbacks, and teardown. | pass · large | pending evaluation | — | — |
| `src/cadr-server/storage.lisp` | 195 | 15 | Persist server machine and instance records. | pass | pending evaluation | — | — |
| `src/cadr-server/supervisor.lisp` | 609 | 27 | Supervise live RPC child instances, streams, persistence, and recovery. | pass · large | pending evaluation | — | — |
| `src/cadr-server/types.lisp` | 24 | 4 | Define machine/instance record values and timestamps. | pass | pending evaluation | — | — |

### 2.7 `cadr-storage`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-storage/package.lisp` | 19 | 1 | Declare the minimal SQLite adapter package. | pass | pending evaluation | — | — |
| `src/cadr-storage/sqlite.lisp` | 12 | 3 | Wrap SQLite open, close, and migration operations. | pass | pending evaluation | — | — |

### 2.8 `cadr-tui`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-tui/autocomplete.lisp` | 592 | 37 | Parse completion context and provide cancellable command/file suggestions and application. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/components/image.lisp` | 45 | 1 | Render image bytes or the baseline text fallback. | pass | pending evaluation | — | — |
| `src/cadr-tui/components/markdown.lisp` | 1,564 | 46 | Render Markdown, ANSI tables, inline spans, and visually truncated text. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/components/select-list.lisp` | 308 | 8 | Own filterable two-column selection state, navigation, and rendering. | pass | pending evaluation | — | — |
| `src/cadr-tui/components/status.lisp` | 253 | 6 | Render footer and status-bar projections. | pass | pending evaluation | — | — |
| `src/cadr-tui/components/tool-block.lisp` | 626 | 23 | Render tool titles, previews, diffs, elapsed time, and result states. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/composition/loaders.lisp` | 238 | 20 | Own animated and cancellable loader components using the shared cleanup policy. | pass | pending evaluation | — | — |
| `src/cadr-tui/composition/protocol.lisp` | 127 | 30 | Define the component, focus, container, render, event, and disposal protocols. | pass | pending evaluation | — | — |
| `src/cadr-tui/composition/rich-content.lisp` | 276 | 10 | Compose cached Markdown and image components. | pass | pending evaluation | — | — |
| `src/cadr-tui/composition/root.lisp` | 317 | 23 | Own the TUI root, focus routing, render scheduling, and overlay stack. | pass | pending evaluation | — | — |
| `src/cadr-tui/composition/settings-list.lisp` | 459 | 30 | Implement settings-list behavior and the shared editor-component adapters. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/composition/text-box.lisp` | 275 | 23 | Implement text, spacer, box, and truncated-text components. | pass | pending evaluation | — | — |
| `src/cadr-tui/editor.lisp` | 1,989 | 87 | Implement the grapheme-aware multiline editor, history, editing, autocomplete, wrapping, and rendering. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/fuzzy.lisp` | 134 | 8 | Score and filter fuzzy text matches. | pass | pending evaluation | — | — |
| `src/cadr-tui/input-component.lisp` | 419 | 19 | Implement the grapheme-aware single-line Input component and software cursor. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/input.lisp` | 376 | 17 | Incrementally decode terminal bytes, bracketed paste, and control sequences into input events. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/keybindings.lisp` | 176 | 11 | Store configurable keybinding definitions and resolve conflicts/actions. | pass | pending evaluation | — | — |
| `src/cadr-tui/keys.lisp` | 595 | 32 | Parse and canonicalize Kitty, xterm, modified, and legacy key encodings. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/kill-ring.lisp` | 38 | 5 | Implement kill-ring push/peek/rotate operations. | pass | pending evaluation | — | — |
| `src/cadr-tui/mermaid/ansi.lisp` | 37 | 2 | Render ANSI-colored Mermaid source lines with terminal-safe styles. | pass | pending evaluation | — | — |
| `src/cadr-tui/mermaid/canvas.lisp` | 336 | 34 | Implement the edge-mask raster grid that clips labels and box borders during layout. | pass | pending evaluation | — | — |
| `src/cadr-tui/mermaid/graph.lisp` | 106 | 18 | Define the shared graph model shared by all Mermaid diagram kinds. | pass | pending evaluation | — | — |
| `src/cadr-tui/mermaid/index.lisp` | 111 | 3 | Render the five supported diagram kinds from the shared graph model. | pass | pending evaluation | — | — |
| `src/cadr-tui/mermaid/transform.lisp` | 427 | 30 | Replace top-level mermaid fences using marked 18 fence rules and the Part B renderer. | pass | pending evaluation | — | — |
| `src/cadr-tui/mermaid/labels.lisp` | 334 | 28 | Normalize Mermaid edge/node labels before measurement and drawing. | pass | pending evaluation | — | — |
| `src/cadr-tui/mermaid/layout.lisp` | 1,090 | 36 | Implement the Sugiyama layered-graph layout used by flow diagrams. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/mermaid/layout-seq.lisp` | 254 | 9 | Implement the sequence-diagram layout and lane projection. | pass | pending evaluation | — | — |
| `src/cadr-tui/mermaid/parse.lisp` | 1,180 | 60 | Parse Mermaid source into the shared graph model for all diagram kinds. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/mermaid/source-box.lisp` | 93 | 3 | Fall back to rendering raw Mermaid source in a box when parsing fails. | pass | pending evaluation | — | — |
| `src/cadr-tui/mermaid/width-data.lisp` | 1,008 | 1 | Provide the generated code-point width table consumed by the width engine. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/mermaid/width.lisp` | 72 | 7 | Compute grapheme display width for Mermaid layout and truncation. | pass | pending evaluation | — | — |
| `src/cadr-tui/native-modifiers.lisp` | 78 | 11 | Query Apple Terminal modifier flags through CoreGraphics when supported. | pass | pending evaluation | — | — |
| `src/cadr-tui/overlay.lisp` | 481 | 30 | Resolve overlay geometry, composite frames, and manage overlay focus/stack state. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/package.lisp` | 352 | 1 | Declare the public `cadr-tui` package surface. | pass | pending evaluation | — | — |
| `src/cadr-tui/renderer/alt-screen.lisp` | 424 | 10 | Prepare, crop, render, and restore alternate-screen documents. | pass | pending evaluation | — | — |
| `src/cadr-tui/renderer/lifecycle-input.lisp` | 1,234 | 44 | Own renderer state, lifecycle, viewport, selection, mouse, and input dispatch. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/renderer/main-screen.lisp` | 614 | 16 | Render incremental main-screen frames and manage terminal images. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/renderer/terminal-protocol.lisp` | 73 | 23 | Define the terminal output, cursor, lifecycle, query, and capability protocol. | pass | pending evaluation | — | — |
| `src/cadr-tui/renderer/virtual-terminal.lisp` | 184 | 13 | Implement the deterministic in-memory terminal and screen snapshot. | pass | pending evaluation | — | — |
| `src/cadr-tui/stdin-buffer.lisp` | 229 | 11 | Buffer terminal bytes until complete atomic control/key sequences can be emitted. | pass | pending evaluation | — | — |
| `src/cadr-tui/terminal-colors.lisp` | 191 | 15 | Parse terminal background/color-scheme/cell-size responses. | pass | pending evaluation | — | — |
| `src/cadr-tui/terminal-image.lisp` | 677 | 43 | Detect image capabilities, encode Kitty/iTerm images, inspect dimensions, crop, link, and fall back. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/terminal.lisp` | 882 | 45 | Own the real process terminal lifecycle, raw mode, keyboard protocol, Apple normalization, queries, and progress. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/theme.lisp` | 563 | 37 | Resolve semantic theme colors/styles and terminal color downgrades. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/threads.lisp` | 6 | 1 | Provide bounded cleanup of one SBCL thread. | pass | pending evaluation | — | — |
| `src/cadr-tui/undo-stack.lisp` | 20 | 5 | Implement undo-stack push/pop/clear operations. | pass | pending evaluation | — | — |
| `src/cadr-tui/unicode.lisp` | 1,213 | 49 | Implement terminal Unicode/grapheme/ANSI width, slicing, truncation, and wrapping semantics. | pass · large | pending evaluation | — | — |
| `src/cadr-tui/word-navigation.lisp` | 141 | 8 | Move over whitespace, punctuation, CJK, and editor-atomic word segments. | pass | pending evaluation | — | — |
| `src/cadr-tui/latex.lisp` | 1,913 | 62 | Render basic LaTeX math to terminal-friendly Unicode, ported from the fixed baseline LatexParser. | pass · large | pending evaluation | — | — |

### 2.9 `cadr-core`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-core/atomic-file.lisp` | 106 | 8 | Atomically replace files with durability policy and private-mode enforcement. | pass | no-rewrite | Most-TS spot: plain string errors at :8/:41 instead of typed conditions. Right in Lisp: call-with-X + unwind-protect is the CL idiom, and the zero-dependency base layer deliberately stays below the condition hierarchies that import it. | 20 |
| `src/cadr-core/cancellation.lisp` | 70 | 7 | Own the shared cancellable-state primitive and its thread-safe propagation. | pass | no-rewrite | Most-TS spot: ignore-errors around the user predicate at :21-22. Right in Lisp: the contract is that a failing predicate must never crash the canceller; defstruct+mutex+waitqueue is the native shape. | 20 |
| `src/cadr-core/package.lisp` | 43 | 1 | Declare the public `cadr-core` package surface. | pass | no-rewrite | Most-TS spot: the explicit export list reads like a TS barrel file. Right in Lisp: defpackage is the boundary mechanism — this list is what the 12E-3 leak metric is measured against. | 20 |
| `src/cadr-core/paths.lisp` | 95 | 19 | Own the single user-level path layout consumed by every cadr system. | pass | no-rewrite | Most-TS spot: eleven isomorphic one-line merge-pathnames bodies at :42-84. Right in Lisp: the set is a registry of distinct paths with per-entry provenance comments, one decision owned once — a macro would add indirection without removing a decision. | 20 |
| `src/cadr-core/redacted-print.lisp` | 44 | 6 | Provide the secret-safe print-object registry that keeps credentials opaque everywhere. | pass | no-rewrite | Most-TS spot: hand-rolled replace-all at :22-36. Right in Lisp: cadr-core is the zero-dependency layer, and define-redacted-print-object at :13-20 is the tree-wide model of a machine-enforced benefit. | 20 |
| `src/cadr-core/threads.lisp` | 47 | 2 | Bound cleanup waits and terminate unresponsive workers instead of hanging exit paths. | pass | no-rewrite | Most-TS spot: the catch-all (condition () timed-out) at :19. Right in Lisp: bounded cleanup must never throw, the sentinel disambiguates timeout from result, and keyword outcomes are idiomatic. | 20 |
| `src/cadr-core/time.lisp` | 66 | 5 | Own UTC/ISO time and ID formatting primitives. | pass | needs-rewrite | unix-milliseconds at :5-7 is second-granular (get-universal-time) while named milliseconds; pi Date.now() is real ms, so this is a precision gap vs the baseline. Fix changes observable timestamp/ID precision — needs baseline-locked assertions first (Part K). | 20 |

## 3. Verdict summary and expected distribution

| System | pass | pass · large | should split | should merge | Total |
|---|---:|---:|---:|---:|---:|
| `cadr-agent` | 28 | 13 | 0 | 0 | 41 |
| `cadr-ai` | 46 | 15 | 0 | 0 | 61 |
| `cadr-cli` | 87 | 27 | 0 | 0 | 114 |
| `cadr-core` | 7 | 0 | 0 | 0 | 7 |
| `cadr-evals` | 3 | 5 | 0 | 0 | 8 |
| `cadr-protocol` | 3 | 2 | 0 | 0 | 5 |
| `cadr-server` | 7 | 4 | 0 | 0 | 11 |
| `cadr-storage` | 2 | 0 | 0 | 0 | 2 |
| `cadr-tui` | 30 | 19 | 0 | 0 | 49 |
| **Total** | **213** | **85** | **0** | **0** | **298** |

No production file remains in `should split` or `should merge`. B11 completed the remaining
25 named AI owners after establishing the fixed-baseline provider matrix. This
is not a quota result: every target below names a verified responsibility, and
the tests reject a missing owner or a surviving mixed file.

| System | Failing files | Expected target files | Net files |
|---|---:|---:|---:|
| `cadr-agent` | 0 | 0 | +0 |
| `cadr-ai` | 0 | 0 | +0 |
| `cadr-cli` | 0 | 0 | +0 |
| `cadr-tui` | 0 | 0 | +0 |
| **Total** | **0** | **0** | **+0** |

At current boundaries the physical distribution is 166 files below 300 lines,
81 at 300–699, 28 at 700–999, and 23 at or above 1,000;
only generated `models.generated.lisp` remains at or above 3,000. Average file
size is now 420.0 lines and the under-300 share is about 55.7%. The modest
percentage is honest:
cohesive files such as the multiline
editor, Unicode engine, image codec, protocol codecs, and vendored assets are
not chopped up to make the chart prettier.

### 3.1 Cohesion map for every `should split` file

| Current file | Expected named responsibilities (count) |
|---|---|
| `agent/extensions.lisp` | **Completed in B9:** `extensions/{context,api,registration,snapshot,rendering,providers,commands,lifecycle}.lisp` (8). |
| `agent/loop.lisp` | **Completed in B8:** `loop/{events,tool-execution,turns,agent-loop}.lisp` (4). |
| `agent/session.lisp` | **Completed in B8:** `session/{codec,journal,discovery,migration,export-html}.lisp` (5). |
| `agent/storage.lisp` | **Completed in B8:** `storage/{protocol,memory,harness,jsonl}.lisp` (4). |
| `ai/capabilities.lisp` | **Completed in B10:** `capabilities/{streaming-json,event-stream,grammar-tools,session-resources,proxy-config,image-runtime}.lisp` (6). |
| `ai/http.lisp` | **Completed in B10:** `transport/{http,aws-event-stream}.lisp` (2). |
| `ai/models-runtime.lisp` | **Completed in B10:** `runtime/{models,faux-provider}.lisp` (2). |
| `ai/oauth-flows.lisp` | **Completed in B11:** `oauth/providers/{xai,kimi,github-copilot,openrouter,radius,openai-device,anthropic}.lisp` (7). |
| `ai/oauth.lisp` | **Completed in B11:** `oauth/{pkce,callback,page,openai-anthropic}.lisp` (4). |
| `ai/provider-auth.lisp` | **Completed in B11:** `auth/{bedrock,vertex,device-code,github-copilot,radius-cloudflare}.lisp` (5). |
| `ai/providers/independent.lisp` | **Completed in B11:** `providers/{azure-openai,codex,mistral,vertex,bedrock,pi-messages}.lisp` (6). |
| `ai/registry.lisp` | **Completed in B11:** `providers/{definitions,registry,runtime-projection}.lisp` (3). |
| `ai/utilities.lisp` | **Completed in B10:** `support/{threads,release,retry,token-estimation,overflow,grammar-coercion,uuid}.lisp` (7). |
| `cli/core-support.lisp` | **Completed in B4:** `support/{model-help,event-bus,timings,file-watcher,paths,shell-process}.lisp` (6). |
| `cli/extensions.lisp` | **Completed in B4:** `extensions/{discovery,loader,commands,installer}.lisp` (4). |
| `cli/interactive-components.lisp` | **Completed in B6:** `interactive/components/{loaders,countdown,armin,daxnuts,announcement}.lisp` (5). |
| `cli/interactive-services.lisp` | **Completed in B2:** `interactive/selectors/{common,sessions,tree,settings,auth,models,trust,fork}.lisp` (8); `common` was implemented before the domain extraction. |
| `cli/main.lisp` | **Completed in B5:** `bootstrap/{tools,sessions,settings,auth,commands,main}.lisp` (6). |
| `cli/model-services.lisp` | **Completed in B4:** `models/{auth-storage,store,registry,matching,credential-print}.lisp` (5). |
| `cli/modes/rpc/mode.lisp` | **Completed in B5:** `modes/rpc/{models,prompt-bash,sessions,commands,mode}.lisp` (5). |
| `cli/package-manager.lisp` | **Completed in B4:** `packages/{source,settings,manifest,config-selector,commands}.lisp` (5). |
| `cli/sdk-services.lisp` | **Completed in B4:** `sdk/{cache-version,system-prompt,settings-service,resource-service,model-service}.lisp` (5). |
| `cli/sdk.lisp` | **Completed in B4:** `sdk/{session-manager,agent-session,session-runtime}.lisp` (3). |
| `cli/settings.lisp` | **Completed in B4:** `settings/{config-values,manager,trust}.lisp` (3). |
| `cli/tui.lisp` | **Completed in B6:** `interactive/{state,status,user-bash,transcript,tool-rendering,entries,pending-messages,frame,extension-ui,autocomplete,themes,controller}.lisp` (12); the existing B1 `status` and `transcript` owners absorbed their controller-side responsibilities. |
| `cli/utilities.lisp` | **Completed in B4:** `support/{threads,atomic-write,changelog-share,html,resume-version-git,headers,external-editor}.lisp` (7). |
| `tui/components.lisp` | **Completed in B7:** `components/{markdown,image,tool-block,status,select-list}.lisp` (5). |
| `tui/composition.lisp` | **Completed in B7:** `composition/{protocol,text-box,rich-content,settings-list,loaders,root}.lisp` (6). |
| `tui/renderer.lisp` | **Completed in B7:** `renderer/{terminal-protocol,virtual-terminal,lifecycle-input,main-screen,alt-screen}.lisp` (5). |

## 4. Directory ownership rules

The new hierarchy is semantic, not a mirror of TypeScript:

- `cadr-cli/interactive/` owns interactive-mode state, transcript projection,
  UI services, and the controller.  Its `selectors/` and `components/`
  subdirectories contain independently nameable selector/component families.
- `cadr-cli/modes/` owns non-interactive transport modes; `rpc/` command domains
  stay below it.  Generic settings, packages, models, extensions, and SDK
  services do not live under `interactive/` merely because the TUI calls them.
- `cadr-agent/session/`, `storage/`, `loop/`, and `extensions/` each own one
  agent-domain protocol plus its implementations; backend-specific SQLite stays
  separate from generic storage.
- `cadr-ai/providers/` contains two different but explicit kinds of source:
  declarative provider definitions and one file per wire protocol.  Provider
  brands sharing a protocol remain data rows, not 38 near-empty code files.
  `oauth/providers/` and `auth/` hold genuinely provider-specific behavior.
- `cadr-tui/components/`, `composition/`, and `renderer/` own reusable terminal
  primitives only; coding-agent copy and command behavior stay in `cadr-cli`.
- `cadr-core/` owns only cross-system, product-neutral policy primitives:
  bounded thread cleanup, component-local cancellation, atomic file replacement,
  redacted object printing, and UTC time conversion. Product, provider, session,
  and UI policy must stay in their domain system and consume these primitives.

ASDF files list modules in dependency order: value types/protocols first,
shared helpers next, implementations next, controllers last.  Moving a form
must not create exports merely to compensate for a false directory boundary.

## 5. Required anomaly decisions

### 5.1 `cadr-server`: intentional process boundary, not copied agent logic

The dependency difference is intentional and should remain.

- `cadr-server.asd:5-7` depends on `cadr-ai` only for JSON, HTTP/auth, UUID, and
  Radius primitives.  It does not load an agent or coding session in-process.
- `src/cadr-server/rpc-process.lisp:265-307` starts a child Cadr in RPC mode;
  `supervisor.lisp:259-328` owns only child lifecycle and persisted instance
  metadata.  Agent prompting, tools, session context, and extensions stay in
  that child's `cadr-cli`/`cadr-agent` runtime.
- A full top-level-name comparison found only `current-iso8601` shared with
  `cadr-agent`, and only the generic names `main` and `rpc-command-id` shared
  with `cadr-cli`; there is no duplicated agent/session implementation.
- The extra mass is concrete Cadr server functionality: Radius presence is 744
  lines, RPC child isolation 419, supervision/recovery 609, and Unix-socket IPC
  329.  Calling that duplication would be false.

Therefore the shallower dependency is an intentional implementation difference:
the server is a process supervisor around the already-frozen RPC contract rather
than an in-process coding-agent host.  Adding `cadr-agent` or `cadr-cli` would
collapse the process boundary without removing code and is rejected.

### 5.2 Providers: the headline comparison was apples to half an apple

The draft's `82 files / 2,111 lines` excludes baseline `providers/all.ts` and,
more importantly, excludes all 31 API implementation files.  At fixed baseline
`53fa77ccd` the actual comparison is:

| Surface | Files | Lines | Meaning |
|---|---:|---:|---|
| pi `providers/` excluding `all.ts` | 82 | 2,111 | Brand/model declarations |
| pi `api/` | 31 | 10,566 | Wire protocols, auth transforms, reducers |
| pi combined | 113 | 12,677 | Fair declaration + protocol denominator |
| Cadr `providers/` | 13 | 5,643 | Wire protocols plus validated declaration/registry/runtime projection |
| Cadr `providers/definitions.lisp` declaration rows | 38 rows | 963-file total | Brand/provider data plus field validation |

Cadr has not written twice the provider boilerplate. It does the Lisp-native
thing: 38 brands are validated rows in one `provider-definition` table, while
protocol files implement shared wire behavior. B11 closed the four defects the
audit identified:

1. The six protocols formerly in `providers/independent.lisp` have exact files.
2. Declarations, lookup/construction, and runtime projection have exact files.
3. Provider identity/auth fields and callback strategy identities live in the
   validated declaration; ambient environment names are derived from it.
4. Protocol construction has one branch per declared protocol; the stray
   duplicate Google clause is gone with the retired mixed registry.

The convergence is a validated declarative provider schema that owns names,
login labels/instructions, endpoints, auth methods, environment inputs, and
login/refresh/auth callbacks once.  One runtime constructor consumes it.  Each
wire protocol remains a real file; Cadr must not recreate pi's 82 tiny brand
wrappers merely to resemble TypeScript.

The required divergence safety net is a generated fixed-baseline fixture with
one row per provider and assertions for every field above, plus protocol payload
and event fixtures per `provider × thinking level`.  A row or callback changed
upstream must turn the gate red.

### 5.3 Freeze status

The historical whole-object freeze of `src/cadr-ai` no longer exists: approved
Goal 13 commits changed provider streaming, OAuth, transport, and crash handling.
The active freezes are narrower and still binding:

- extension public export text SHA-256
  `61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`;
- 34-event source block SHA-256
  `12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`;
- public package exports, wire/payload/session contracts, and all observable
  behavior.

Internal file moves in `src/cadr-ai` are therefore eligible, but provider
declaration changes need the baseline-derived field matrix above, and any new
export/event or observable change is blocked for a separate proposal.

## 6. Repeated manual decisions

The threshold is the one from Goal 14: at least three handwritten decisions,
where one omission produces a user-visible defect.  This finds deeper risks
than the file table.

| Decision repeated by hand | Current locations | Failure if one copy drifts | Prior bug | Convergence |
|---|---|---|---|---|
| Bounded thread cleanup | **Converged in B3:** `cadr-core/threads.lisp` owns bounded cleanup; `cli/support/threads.lisp` is a branch-free compatibility delegate and raw active waits require an explicit reason. | Exit hangs, orphaned worker, or forced termination at the wrong time | Goal 13 exit deadlock | Source gates reject unannotated cleanup joins outside the core owner. |
| Cancellation state and propagation | **Converged in B3:** `cadr-core/cancellation.lisp` owns component-local state, abort, predicate adaptation, and bounded waiting; `ai/transport/http.lisp`, `ai/runtime/models.lisp`, `agent/extensions/context.lisp`, `tui/autocomplete.lisp`, and `tui/composition/loaders.lisp` are explicit adapters. Agent lifecycle abort remains a separate product policy. | UI closes while network/listener/tool work continues, or stale work updates a new request | OAuth cancel hang; slow SSE abort; stale autocomplete | Functional tests lock state/wait semantics; a source gate requires every package-boundary adapter to call the core owner. |
| Infrastructure output ownership | **CLI extension side converged in B4 and command/RPC consumers preserved in B5:** `cli/extensions/loader.lisp` owns extension output and infrastructure capture, `bootstrap/commands.lisp` owns frontend mode injection, and `modes/rpc/jsonl.lisp` owns wire emission; process/tool, TUI notice/browser, server Radius, and fatal sinks retain their domain owners. | ASDF, setsid, SSL/SBCL pointers, or internal `session>` labels reach the user channel | setsid, ASDF, SSL, and notice-prefix leaks | Source gates keep each output category with its sink and reject direct JSONL writes from RPC command domains. |
| Selector frame semantics | **Converged in B2:** `cli/interactive/selectors/common.lisp` owns frame sections, semantic borders/titles/input/help, centered viewport/count, and wrap navigation; seven domain owners supply entries and domain callbacks. | One overlay loses cursor, wraps a help glyph, uses the wrong color, spacing, or navigation semantics | Repeated Goal 9 overlay rounds; Goal 14 A0 title/border/cursor | `selector-frame` is the sole shared owner; source gates require every selector family to render through it and delegate wrap navigation. |
| Provider identity/auth metadata | **Converged in B11:** `ai/providers/definitions.lisp` owns 38 validated rows, all static fields, callback strategy identities, and the derived ambient-environment set; `registry.lisp` constructs protocols and `runtime-projection.lisp` consumes the strategies. | Endpoint, login title/instruction, auth source, environment, refresh, or model filtering differs for the same provider | Anthropic generic browser instructions; A0 stored/configured source | The fixed-baseline 38-provider matrix checks every field; source gates reject duplicate/missing rows and mixed legacy owners. |
| Secret-safe object printing | **Converged in B3 and preserved in B4:** `cadr-core/redacted-print.lisp` owns printer declarations; credential-bearing CLI values in `arguments.lisp`, `config.lisp`, `models/auth-storage.lisp`, `models/registry.lisp`, and `interactive/selectors/auth.lisp` use that owner. | A newly printable slot dumps tokens into a condition, crash log, or REPL | Fatal backtrace exposed session state; token non-leak depended on opaque printing | The registry test constructs and prints every declared secret-bearing type with sentinel secrets. |
| Atomic persistence and file modes | **Converged in B3 and preserved in B4:** `cadr-core/atomic-file.lisp` owns replacement and modes; `cli/support/atomic-write.lisp` and `cli/settings/manager.lisp` only select the existing public durability policy. | Torn JSON, refresh-token loss, stale temp files, or world-readable secrets | OAuth refresh/order investigation established atomicity as a hard safety property | Source gates reject handwritten replacement outside the core owner; private auth remains on the shared `0600` path. |
| JavaScript string/byte count semantics | **Converged in B4:** `agent/truncate.lisp` owns UTF-16 code-unit length; `cli/truncation.lisp` is now a direct delegate, while byte/line sizing retains domain adapters. | Tool result counts differ for CJK/emoji or truncation metadata disagrees | Write result counted UTF-8 bytes instead of JS UTF-16 units | B4 rejects a second CLI loop and keeps non-ASCII result fixtures. |
| ISO time and ID formatting | **Bottom-layer conversion exists from B3 and B5 consumes it at the split boundaries:** session export uses `cadr-core:milliseconds-to-utc-iso8601` in `bootstrap/sessions.lisp`; RPC IDs use `cadr-core:unix-milliseconds` in `modes/rpc/jsonl.lisp`.  Package-local compatibility delegates remain where their public semantics differ. | Session discovery, server status, tree labels, or export names drift by timezone/fraction rules | Tree timestamp and export filename parity defects | Fixed vectors guard the core owner; B5 source gates reject restoration of the former cross-package time calls. |

Two apparent repetitions must **not** be collapsed.  Home/path display differs
intentionally between tools, session selector, and tree selector because the
baseline contracts differ; one generic shortening helper would erase those
differences.  Likewise provider protocol implementations should share only
verified wire primitives, not an over-generalized request builder that hides
provider-specific payload semantics.

A small `cadr-core` leaf is the only clean home for SBCL thread cleanup,
cancellation, atomic replace, redacted-printer support, and time formatting:
putting them in `cadr-ai` would break the good `cadr-tui`-does-not-depend-on-AI
boundary.  It adds a shared leaf but no dependency reversal between existing
systems.  Because Goal 14 forbids casual system-graph changes, creating that
leaf is explicitly a Part B decision, not an audit-side implementation.

### Part C B3 implementation status

B3 implemented the approved leaf before any file extraction.  Its modules own
exactly one policy each: `threads` bounds cleanup waits and requires a written
reason for an active unbounded join; `cancellation` owns component-local abort
state and waiting; `atomic-file` owns sibling-temp replacement and explicit
file modes; `redacted-print` owns secret-safe object declarations; `time` owns
UTC millisecond and ISO formatting.  Existing package-local entry points are
compatibility delegates with no policy.  Source gates reject raw production
`join-thread`, handwritten replacement rename, and direct secret-bearing
`print-object` definitions outside these owners.

The remaining repeated decisions keep their approved order: B1 names output
ownership before extracting presentation leaves; B2 establishes
`selector-frame` before extracting selector families; B4 converges CLI sinks
and the duplicate JavaScript metric before service extraction; B5--B10 consume
those owners before their splits; B11 created the fixed-baseline provider
matrix before the declaration owner and provider file split.

### Part C B1 implementation status

B1 extracted only the eight cohesive interactive leaves.  Transcript projection,
status/startup projection, footer/Git data, theme resolution, image processing,
clipboard access, syntax highlighting, and tool-render session state now each
have one exact file owner under `src/cadr-cli/interactive/`.  The move preserved
the existing package-private symbols and introduced no alternate sink, export,
callback, or visible byte.

This batch deliberately left every selector in `interactive-services.lisp`.
Splitting those state machines before their common frame existed would have
copied the same border/title/input/count/help/navigation decisions into eight
files.  B2 therefore begins by making `selector-frame` the sole owner of those
decisions and only then extracts the selector families.  `images.lisp` loads
before `clipboard.lisp` because clipboard image acquisition consumes the shared
image result and processing functions; all other leaf owners load before the
remaining selector consumer file.

### Part C B2 implementation status

B2 first established `interactive/selectors/common.lisp` as the sole owner of
selector chrome, viewport/count placement, input, help rows, and bidirectional
wrap navigation.  Only after the frame behavior gate was red did the seven
domain selector owners move out of `interactive-services.lisp`.  Existing
overlay and base-screen bytes stayed unchanged.

### Part C B4 implementation status

B4 completed all eight approved CLI service splits.  The proposal's prose said
"36 files", but its explicit cohesion map names 37 responsibilities
(`6 + 7 + 3 + 5 + 4 + 4 + 5 + 3`); the implementation follows the approved
named boundaries rather than hiding one owner to satisfy the arithmetic typo.

Convergence preceded extraction.  `cadr-agent/truncate.lisp` became the single
implementation of JavaScript UTF-16 code-unit length before the CLI adapter
moved.  The existing extension user-output sink and infrastructure-capture
boundary moved together into `extensions/loader.lisp`; settings/auth writes
continue through `cadr-core` atomic replacement, and all credential-bearing
objects continue through the shared redacted-printer declarations.  The 37
new files preserve the old top-level forms and package-private names; only ASDF
ownership and the eliminated duplicate UTF-16 loop changed.

### Part C B5 implementation status

B5 split the 64 definitions formerly in `main.lisp` across six bootstrap
owners, and the 36 RPC definitions across five command-domain owners.  The
process entrypoint and RPC loop are now thin lifecycle boundaries; tool,
session, settings, authentication, command, model, prompt/bash, and RPC session
responsibilities live in files whose names predict their contents.

Convergence happened at the split boundary.  CLI commands still inject exactly
one `frontend-output` sink, every RPC domain emits only through
`rpc-write-object`, session-export timestamps call the B3 UTC formatter
directly, and RPC IDs call the B3 millisecond clock directly.  The split kept
all 100 top-level definitions and the public package text unchanged.

### Part C B6 implementation status

B6 removed both interactive monoliths only after the B2 selector frame, B4
output sinks, and B3 cleanup policy were available.  State records load first;
entry/status/transcript/tool reducers and extension bridges load next; frame,
autocomplete, theme watching, and the controller load in dependency order.
The two existing B1 owners, `status.lisp` and `transcript.lisp`, absorbed their
matching controller-side forms instead of creating duplicate owners.

The five independent component families now have exact files, while the live
controller keeps only lifecycle and input/command routing.  All 224 top-level
definitions moved without renaming, public package text stayed byte-identical,
and source gates reject either legacy monolith or a second selector/output/
cleanup policy.

### Part C B7 implementation status

B7 moved the 288 existing reusable-TUI definitions into sixteen exact owners.
Component protocols load before concrete composition methods; terminal
protocols and the virtual terminal load before lifecycle/input and the two
screen renderers.  The loader owner delegates cancellation and bounded thread
cleanup to the B3 primitives instead of reintroducing either policy.

No definition was renamed and `src/cadr-tui/package.lisp` remained
byte-identical, so the public export set is frozen.  Full-screen, overlay,
mouse, scroll, performance, and fresh-compile gates protect the unchanged
observable behavior while organization tests reject all three legacy
monoliths and any dependency-unsafe ASDF order.

### Part C B8 implementation status

B8 moved all 251 session, storage, and loop definitions into thirteen exact
owners. Session codecs precede journals, migration, discovery, and export;
storage protocols precede memory, harness, JSONL, and SQLite backends; loop
events and tool execution precede turns and public agent-loop entrypoints.
The split preserves the B3 UUID/time and atomic-replacement owners and adds no
alternate persistence or retry policy.

All three legacy monoliths are gone. The sorted definition set, public package
text, session bytes, tool results, event/wire output, and screen snapshots are
unchanged. The Goal 11 stability provenance now hashes the exact session codec
owner so the verification gate cannot silently follow a deleted aggregate.

### Part C B9 implementation status

B9 moved all 239 extension-host definitions into eight exact owners: context,
API value/event handling, registration, immutable snapshots, rendering,
provider/tool projection, commands/templates, and lifecycle dispatch. The ASDF
order follows those dependencies; no symbol was renamed and the legacy
monolith is gone.

The B3 cancellation owner still drives context abort state, and rendering still
emits through the injected extension notification sink. The public extension
export block and the 34-event source block remain byte-identical at SHA-256
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`
and `12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.

### Part C B10 implementation status

B10 moved all 229 definitions from four mixed AI files into seventeen exact
owners. Streaming JSON, event streams, grammar tools, session resources, proxy
configuration, and image runtime are separate capabilities; native HTTP and
AWS framing are separate transports; model/auth runtime and faux behavior are
separate runtime owners; release, retry, estimation, overflow, coercion, UUID,
and the B3 thread delegate are separate support owners.

The split is structural only. HTTP and model cancellation still consume the B3
core owner, SSE retains an explicit unbounded read timeout, network failures
retain the canonical `fetch failed` boundary, and the public `cadr-ai` package
text remains byte-identical at SHA-256
`e722e49fd70592edcd28da93acc97051d4a0b22bc016e4b7da314a65c4acfb4f`.

### Part C B11 implementation status

B11 retired the five mixed provider/authentication owners and replaced them
with 25 exact owners. OAuth primitives, callback/page handling, each bundled
OAuth provider, each authentication mechanism, six independent wire protocols,
provider declarations, protocol construction, and runtime projection now have
predictable files loaded in dependency order.

Convergence preceded extraction. The committed fixture generated from pi
baseline `53fa77ccd8a279eb87e92294ef3687b03ff80112` records all 38 providers and
every declaration field with `file:line` provenance. The validated declaration
is now the only owner of static provider identity/auth fields and callback
strategy identities; the ambient environment list is derived from those rows.
The public package text remains byte-identical at SHA-256
`e722e49fd70592edcd28da93acc97051d4a0b22bc016e4b7da314a65c4acfb4f`.

### Already-converged examples to preserve

- A0 now gives authentication overlays and Input components ownership of their
  own semantics instead of patching call sites.
- `model-registry-authentication-status` is the single producer of the live
  provider-status source.
- `call-with-fatal-condition-boundary` and credential `print-object` methods are
  the current top-level crash safety boundary.
- `call-with-normalized-file-operation` owns built-in file-tool condition copy.

These are design assets.  Splitting files must not duplicate their decisions
back into the new modules.

### Part L upgrade routing (v0.84.1, goal 18 runbook step 10)

Goal 18 Part L upgraded the fixed baseline from `74caa2649` to `53fa77ccd`
(v0.84.1). This subsection is the required retrospective on how the §1a
package boundary map survived that upgrade.  All numbers below were
re-derived from `git diff --name-status` between the two commits on the
baseline object (2026-08-12), not taken from the hand-written upgrade table;
the hand count of "248 non-test source files" is superseded by the mechanical
count of **257** files under `packages/*/src` (228 modified/added/deleted plus
29 in the `storage` → `session-backends` rename).

#### Hit rate of the §1a first-pass router

| Baseline area | Changed src files | Route taken |
|---|---:|---|
| `coding-agent/src/core` | 25 | `cadr-agent` (rule hit) |
| `coding-agent/src/modes` | 18 | `cadr-cli` (rule hit) |
| `coding-agent/src/cli` | 13 | `cadr-cli` (rule hit) |
| `coding-agent/src/extensions` | 2 | `cadr-agent` (rule hit) |
| `ai/src` | 50 | `cadr-ai` (rule hit) |
| `agent/src` top-level | 5 | `cadr-agent` (rule hit) |
| `tui/src` | 22 | `cadr-tui` (rule hit) |
| `server/src` | 28 | `cadr-server` (rule hit) |
| `protocol/src` | 1 | `cadr-protocol` (rule hit) |
| `storage` → `session-backends` | 29 | `cadr-storage` + `cadr-agent` (pre-mapped in §1a) |
| `coding-agent/src/utils` | 7 | per-function split; see below |
| `coding-agent/src/client` + top-level `main/rpc/cli/index/package-manager-cli` | 8 | `cadr-cli` after reading each file |
| `agent/src/harness` | 32 | test-support, routed to cadr-evals harness fixtures, not product code |
| `client/src` | 10 | no cadr counterpart; adjudicated `intentional difference` |
| `telemetry/src` | 6 | no cadr counterpart; adjudicated `intentional difference` |

The rule classified **193 of 257 files** (75%) without reading them.  The
`coding-agent` core/modes refinement predicted exactly the 74 changed
`coding-agent` files the §1a text promised, which is the strongest hit-rate
signal: the boundary was written before the upgrade and survived it
byte-for-byte at the file level.

#### Where the rule needed a human

1. **`agent/src/harness` (32 files, the largest churn)** — harness v2 is
   test-support, not product code.  The §1a map has no row for it; the
   routing decision was to treat it as behavior, not source: cadr's
   harness/conformance equivalents live under `cadr-evals` and
   `test/fixtures/`, verified by the behavioral gates, and the files were not
   ported 1:1.  This is the honest "rule gap" of the upgrade: a future
   baseline change under `agent/src/harness` should be pre-routed the same
   way instead of re-litigated.
2. **`coding-agent/src/utils` (7 files)** — mixed destinations by function
   (abort/error text → cadr-core or cadr-agent, UI helpers → cadr-cli).
   Each needed a read.  This is the only repeated judgment in the upgrade;
   the decisions are recorded in the ledger rows.
3. **`server/src` rewrite (28 files)** — the legacy server was replaced
   (−1974/+2290), so "route to cadr-server" was a destination but not a
   mapping; the per-file judgment was which endpoint/transport behavior the
   cadr-server files should absorb.  The §1a map's "product boundary, not
   copied agent logic" anomaly (§5.1) absorbed this without a new decision.
4. **`client/src` and `telemetry/src` (16 files)** — genuinely new baseline
   packages with no cadr counterpart.  Adjudicated as `intentional difference` (client:
   remote-session transport folded into cadr-cli; telemetry: contracts-only
   package with no network egress and zero imports, deliberately not ported).

#### Hotspot files and their cadr destinations

The top ten by absolute churn: `agent/src/harness/agent-harness.ts` (1,511),
`tui/src/latex.ts` (1,373, new), `tui/src/tui-alt-screen.ts` (1,047, new),
`agent/src/harness/session/testing/conformance.ts` (993),
`session-backends/.../sqlite/repo.ts` (958),
`agent/src/harness/reducer.ts` (667), `agent/src/harness/types.ts` (655),
`agent/src/harness/telemetry.ts` (615),
`coding-agent/src/modes/interactive/interactive-mode.ts` (596),
`ai/src/models.ts` (451).

- `latex.ts` → `src/cadr-tui/latex.lisp` (new owner, preflighted per §7
  "Future goal preflight": stated owner, reused existing markdown pipeline).
- `tui-alt-screen.ts` and the `TuiAltScreen.ts` deletion → existing
  `cadr-tui` alt-screen owners; no new boundary was needed for the rewrite.
- `interactive-mode.ts` stayed the single largest `coding-agent` hotspot, and
  cadr's `interactive/controller.lisp` remains its counterpart.  Part L did
  **not** split it further; the preflight rule defers re-organization to a
  goal whose charter is ownership, and the ledger already records the
  controller as a stable owner.

#### Verdict

The §1a map was the right tool and it worked: 77% mechanical routing, the
`coding-agent` split exact, and every genuinely new package either landed in
a pre-existing owner or was adjudicated.  The two things to carry forward are
the `agent/src/harness` test-support route (add it to the map) and the
`coding-agent/src/utils` per-function split (the only recurring manual
judgment; it is a candidate for a future B-batch convergence).

## 7. Permanent organization gate

`scripts/check-code-organization.py` scans every regular production file below
`src/`.  Part A's complete histogram placed 23 of 296 files in a distinct
`>=1000`-line band above the 700--999 band, so that audited band is the review
boundary.  The number is not a target: a cohesive 999-line file is not thereby
good, and a justified 1000-line file is not thereby bad.

Every file at or above that boundary must have a non-empty, path-specific
reason in `docs/code-organization-exemptions.json`.  The gate rejects an
unreviewed large file, a missing or duplicate reason, and a stale exemption for
a file that moved, disappeared, or fell below the boundary.  The checked-in
manifest currently contains the exact 23 files at or above the boundary, including generated
and vendored assets.  `scripts/verify.sh` drives both synthetic regressions and
the real repository/manifest pair before the parity and build stages.

This is a **symptom detector only**.  Passing it does not prove good ownership,
and failing it means "review and explain the boundary", not "split until the
number is green".  Repeated policy is the deeper failure mode, so the following
behavior and anti-bypass tests are the stronger permanent controls:

| Converged decision | Policy owner | Permanent behavior / anti-bypass gate |
|---|---|---|
| Bounded thread cleanup | `cadr-core/threads.lisp` | `bounded-thread-cleanup-times-out-and-makes-active-unbounded-waits-explicit`; `production-cleanup-joins-cannot-bypass-cadr-core` |
| Cancellation state and propagation | `cadr-core/cancellation.lisp` | `cancellation-state-is-local-external-waitable-and-thread-safe`; `production-cancellation-adapters-cannot-bypass-cadr-core` |
| Infrastructure output ownership | domain sinks, with CLI extension capture in `extensions/loader.lisp` and RPC wire output in `modes/rpc/jsonl.lisp` | `goal14-b4-converges-sinks-and-javascript-length-before-split`; `goal14-b5-converges-mode-output-and-time-before-split` plus existing user-channel diagnostic regressions |
| Selector frame semantics | `interactive/selectors/common.lisp` | `goal14-b2-selector-frame-owns-shared-selector-decisions`; `goal14-b2-selector-frame-wraps-and-centers-independently` |
| Provider identity/auth metadata | `cadr-ai/providers/definitions.lisp` | `goal14-provider-matrix-is-fixed-baseline-derived-and-complete`; `goal14-every-provider-definition-field-matches-fixed-baseline-matrix`; one-owner source gates |
| Secret-safe object printing | `cadr-core/redacted-print.lisp` | `redacted-object-declaration-registers-type-and-never-prints-secret`; `atomic-replacement-and-secret-printers-have-one-policy-owner` plus the credential-type registry test |
| Atomic persistence and file modes | `cadr-core/atomic-file.lisp` | `atomic-replacement-preserves-old-content-on-error-and-private-mode`; `atomic-replacement-and-secret-printers-have-one-policy-owner` |
| JavaScript UTF-16 count semantics | `cadr-agent/truncate.lisp` | `goal14-b4-converges-sinks-and-javascript-length-before-split` plus non-ASCII write/truncation fixtures |
| ISO time and ID formatting | `cadr-core/time.lisp` | `utc-time-primitives-match-fixed-baseline-vectors`; `goal14-b5-converges-mode-output-and-time-before-split` |

### Future goal preflight

Every future goal that adds production code must state before implementation:

1. the directory and named owner for the new code, using section 4;
2. which existing primitive or domain policy it reuses;
3. if none applies, why the new decision is genuinely distinct rather than a
   convenient second implementation.

The review must consider repeated decisions even when every touched file is
below the line threshold.  New files belong where responsibility is owned, not
where the current caller happens to be easiest to edit.

## 6. Package-boundary leak baseline (goal 20, item 12E-3)

`cadr-ai::` double-colon references from outside `src/cadr-ai/` are a
compile-time declaration of "I depend on your internals"; the export list
is therefore not the real API surface. The advisor ruling (2026-08-15)
defers the ratchet gate until Part K closes — Part K restructuring moves
the count in both directions, and a monotone constraint mid-refactor
would manufacture false reds. Until then this section carries the
baseline and the trend.

Measured 2026-08-15 (HEAD `1aa4e9b1a`):

| Metric | Value |
|---|---:|
| `cadr-ai::` occurrences outside `src/cadr-ai/` | 890 |
| Distinct files containing them | 98 |
| Distinct internal symbols referenced | 64 |

Reproduce:

```sh
grep -roE 'cadr-ai::[A-Za-z0-9*+<>=/_-]+' src --include='*.lisp' | grep -v '^src/cadr-ai/' | wc -l   # occurrences
grep -rlE 'cadr-ai::' src --include='*.lisp' | grep -v '^src/cadr-ai/' | wc -l                     # files
grep -rlE 'cadr-ai::' src --include='*.lisp' | grep -v '^src/cadr-ai/' \
  | xargs grep -hoE 'cadr-ai::[A-Za-z0-9*+<>=/_-]+' | sort -u | wc -l                              # symbols
```

Cadence (per the ruling): recompute all three at each Part K close and
append one row below — visibility and history first, constraint
direction second. The ratchet proposal returns at Part K close with this
trend line attached.

| Date | HEAD | Occurrences | Files | Symbols | Note |
|---|---|---:|---:|---:|---|
| 2026-08-15 | `1aa4e9b1a` | 890 | 98 | 64 | baseline |
