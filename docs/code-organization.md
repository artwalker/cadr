# Code organization ledger

<!-- GOAL20_LISPIFICATION_LEDGER baseline=13cbf77df2396303013a41646bcfa77b4271ae56 files=299 lines=128867 assets=5 unevaluated=0 needs-rewrite=0 no-rewrite=147 in-progress=0 done=152 -->

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
goal is supposed to police, so this ledger covers all 299 current files.

- 293 Lisp files, 121,105 lines, 4,976 top-level definitions.
- 5 static export assets, 4,275 lines.
- 299 production files and 125,380 physical lines in total.
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
| `src/cadr-agent/branch-summarization.lisp` | 185 | 11 | Prepare a session branch and ask the model for its branch summary. | pass | done | llm-passthrough-message-p / agent-message-to-llm. I0: one passthrough owner. | 20 |
| `src/cadr-agent/summarization.lisp` | 86 | 4 | Own the shared conversation-summary prompt, request, and retry contract. | pass | no-rewrite | The or/progn nil-witness at :48-61 distinguishes nil-return from abort at an external boundary; retry/cache/routing already single-owned via closure injection. | 20 |
| `src/cadr-agent/compaction.lisp` | 883 | 35 | Estimate context, choose a cut point, and execute the compaction lifecycle. | pass · large | done | one reverse walk; compaction-field. I0: one extension-vs-generated pick. compact-from-preparation is in-memory compact(). | 20 |
| `src/cadr-agent/conditions.lisp` | 43 | 9 | Define agent-layer condition types. | pass | no-rewrite | The condition hierarchy IS the Lisp mechanism; slotted conditions carry payload and messages live at signal sites, consumed via handler-case. | 20 |
| `src/cadr-agent/execution-env.lisp` | 855 | 56 | Implement the replaceable filesystem/process execution environment used by tools and harnesses. | pass · large | done | call-signaled-operation. I0: abort/classify one owner. | 20 |
| `src/cadr-agent/export-html/template.css` | 1,066 | 0 | Provide the exact vendored baseline stylesheet embedded in offline session exports. | pass · large | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/export-html/template.html` | 55 | 0 | Provide the exact HTML shell embedded in offline session exports. | pass | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/export-html/template.js` | 1,864 | 0 | Provide the exact vendored baseline browser renderer embedded in session exports. | pass · large | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/export-html/vendor/highlight.min.js` | 1,212 | 0 | Vendor the approved Highlight.js browser asset byte-for-byte. | pass · large | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/export-html/vendor/marked.min.js` | 78 | 0 | Vendor the approved Marked browser asset byte-for-byte. | pass | n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |
| `src/cadr-agent/extensions/api.lisp` | 369 | 31 | Validate active APIs, copy extension values, and project event payloads/results. | pass | no-rewrite | Bare forwarders at :322-338 are the curated public surface over the deliberate %-internal conc-name; validation enforces the baseline clone/error contract via conditions. | 20 |
| `src/cadr-agent/extensions/commands.lisp` | 296 | 11 | Invoke extension commands and expand registered prompt templates. | pass | no-rewrite | (nth (1- index) arguments) at :67 is the baseline $N positional contract over one command line; scanners are zero-copy and grammar-locked. | 20 |
| `src/cadr-agent/extensions/context.lisp` | 707 | 77 | Define extension host/context state, cancellation, and all context/UI actions. | pass · large | done | assert-extension-deliver-as. I0: one deliver-as owner. | 20 |
| `src/cadr-agent/extensions/lifecycle.lisp` | 779 | 18 | Validate, merge, and dispatch the complete frozen extension lifecycle. | pass · large | no-rewrite | Fresh-cons getf-sentinel idiom (7x) is the aliasing-safe way to preserve the baseline absent-vs-NIL key contract; one cond owns the per-event result contract. | 20 |
| `src/cadr-agent/extensions/providers.lisp` | 524 | 21 | Project extension tools, messages, and session-local provider overlays into an agent. | pass | no-rewrite | Six default-install blocks at :143-178 differ in signature and target; a thunk table adds indirection without removing a decision. | 20 |
| `src/cadr-agent/extensions/registration.lisp` | 819 | 53 | Define bundles, registries, frozen events, and extension authoring macros. | pass · large | done | register-* owns &key; define-* keeps Goal 12 frozen lists. I0: one implementation owner. | 20 |
| `src/cadr-agent/extensions/rendering.lisp` | 256 | 18 | Own extension failure notices, Markdown/message/tool rendering, and shortcuts. | pass | done | render-extension-named. I0: one named-renderer apply. | 20 |
| `src/cadr-agent/extensions/snapshot.lisp` | 397 | 24 | Build immutable extension snapshots and replace active bundles safely. | pass | done | extension-definition-bundle generic. I0: new type is a method. | 20 |
| `src/cadr-agent/file-mutation-queue.lisp` | 92 | 11 | Serialize mutations to the same resolved file. | pass | done | with- macro over call-with-file-mutation-queue. I0: ticket lock without lambda. | 20 |
| `src/cadr-agent/harness-events.lisp` | 75 | 8 | Define the harness run lifecycle event bus: run-start/run-end events, typed subscriptions, and buffered watch. | pass | done | push / nreverse on watch flush. I0: record is O(1). | 20 |
| `src/cadr-agent/loop/agent-loop.lisp` | 442 | 8 | Own the public prompt/steer/follow-up entrypoints and outer agent lifecycle. | pass | done | early terminal exit. I0: no cond pyramid. | 20 |
| `src/cadr-agent/loop/events.lisp` | 169 | 17 | Emit and normalize agent lifecycle, stream, queue, and tool events. | pass | no-rewrite | The tail-cons append cache at :131-164 is the parity-required O(1) queue idiom; vector-push-extend at :113 proves it was a deliberate interop choice. | 20 |
| `src/cadr-agent/loop/tool-execution.lisp` | 489 | 19 | Execute tool batches with hooks, restarts, termination, updates, and abort state. | pass | done | map-into. I0: no index+aref fill. | 20 |
| `src/cadr-agent/loop/turns.lisp` | 393 | 15 | Prepare, stream, retry, compact, and finalize one agent turn. | pass | done | abort-p keyword. I0: no one-field plist. | 20 |
| `src/cadr-agent/messages.lisp` | 253 | 26 | Convert agent-specific message envelopes and file-operation summaries to model-facing messages. | pass | done | agent-message-to-llm generic. I0: unmatched types drop in one method. | 20 |
| `src/cadr-agent/package.lisp` | 456 | 1 | Declare the public `cadr-agent` package surface. | pass | no-rewrite | The flat export list is CL's only wildcard-free contract form; zero logic to Lisp-ify. | 20 |
| `src/cadr-agent/proxy.lisp` | 251 | 9 | Translate proxy-provider events into native agent stream events. | pass | done | nappend-string. I0: deltas are amortized linear. | 20 |
| `src/cadr-agent/resources.lisp` | 739 | 30 | Load, validate, substitute, and format prompts and skills as agent resources. | pass · large | no-rewrite | Post-12F-4 the frontmatter pop-iterates; the remaining hand index loop at :380-452 is the documented single-pass no-reexpansion contract over strings. | 20 |
| `src/cadr-agent/runtime.lisp` | 421 | 30 | Own agent event emission, queued steering/follow-up input, mutation state, abort, and shutdown. | pass · large | done | agent-queue-messages / set-agent-queue-messages. I0: one queue slot owner. | 20 |
| `src/cadr-agent/schema.lisp` | 850 | 22 | Validate JSON Schema definitions and tool arguments with local reference support. | pass · large | done | with-present. I0: one present-p guard. | 20 |
| `src/cadr-agent/session/codec.lisp` | 1152 | 47 | Encode, decode, validate, and identify session entries and metadata. | pass | done | typed session-file-header. I0: one coerce owner. | 20 |
| `src/cadr-agent/session/discovery.lisp` | 154 | 5 | Discover, list, continue, and resolve session files. | pass | no-rewrite | The octet loop at :41-77 implements the byte-counted 1MiB scan cap with mid-line cutoff and per-line :skip — inexpressible with read-line. | 20 |
| `src/cadr-agent/session/export-html.lisp` | 455 | 24 | Embed assets and export a session as baseline-compatible offline HTML. | pass | no-rewrite | String-keyed color alists at :46-152 must stay string-keyed (camelCase CSS vars are the byte contract); hand-rolled base64 honors the no-new-deps policy. | 20 |
| `src/cadr-agent/session/journal.lisp` | 679 | 33 | Create, append, branch, label, and inspect the live JSONL session journal. | pass | done | binary journal fd + reused octet buffer. I0: one details/usage emit. | 20 |
| `src/cadr-agent/session/migration.lisp` | 2185 | 42 | Validate and migrate v1/v2/v3 session logs with atomic replacement. | pass | done | SCAN-KEY/PARSE-STRING skip quote via two ub32 haszero. Load indexes a simple-vector of parsed records. I0: intern once. | 20 |
| `src/cadr-agent/sqlite-storage.lisp` | 834 | 33 | Implement the SQLite session-storage and repository backend. | pass · large | done | one model/level bind; model-plist-from-entry. I0: one current-model owner. | 20 |
| `src/cadr-agent/storage/harness.lisp` | 476 | 31 | Adapt session-storage backends to harness session lifecycle operations. | pass | done | model-plist-from-entry. I0: same current-model owner as sqlite. | 20 |
| `src/cadr-agent/storage/jsonl.lisp` | 536 | 21 | Implement JSONL session storage and repository backends. | pass | no-rewrite | Manual path joining at :315-352 is required — execution-env paths are opaque possibly-non-local strings and the filename encoding is the byte contract. | 20 |
| `src/cadr-agent/storage/memory.lisp` | 378 | 20 | Implement in-memory session storage and repository backends. | pass | done | tail pointer. I0: O(1) append like journal. | 20 |
| `src/cadr-agent/storage/protocol.lisp` | 142 | 25 | Define storage/repository metadata, generic protocols, and shared errors. | pass | no-rewrite | ensure-session-metadata (:40-53) is the single owner of default construction; the file is otherwise the defgeneric protocol all backends specialize. | 20 |
| `src/cadr-agent/tool.lisp` | 319 | 23 | Define tool registry, execution bindings, validation, and prepared outcomes. | pass · large | done | drop (or content nil). I0: TS ?? is identity. | 20 |
| `src/cadr-agent/truncate.lisp` | 554 | 35 | Implement baseline-compatible bounded head/tail/line truncation and its result contract. | pass | no-rewrite | Post-12F-1 the core is zero-alloc; the 11 forwarders at :28-62 are the exported API surface over the single-owning struct; line semantics match split("\n"). Head/tail now scan indices instead of split-string. Head and tail ASCII-run fill plus exact copy. | 20 |

Part K6 (2026-08-18): 23 needs-rewrite rows done. 14 no-rewrite
kept. Report: `docs/acceptance/goal-v20-part-k6.md`.

### 2.2 `cadr-ai`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-ai/auth.lisp` | 207 | 17 | Serialize, atomically persist, redact, and refresh provider credentials. | pass | done | +oauth-reserved-credential-keys+. I0: one reserved-key list. | 20 |
| `src/cadr-ai/capabilities/event-stream.lisp` | 69 | 6 | Implement the producer/consumer event stream and terminal-result protocol. | pass | done | queue-tail. I0: FIFO is O(1). | 20 |
| `src/cadr-ai/capabilities/grammar-tools.lisp` | 292 | 19 | Resolve deferred tools and strict/grammar constrained-sampling metadata. | pass | done | keyed-collection-value. I0: one hash-or-plist lookup. | 20 |
| `src/cadr-ai/capabilities/image-runtime.lisp` | 117 | 18 | Register image APIs and own the mutable image provider/model runtime. | pass | no-rewrite | append-to-end at :41 is a cold path bounded by provider count; the catch-all at :100-117 is the baseline-mandated error-object contract via handler-case. | 20 |
| `src/cadr-ai/capabilities/proxy-config.lisp` | 77 | 5 | Resolve HTTP proxy and NO_PROXY policy for target URLs. | pass | no-rewrite | Cascaded and-checks at :14-23 mirror TS ?. chains, but proxy selection and error text are baseline-observable; explicit position arithmetic matches pi without a new dep. | 20 |
| `src/cadr-ai/capabilities/session-resources.lisp` | 34 | 5 | Register and clean session-owned provider transport resources. | pass | no-rewrite | Module-level registry at :5-7 is genuinely process-global; mutex-scoped snapshot and per-cleanup handler-case already Lisp-shaped. | 20 |
| `src/cadr-ai/capabilities/streaming-json.lisp` | 162 | 11 | Provide stable JavaScript-compatible hashes and repair partial streaming JSON. | pass | no-rewrite | Manual index loop at :76-107 is forced by the 6-char \uXXXX lookahead and the JS-semantics hash contract; case/format/handler-case used where Lisp helps. | 20 |
| `src/cadr-ai/conditions.lisp` | 44 | 12 | Define provider-layer condition types. | pass | no-rewrite | retryable-p slot mirrors a JS flag, but the hierarchy with message-only :report is the Lisp-native replacement for instanceof chains and matches String(err) output. | 20 |
| `src/cadr-ai/crash.lisp` | 255 | 16 | Redact secrets and report fatal conditions through a private crash-log boundary. | pass | done | SBCL-only fatal boundary. I0: no #-sbcl copy. | 20 |
| `src/cadr-ai/crypto.lisp` | 367 | 14 | Implement SigV4 canonicalization/signing and service-account JWT signing. | pass · large | no-rewrite | Manual pad loop at :37-40 is RFC 2104 test-vector locked; the unwind-protect FFI ladder is canonical CFFI and openssl-check owns return-code checking. | 20 |
| `src/cadr-ai/image-models.generated.lisp` | 185 | 1 | Hold generated image-model catalog data. | pass · large | no-rewrite | Generated artifact pinned to the baseline catalog; the -1000000.0d0 price sentinels are data, not code shape. | 20 |
| `src/cadr-ai/images.lisp` | 222 | 8 | Build OpenRouter image requests and normalize generated-image results. | pass | no-rewrite | Tail-append at :142-145/:156-160 preserves the baseline-mandated block order on a wire-bounded list; failure mapping uses the condition system. | 20 |
| `src/cadr-ai/json.lisp` | 1905 | 41 | Parse and serialize bounded JSON plus common content/data-URL helpers. | pass · large | no-rewrite | ASCII octet windows copy as ub32 schar stores. UTF8-STRING reuses that copy for ASCII runs and decodes non-ASCII scalars. Optional START/END decode one slice. Key windows compare as ub32 chunks. Index-walking number DFA transcribes RFC 8259; integers parse from the source window; one-element arrays skip the list+coerce path. Exact-rational round-trip is a genuine Lisp advantage TS doubles cannot express. Interned key lookup dispatches on first character; unescaped ASCII windows are one typed copy; escaped octet windows decode without PARSE-JSON-SOURCE; objects stack ≤8 pairs then allocate `:size` count; PARSE-STRING defers base-p to the copy path. | 20 |
| `src/cadr-ai/model-data.lisp` | 407 | 27 | Validate model-data artifacts/manifests and generate deterministic catalog fixtures. | pass · large | done | walk-model-data-groups. I0: one group walker. | 20 |
| `src/cadr-ai/models.generated.lisp` | 8,711 | 1 | Hold the generated model metadata catalog; the generator is its owner. | pass · large | no-rewrite | Generated data artifact (1219 entries, one uniform schema); shape changes belong to the generator, not this file. | 20 |
| `src/cadr-ai/models.lisp` | 288 | 22 | Define model metadata/catalog operations, thinking-level resolution, and cost calculation. | pass | no-rewrite | nth-on-list at :216-226 is over a fixed 7-element ordinal constant and directly expresses the baseline nearest-level search; rest is defstruct+registry+conditions. | 20 |
| `src/cadr-ai/oauth/callback.lisp` | 324 | 12 | Parse manual/callback authorization input and own the loopback callback lifecycle. | pass | done | oauth-callback-provider-key. I0: one display-name map. | 20 |
| `src/cadr-ai/oauth/openai-anthropic.lisp` | 304 | 13 | Exchange, refresh, and orchestrate the browser OAuth flows shared by OpenAI Codex and Anthropic. | pass | done | login-pkce-browser-oauth. I0: one PKCE+browser flow. | 20 |
| `src/cadr-ai/oauth/page.lisp` | 149 | 6 | Render the branded OAuth callback success and error pages. | pass | done | oauth-callback-provider-key. I0: same display-name owner as callback. | 20 |
| `src/cadr-ai/oauth/pkce.lisp` | 322 | 36 | Own OAuth metadata plus the SHA-256, Base64URL, PKCE, state, and authorization-URL primitives. | pass | no-rewrite | Hand-indexed SHA-256 at :165-195 is spec-locked 32-bit arithmetic; dep policy bars ironclad, so test-vector transcription is correct. | 20 |
| `src/cadr-ai/oauth/providers/anthropic.lisp` | 16 | 1 | Project the Anthropic browser OAuth flow into the runtime callback contract. | pass | no-rewrite | 16-line adapter; closure wrappers at :7-16 are precisely the seam keeping the login flow decoupled. | 20 |
| `src/cadr-ai/oauth/providers/github-copilot.lisp` | 174 | 15 | Implement GitHub Copilot device login, token exchange, refresh, and model filtering. | pass | no-rewrite | RFC 8628 code lists at :117-118 are wire tokens; the single-owner fix belongs to oauth-poll-token defaults, not this file. | 20 |
| `src/cadr-ai/oauth/providers/kimi.lisp` | 58 | 6 | Implement Kimi Coding device login and credential refresh. | pass | no-rewrite | Poll vocabulary at :43-44 is wire constants; owner fix lives in oauth-poll-token (xai.lisp:91), not here. | 20 |
| `src/cadr-ai/oauth/providers/openai-device.lisp` | 199 | 7 | Implement OpenAI Codex device authorization, polling, and runtime login selection. | pass | no-rewrite | string= on OpenAI wire error codes at :116-123 is the baseline-verbatim contract; cancellation via dynamic binding is already Lisp-native. | 20 |
| `src/cadr-ai/oauth/providers/openrouter.lisp` | 89 | 7 | Implement OpenRouter PKCE login, key exchange, and refresh. | pass | no-rewrite | Empty-string-as-null at :42-43 is forced by the shared auth.json round-trip contract. | 20 |
| `src/cadr-ai/oauth/providers/radius.lisp` | 116 | 7 | Implement Radius browser/device login and gateway-scoped credential refresh. | pass | done | parse-device-authorization. I0: fourth copy gone. | 20 |
| `src/cadr-ai/oauth/providers/xai.lisp` | 184 | 17 | Implement xAI device authorization, polling, and refresh over the shared OAuth request boundary. | pass | no-rewrite | member/string= over wire error lists at :112-120 are protocol constants; file already uses dynamic vars and &key test seams. | 20 |
| `src/cadr-ai/package.lisp` | 480 | 2 | Declare the public `cadr-ai` package surface and HTTP injection seam. | pass | no-rewrite | The export barrel mirrors index.ts, but one defpackage is CL's one-owner API inventory; scattering :export would create N owners. | 20 |
| `src/cadr-ai/auth/bedrock.lisp` | 220 | 12 | Resolve Bedrock credentials, profiles, regions, and ARN-derived configuration. | pass | done | destructuring-bind ARN parts. I0: no nth 2/3. | 20 |
| `src/cadr-ai/auth/device-code.lisp` | 239 | 12 | Own generic cancellable device-code polling, validation, and credential parsing. | pass | done | parse-device-authorization. I0: one parse, keyword options. | 20 |
| `src/cadr-ai/auth/github-copilot.lisp` | 53 | 3 | Parse GitHub device authorization and resolve Copilot endpoint/model metadata. | pass | done | parse-device-authorization. I0: third copy gone. | 20 |
| `src/cadr-ai/auth/radius-cloudflare.lisp` | 118 | 6 | Validate Radius configuration and materialize Radius/Cloudflare endpoints. | pass | done | +radius-oauth-client-id+ / scope. I0: one client identity. | 20 |
| `src/cadr-ai/auth/vertex.lisp` | 212 | 8 | Resolve Google Vertex credentials and exchange service-account access tokens. | pass | no-rewrite | string= dispatch on method ids at :31-53 is the baseline prompt-flow contract; injected probes and data-driven specs are Lisp-native. | 20 |
| `src/cadr-ai/provider.lisp` | 799 | 75 | Define provider protocol classes plus common request, retry, history, stream, and error machinery. | pass · large | no-rewrite | append-content-block at :470-474 emulates push, but the list position IS the content-index contract; CLOS generics and constructor macro used elsewhere. | 20 |
| `src/cadr-ai/providers/anthropic.lisp` | 644 | 16 | Implement Anthropic Messages request, response, cache, tool, and stream semantics. | pass · large | done | pop traversal. I0: no nth on prepared. | 20 |
| `src/cadr-ai/providers/google.lisp` | 442 | 20 | Implement Google Generative AI request, thinking, response, and stream semantics. | pass · large | done | google-gemini-3-model-p. I0: one tool-id sniff. | 20 |
| `src/cadr-ai/providers/azure-openai.lisp` | 223 | 12 | Adapt Azure, Copilot, and Cloudflare OpenAI-compatible endpoints and headers. | pass | done | &rest/apply build-request. I0: one keyword list. | 20 |
| `src/cadr-ai/providers/bedrock.lisp` | 934 | 34 | Implement Bedrock Converse payloads, SigV4 request metadata, event reduction, and complete responses. | pass · large | done | bedrock-sigv4-headers. I0: one sigv4 bind. | 20 |
| `src/cadr-ai/providers/codex.lisp` | 34 | 1 | Adapt the OpenAI Codex Responses request contract. | pass | no-rewrite | Post-build remhash at :31-32 reuses the OpenAI builder and applies a max_output_tokens-only delta, the correct reuse shape. | 20 |
| `src/cadr-ai/providers/mistral.lisp` | 97 | 4 | Adapt Mistral Conversations reasoning and tool-call identifiers. | pass | done | affinity-p. I0: one session/cache decision. | 20 |
| `src/cadr-ai/providers/pi-messages.lisp` | 255 | 6 | Implement pi Messages request rewriting and event/response reduction. | pass | done | block-indices stores the block. I0: no nth. | 20 |
| `src/cadr-ai/providers/vertex.lisp` | 134 | 2 | Adapt Google Vertex endpoints and signed request construction. | pass | no-rewrite | {location} substring sniffing at :7 is the baseline base-URL config contract; credential fallback is or/let* idiom with signaled errors. | 20 |
| `src/cadr-ai/providers/openai-completions.lisp` | 880 | 33 | Implement OpenAI-compatible Chat Completions request, response, tool, and stream semantics. | pass · large | done | block-indices stores (index . block). I0: no nth. | 20 |
| `src/cadr-ai/providers/openai.lisp` | 828 | 17 | Implement OpenAI Responses request, response, tool, reasoning, and stream semantics. | pass · large | done | block-indices stores (index . block). I0: no nth. | 20 |
| `src/cadr-ai/providers/definitions.lisp` | 1,040 | 14 | Validate and own the complete 38-provider declaration matrix and environment inputs. | pass · large | done | provider-definition-row-keys from MOP. I0: slots are the contract. | 20 |
| `src/cadr-ai/providers/registry.lisp` | 157 | 2 | Instantiate declared providers through the appropriate native protocol class. | pass | no-rewrite | Five metadata-or-fallback ifs at :124-148 share a shape but are five distinct decisions — the explicit chain is the auditable parity contract. | 20 |
| `src/cadr-ai/providers/runtime-projection.lisp` | 297 | 17 | Project provider declarations into session-local auth, OAuth, model, and dispatch callbacks. | pass | done | +api-key-auth-strategy-table+. I0: one strategy set. | 20 |
| `src/cadr-ai/runtime/faux-provider.lisp` | 601 | 34 | Implement the deterministic faux provider, queued responses, and transcript serializer. | pass | done | faux-stream-block. I0: one emit skeleton. | 20 |
| `src/cadr-ai/runtime/models.lisp` | 809 | 51 | Own mutable provider/model/auth state, refresh, lookup, and request dispatch. | pass · large | done | call-with-models-runtime-error. I0: one wrap. | 20 |
| `src/cadr-ai/sse.lisp` | 267 | 7 | Parse Server-Sent Events from text or binary streams. | pass | no-rewrite | Sentinel read loop transcribes the WHATWG line protocol; field dispatch has one owner and failures signal typed errors. Binary data/event/id lines decode payload octets only. File-stream READ-SEQUENCE scans newlines in the 8192 chunk; sockets stay on READ-BYTE. | 20 |
| `src/cadr-ai/support/attribution.lisp` | 18 | 2 | Emit OpenCode session and client headers for provider requests. | pass | done | opencode-request-headers. I0: host+session. | 20 |
| `src/cadr-ai/support/grammar-coercion.lisp` | 279 | 15 | Coerce and validate grammar-tool JSON values against schemas. | pass | no-rewrite | string= type dispatch at :57-66/:80-121 is external JSON Schema vocabulary the baseline compares verbatim. | 20 |
| `src/cadr-ai/support/overflow.lisp` | 78 | 5 | Classify context-overflow errors from status and usage evidence. | pass | no-rewrite | String fragment tables at :3-27 are provider wire error messages; case-insensitive substring match is the baseline heuristic. | 20 |
| `src/cadr-ai/support/release.lisp` | 104 | 19 | Read the single version source and format the aligned release identity. | pass | no-rewrite | Format-built copy at :75-96 is byte-locked to baseline auth-guidance.ts with citations; wrappers implement the single-owner identity. | 20 |
| `src/cadr-ai/support/retry.lisp` | 169 | 9 | Classify retryable assistant failures and execute the bounded retry policy. | pass | done | aborted-message. I0: one abort-during-wait. | 20 |
| `src/cadr-ai/support/threads.lisp` | 6 | 1 | Delegate bounded thread cleanup to the B3 core policy owner. | pass | no-rewrite | A 3-line facade forwarder keeping cadr-core the owner; nothing TS-shaped exists to rewrite. | 20 |
| `src/cadr-ai/support/token-estimation.lisp` | 170 | 14 | Estimate message, tool, image, and context token usage. | pass | no-rewrite | utf16-code-unit-length at :11-13 counts UTF-16 units because that is the JS-semantics baseline heuristic, not an index-loop habit. | 20 |
| `src/cadr-ai/support/uuid.lisp` | 93 | 4 | Generate monotonic UUIDv7 identifiers from random octets. | pass | no-rewrite | Manual byte assembly is RFC 9564 UUIDv7 layout; entropy pool copies getRandomValues (no /dev/urandom per id). | 20 |
| `src/cadr-ai/transport/aws-event-stream.lisp` | 222 | 10 | Decode AWS event-stream frames and issue Bedrock event requests. | pass | no-rewrite | Manual offset walking and CRC32 at :18-83 are a byte-fixed frame format; dep policy bars new libs, failures are signaled conditions. | 20 |
| `src/cadr-ai/transport/http.lisp` | 831 | 42 | Implement abortable native HTTP/TLS transport, framing, and normalized errors. | pass · large | done | parsed-url-authority + signal-http-timeout. I0: one port, one timeout. | 20 |
| `src/cadr-ai/types.lisp` | 207 | 21 | Define provider/model/message/content/tool/event value types and safe printers. | pass | done | defstruct constructor. I0: no 13-key wrapper. | 20 |
| `src/cadr-ai/websocket.lisp` | 628 | 41 | Implement OpenAI Codex WebSocket framing, pooling, continuation, and provider dispatch. | pass · large | no-rewrite | json-value-equal-p at :403-404 matches the baseline's own JSON.stringify cache-admission comparison; hand-rolled SHA-1 justified by the dep policy. | 20 |

### 2.3 `cadr-cli`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-cli/arguments.lisp` | 1036 | 27 | Parse, validate, resolve, and document the CLI argument contract. | pass · large | done | lookup-cli-option closed table; print-cli-usage write-string literals. I0: approve/no-approve stay special. | 20 |
| `src/cadr-cli/bootstrap/auth.lisp` | 172 | 2 | Project provider-owned authentication options into the native CLI login command. | pass | done | one metadata let. I0: :status stays on the option. | 20 |
| `src/cadr-cli/bootstrap/commands.lisp` | 2,580 | 8 | Construct the agent controller and dispatch CLI modes and slash-command output through one frontend sink. | pass · large | done | spec-driven command records; one provider match. I0: no third loop. | 20 |
| `src/cadr-cli/bootstrap/main.lisp` | 409 | 10 | Handle package/credential preflight, parse arguments, and enter the selected CLI path. | pass | no-rewrite | list_models writes token counts from slots; six-column table is still the baseline. | 20 |
| `src/cadr-cli/bootstrap/sessions.lisp` | 1,963 | 46 | Resolve, create, switch, fork, export, and mutate CLI sessions and their tree lifecycle. | pass · large | done | +hotkeys-markdown-sections+. I0: key adjacent to label. | 20 |
| `src/cadr-cli/bootstrap/settings.lisp` | 1232 | 21 | Resolve agent directories, trust, settings, resources, runtime reload, and the effective system prompt. | pass · large | done | inline image options; +settings-fallback-keys+. I0: no splice. | 20 |
| `src/cadr-cli/bootstrap/tools.lisp` | 89 | 8 | Construct the baseline tool set and its prompt metadata. | pass | no-rewrite | Most TS-like: the per-tool `(string= "read" …)` cond dispatch in `tool-prompt-guidelines` (tools.lisp:77-88); correct in Lisp because `cadr-ai:tool-name` returns baseline-catalog wire strings (JSON boundary — keywords cannot substitute), the guideline bodies are verbatim system-prompt bytes, and looping over the tool list preserves the catalog order the prompt contract depends on — an alist respelling would remove no decision; the file is already data-driven where decisions live (tools.lisp:3-7, 51-61). | 20 |
| `src/cadr-cli/build-support.lisp` | 14 | 2 | Supply the native-image save arguments and executable entry point. | pass | no-rewrite | nothing TS-shaped; nearest candidate is the L8 `(member :sb-core-compression features)` probe, which is already keyword-based — a 14-line keyword-plist builder for save-lisp-and-die is exactly the native form. | 20 |
| `src/cadr-cli/config.lisp` | 284 | 22 | Resolve legacy CLI provider configuration and auth commands. | pass | done | +oauth-login-providers+. I0: one login/refresh table. | 20 |
| `src/cadr-cli/support/atomic-write.lisp` | 7 | 1 | Retain the CLI compatibility entry point while delegating atomic replacement to `cadr-core`. | pass | done | core default, no restated :flush. I0: wrapper owns nothing extra. | 20 |
| `src/cadr-cli/support/bug-report.lisp` | 159 | 10 | Redact diagnostics and write the local `/bug` ZIP archive. | pass | done | redact-url + redact-json-value. I0: CADR_* env only. | 20 |
| `src/cadr-cli/support/changelog-share.lisp` | 342 | 10 | Strip terminal styling, parse changelogs, and publish the resulting session share. | pass | no-rewrite | Most TS-like: the hand-indexed strip-ansi scanner (lines 9-79, incf/length poking), but byte-exact strip parity on adversarial edges (unterminated OSC keeps ESC, lines 52-56; C1 0x9B introducer, line 14) is the output contract, and baseline implements it as a chalk-derived regex (pi utils/ansi.ts:29-42) whose CSI-final set deliberately differs from line 63's #x40-#x7E — swapping in cl-ppcre would be a parity risk, not a checkable improvement; the (condition () nil) parse swallows (line 245) mirror baseline failure->null. | 20 |
| `src/cadr-cli/support/event-bus.lisp` | 40 | 5 | Own the process-local event bus and its error sink. | pass | no-rewrite | Most TS-like: string-keyed channels with append-ordered handler lists (lines 4, 12-16), a JS Map | 20 |
| `src/cadr-cli/support/external-editor.lisp` | 20 | 1 | Round-trip text through the configured external editor. | pass | no-rewrite | Most TS-like: integer-exit-status runner with zerop branch (line 15) and manual probe/delete cleanup (lines 19-20), but exit codes are inherently integers and fallback-to-original-content on nonzero exit is the baseline contract; uiop:with-temporary-file + unwind-protect + chmod #o600 (lines 4-14) is already the Lisp-native form. | 20 |
| `src/cadr-cli/support/file-watcher.lisp` | 69 | 6 | Poll one file signature and close its worker through bounded cleanup. | pass | no-rewrite | Most TS-like: catch-all (error () (funcall on-error)) swallows (lines 39-41, 67-69), try/catch->callback style, but errors-via-callback across the watcher thread boundary is the baseline semantics; the mutex + waitqueue condition-wait poll loop (lines 53-63) and :change keyword event (line 37) are already idiomatic CL. | 20 |
| `src/cadr-cli/support/headers.lisp` | 75 | 5 | Merge provider attribution and request header sources. | pass | done | +stream-setting-defaults+. I0: one inherit walk. | 20 |
| `src/cadr-cli/support/html.lisp` | 63 | 5 | Escape and validate HTML-facing strings and shell quoting. | pass | no-rewrite | Most TS-like: stringly env flag (string= (or value "") "1") at line 50, but env vars are strings and baseline defines the flag as exactly "1" (observable semantics); the URL-scheme/data-prefix allowlists (lines 33-44) are a security contract mirrored verbatim from baseline, and escape-html already uses case + with-output-to-string (lines 4-14). | 20 |
| `src/cadr-cli/support/model-help.lisp` | 20 | 6 | Construct provider/model login help and missing-model diagnostics. | pass | done | B10-frozen cadr-ai surface; CLI names stay. I0: still five forwards. | 20 |
| `src/cadr-cli/support/paths.lisp` | 119 | 6 | Parse file URLs and normalize user path input without changing caller display policy. | pass | no-rewrite | Most TS-like: the strip-json-comments index lexer (lines 8-36), but byte-exact JSONC preprocessing (comment/trailing-comma stripping only outside strings) is the parse contract, and the author already uses position/position-if-not where a sequence scan suffices (lines 26-33); decode-file-url-path's adjustable octet buffer with vector-push-extend (lines 44-64) is idiomatic CL. | 20 |
| `src/cadr-cli/support/resume-version-git.lisp` | 225 | 9 | Format resume commands and parse versioned Git sources. | pass | done | pop walk, missing token is 0. I0: 1.0 == 1.0.0. | 20 |
| `src/cadr-cli/support/shell-process.lisp` | 132 | 12 | Discover shell configuration and manage detached process trees. | pass | done | ProgramFiles loop. I0: one getenv-then-format. | 20 |
| `src/cadr-cli/support/threads.lisp` | 7 | 1 | Retain the CLI cleanup entry point while delegating policy to `cadr-core`. | pass | done | apply core cleanup. I0: no restated 0.5d0/t. | 20 |
| `src/cadr-cli/support/timings.lisp` | 45 | 6 | Record and print opt-in startup timing namespaces. | pass | done | push + nreverse at print. I0: printed order unchanged. | 20 |
| `src/cadr-cli/crash.lisp` | 59 | 4 | Bind CLI-specific secret discovery and redaction into the fatal-condition boundary. | pass | no-rewrite | most TS-like is the dotted-pair redaction-rule table walked with car/cdr and a setf accumulator (L31-40), but dolist-over-alist is the native idiom and the regex/replacement literals are byte-level crash-log contract text; the crash path must stay minimal and total. | 20 |
| `src/cadr-cli/extensions/commands.lisp` | 56 | 3 | Dispatch extension commands and prompt-template expansion. | pass | no-rewrite | Most TS-shaped is the string= "/reload" dispatch (line 28), but slash-command names are the baseline wire format (extension commands register by string name), and split-extension-command properly returns multiple values (14-22). | 20 |
| `src/cadr-cli/extensions/discovery.lisp` | 212 | 11 | Define extension source/manager records and discover precedence-ordered sources. | pass | no-rewrite | Most TS-shaped is the catch-all (condition (c) (push (princ-to-string c) errors)) at 165/184, but per-source failure isolation collected as message strings is the baseline reportDiagnostics contract; scopes are keywords and dedupe is a hash-table (117-143). | 20 |
| `src/cadr-cli/extensions/installer.lisp` | 209 | 9 | Validate, stage, clone, and install opt-in extension packages. | pass | done | uiop:string-prefix-p. I0: GIT: is case-sensitive. | 20 |
| `src/cadr-cli/extensions/loader.lisp` | 702 | 20 | Own extension/infrastructure output sinks, local dependency loading, UI wiring, and reload lifecycle. | pass | no-rewrite | Most TS-shaped is detecting load failures via (search "Failed to load extension" message) at 66 (plus recomposition at 44-48), but baseline main.ts:895 defines that predicate as exactly this substring test, false-positives included — a typed marker would diverge; handler-bind/find-restart (332-339, 418-434) and package-per-extension isolation (475-478) are Lisp-native. | 20 |
| `src/cadr-cli/extensions/llama/client.lisp` | 472 | 25 | Implement llama-server HTTP operations and progress polling. | pass · large | no-rewrite | Most TS-shaped is normalize-llama-server-url's index-arithmetic suffix stripping (50-73), but URL acceptance/rejection must match the baseline exactly and no URL library is in the dep set; wire strings are whitelisted then interned to keywords at the parse boundary (127-132, 172) and the SSE watch uses catch/throw (356/416). | 20 |
| `src/cadr-cli/extensions/llama/extension.lisp` | 470 | 18 | Bind llama commands and catalog refresh into the extension API. | pass · large | done | llama-gated-approval-text. I0: :manual not "manual". | 20 |
| `src/cadr-cli/extensions/llama/huggingface.lisp` | 290 | 14 | Search and inspect Hugging Face GGUF artifacts. | pass | no-rewrite | Most TS-shaped is the hand-nested comparator special-casing "Q4_K_M" (199-221), but it encodes the baseline's exact quantization ordering shown in the download select (presentation contract, ties included); gated is correctly keyword-ized at this boundary (231-238) — the consumer-side bug is in extension.lisp:283. | 20 |
| `src/cadr-cli/extensions/llama/provider.lisp` | 315 | 12 | Project llama-server as a session-local native provider. | pass · large | done | llama-positive-number. I0: one plusp guard. | 20 |
| `src/cadr-cli/interactive/components/loaders.lisp` | 155 | 15 | Own dynamic-border and bordered-loader component primitives. | pass | done | format-key-text*. I0: no join/split round trip. | 20 |
| `src/cadr-cli/interactive/components/countdown.lisp` | 90 | 7 | Own deterministic countdown timer state, rendering, and ticking. | pass | no-rewrite | most TS-like is the union-typed ui slot dispatched via typep/functionp (26-32), but that is the deliberate test seam (render-request function double vs tui-root); the rest is idiom — decf/when/unless flags and dispose guarding against joining its own thread (84-89) — matching baseline setInterval countdown semantics. | 20 |
| `src/cadr-cli/interactive/components/armin.lisp` | 282 | 21 | Own the Armin animated component and its frame lifecycle. | pass | done | 2D array + aref. I0: no nth cell write. | 20 |
| `src/cadr-cli/interactive/components/daxnuts.lisp` | 185 | 17 | Own the Daxnuts animated component and its frame lifecycle. | pass | done | +daxnuts-rgb-grid+ / image lines. I0: parse once. | 20 |
| `src/cadr-cli/interactive/components/announcement.lisp` | 41 | 2 | Compose the Earendil announcement component. | pass | no-rewrite | most TS-like is the duplicated accent-border lambda (11-13 vs 38-40) in an otherwise straight container assembly; the strings are baseline copy/geometry and the only repeated decision is a 3-line lambda — extracting it is cosmetic with no checkable benefit. | 20 |
| `src/cadr-cli/interactive/clipboard.lisp` | 449 | 22 | Own platform clipboard text/image discovery, reading, and writes. | pass · large | no-rewrite | most TS-like is the catch-all (condition () nil) swallow pattern (46-56, 76-81, 94-100, 204-216), i.e. try/catch→null, but best-effort fallback over external tools is the baseline contract and the boundary does signal configuration-error when every strategy fails (111-113); keyword outcome returns (114-120) and multiple-value runners (204-216) are already Lisp-shaped. | 20 |
| `src/cadr-cli/interactive/footer.lisp` | 536 | 23 | Own footer path/usage/status projection and asynchronous Git branch data. | pass · large | no-rewrite | most TS-like is the conditional pyramid in find-git-footer-paths (107-155) and the ".invalid" literal appearing twice (214, 293), but both mirror the baseline's git-discovery case analysis and sentinel (footer-data-provider.ts:16-48, 245, 259); the file otherwise uses Lisp strengths — semaphore-timeout poll loop with content-signature hashing replacing fs.watch (251-270, 437-450) and a dynamically-rebound *git-symbolic-branch-function* seam (419-420, 437-439). | 20 |
| `src/cadr-cli/interactive/images.lisp` | 290 | 9 | Inspect and process interactive image bytes under model limits. | pass | no-rewrite | most TS-like is jpeg-dimensions' manual index walk (20-83), but it is a binary marker scan over a byte vector via aref — the right tool, no list random access; multiple-value returns, typed defstruct, and the identity-preserving changed-flag in normalize-tool-result-images (239-286) are Lisp-native. | 20 |
| `src/cadr-cli/interactive/state.lisp` | 302 | 13 | Own mutable TUI entry, overlay, status, theme, and root-state records. | pass | done | tui-multiline-editor-p; exported editor-clear. I0: one typep. | 20 |
| `src/cadr-cli/interactive/status.lisp` | 445 | 27 | Own startup input, status projection, render coordination, spinners, and account warnings. | pass | done | tail + last-status-cell. I0: no nth last write. | 20 |
| `src/cadr-cli/interactive/syntax.lisp` | 1,089 | 33 | Implement baseline-compatible deterministic syntax highlighting. | pass · large | done | advance helper. I0: one reset after emit. | 20 |
| `src/cadr-cli/interactive/theme.lisp` | 215 | 11 | Detect, resolve, export, and discover interactive themes. | pass | done | xterm-16 vector/aref. I0: matches 6-level table. | 20 |
| `src/cadr-cli/interactive/themes.lisp` | 415 | 12 | Watch, validate, and apply live TUI theme files and terminal theme changes. | pass | no-rewrite | Most-TS: L79-81 string enum `(member name '("$schema" "name" ...) :test #'string=)` and the string side of the token maps — correct because these are JSON member names from user theme files and parse-json yields string-keyed hash tables used directly (L86, 172-173); the file converts to keywords exactly once at the boundary (+tui-theme-json-color-map+ cdr side) and everything internal (overrides alist, :thinking-max fallback) is keywords. | 20 |
| `src/cadr-cli/interactive/tool-render-session.lisp` | 61 | 3 | Own incremental tool-render session state and projection. | pass | no-rewrite | Most-TS: L22 `(not (null pending-p))` truthiness coercion — correct because the slot is declared `:type boolean` (L14), so normalizing at the write boundary lets SBCL's defstruct slot-type check enforce the invariant on every later setf while callers keep a generalized-boolean contract. | 20 |
| `src/cadr-cli/interactive/user-bash.lisp` | 213 | 9 | Render and update direct user bash executions independently of agent tool calls. | pass | no-rewrite | Most-TS: L42-47 second tail-slice `(nthcdr (- count +user-bash-preview-lines+) lines)` looks hand-copied from L24-28 — but they measure different quantities: L24-28 selects source logical lines (and computes hidden-count for the "... N more lines" copy), L42-47 re-truncates after wrapping because the baseline's 20-row preview is measured on wrapped output rows; the byte contract (comment L14-18) requires both. | 20 |
| `src/cadr-cli/interactive/transcript.lisp` | 1,070 | 30 | Project every session entry and assistant/user/custom transcript component. | pass · large | done | wrap-transcript-lines. I0: one OSC-133 splice. | 20 |
| `src/cadr-cli/interactive/tool-rendering.lisp` | 1,009 | 24 | Project agent tool calls/results and reduce agent events into TUI state. | pass · large | done | kebab-keyword-to-camel. I0: one key mapping. | 20 |
| `src/cadr-cli/interactive/entries.lisp` | 918 | 36 | Own append, replacement, invalidation, and status-entry mutation. | pass | done | +startup-expanded-help+. I0: text and style one table. | 20 |
| `src/cadr-cli/interactive/pending-messages.lisp` | 63 | 3 | Render and restore queued steering and follow-up input. | pass | no-rewrite | Most TS-like: twin mapcar blocks at 44-49 and 50-55 differing only in the "Steering:"/"Follow-up:" label, but the shared decision is already factored once into the flet pending-line (37-41) and the two literals are baseline-mandated copy over two distinct state queues, so a data table would only relocate literals; typecase (4-9) and format ~{~A~^...~} (15) are idiomatic. | 20 |
| `src/cadr-cli/interactive/frame.lisp` | 232 | 3 | Compose transcript, status, widgets, overlays, editor, and footer into one frame. | pass | no-rewrite | Most TS-like: the 13-branch hand-rolled type dispatch at 4-35, but its t-fallback (35) is load-bearing — plain select-list overlays (built at controller.lisp:1577-1583, e.g. the /model fallback) render through it — branch signatures are heterogeneous (:now passed only at 32-33), and cond→typecase/defgeneric over the same defstruct predicates adds no machine-checked invariant, failing the project's own checkable-benefit test. | 20 |
| `src/cadr-cli/interactive/extension-ui.lisp` | 756 | 35 | Bridge extension UI requests and custom components into the live TUI. | pass | done | extension-dialog-chrome. I0: one border/title/footer. | 20 |
| `src/cadr-cli/interactive/autocomplete.lisp` | 331 | 15 | Construct command/path autocomplete and extension shortcut routing. | pass | done | push + nreverse. I0: last registration still wins. | 20 |
| `src/cadr-cli/interactive/controller.lisp` | 2,909 | 20 | Own the interactive lifecycle, slash-command routing, input loop, and cleanup. | pass · large | done | one plusp wrapper around overlay dispatch. I0: empty input skips all. | 20 |
| `src/cadr-cli/interactive/selectors/common.lisp` | 394 | 27 | Own composable selector chrome, viewport/count, input, fuzzy matching, and wrap navigation. | pass | no-rewrite | Most TS-like: string direction alist and "shift+ctrl+up" string key-ids at common.lisp:19-35, but canonical key IDs are the baseline's string-typed keybinding contract consumed by cadr-tui:canonical-key-id, so keywordizing would add a conversion layer while removing no decision; the keyword-tagged section DSL with case dispatch and renderer closures (common.lisp:271-374) is data-driven Lisp. | 20 |
| `src/cadr-cli/interactive/selectors/sessions.lisp` | 1,477 | 49 | Search, mutate, navigate, and render resumable session trees. | pass · large | done | session-selector-gutter-prefixes. I0: one reverse walk. | 20 |
| `src/cadr-cli/interactive/selectors/tree.lisp` | 1,812 | 57 | Filter, navigate, edit, and render the branching session tree overlay. | pass · large | no-rewrite | Most TS-like: positional first…seventh access on layout-stack tuples at tree.lisp:1079-1085, but each tuple is pushed and fully destructured inside the same loop (constructed tree.lisp:1124-1135, every slot read immediately at pop), functioning as multiple-values-on-a-stack with one producer, one consumer, and no duplicated decision; substantive machinery (keyword filter case, hash-table fold/visibility maps, labels-local changed/toggle dedup at tree.lisp:793-805) is Lisp-native. | 20 |
| `src/cadr-cli/interactive/selectors/settings.lisp` | 1042 | 28 | Edit settings and theme submenus through the shared selector frame. | pass · large | done | unwrap flet; automatic-theme chrome; model-thinking submenu. I0: one return-from. | 20 |
| `src/cadr-cli/interactive/selectors/auth.lisp` | 624 | 25 | Select authentication methods/providers and collect API keys. | pass · large | no-rewrite | Most TS-like: string-typed status :source matched via string= at auth.lisp:423-425 where keywords look natural, but the field is produced as strings across cadr-ai provider/oauth metadata (runtime-projection.lisp:125, github-copilot.lisp:138) and env-var sources are intrinsically strings, so this consumer cannot keywordize without forking a cross-package representation. | 20 |
| `src/cadr-cli/interactive/selectors/models.lisp` | 1,310 | 62 | Search, choose, scope, enable, and order models. | pass · large | done | :component input. I0: frame computes cursor. | 20 |
| `src/cadr-cli/interactive/selectors/thinking.lisp` | 316 | 18 | Search, choose, and render thinking-level overlays with session vs default persistence. | pass | done | thinking-selector-state + fuzzy filter; Ctrl+S :persist path. I0: one frame owner. | 21 |
| `src/cadr-cli/interactive/selectors/trust.lisp` | 293 | 10 | Choose and persist project trust decisions. | pass | no-rewrite | Most TS-like: hardcoded "k"/"j" string literals checked alongside the keybinding manager in both input layers (trust.lisp:145-150, 160-171), but the baseline hardcodes the same non-configurable aliases (trust-selector.ts:122) and cadr must reproduce that observable behavior on both the parsed-event and raw-byte paths, while each or-form still honors user-configured keybindings first. | 20 |
| `src/cadr-cli/interactive/selectors/fork.lisp` | 147 | 7 | Choose the user-message boundary for a forked session. | pass | no-rewrite | Most TS-like: nth index access into the items list at fork.lisp:43-45, but selection state is an index because the baseline select list is index-based, the shared frame DSL is list-based end to end, and the O(n) nth is dominated by the O(n) per-keystroke render it feeds — vectorizing would ripple through the shared abstraction for no behavioral or asymptotic gain. | 20 |
| `src/cadr-cli/media.lisp` | 1,277 | 56 | Decode, orient, resample, and encode PNG/JPEG image bytes under model limits. | pass · large | no-rewrite | Most TS-like: the hand-rolled byte-cursor JPEG repair walker with backtracking (decf position at 574, body 561-621) and the twin EXIF walker at 681-714; correct in Lisp because JPEG/EXIF are sequential byte formats whose acceptance set must mirror the baseline/Photon behavior exactly (comment 558-560), an index cursor over octet vectors is the native CL idiom, and a binary-parser dependency would need review under the dep policy — the file already uses Gray streams (3-84), defstruct (363), ecase on keywords (417), and multiple values (855-859). | 20 |
| `src/cadr-cli/migration.lisp` | 512 | 30 | Safely migrate the legacy user-data directory with explicit consent. | pass | done | +managed-binary-names+. I0: one name list. | 20 |
| `src/cadr-cli/models/auth-storage.lisp` | 376 | 24 | Serialize locked auth-store updates and runtime credential overrides. | pass | no-rewrite | Most TS-like: instanceof-style etypecase three-backend dispatch repeated across read/modify/delete/list (143, 205, 268, 307); correct in Lisp because the file/memory/runtime trinity is a closed union where etypecase gives machine-enforced exhaustiveness (an unhandled type signals), CLOS methods would scatter rather than remove the decision, and the "api_key"/"oauth" strings at 302-305 are the auth.json/CLI byte contract, not keyword candidates; unwind-protect lock layering (61-63), redacted print (97-99), and the test-injection var (46-47) are already Lisp-shaped. | 20 |
| `src/cadr-cli/models/credential-print.lisp` | 623 | 19 | Parse and execute the one-shot credential-print command without exposing secrets. | pass | done | push/nreverse. I0: forwarded order unchanged. | 20 |
| `src/cadr-cli/models/login-selection.lisp` | 75 | 4 | Classify post-login default-model selection into the baseline four branches. | pass | no-rewrite | Most TS-like: the truthiness guard chain (and (stringp id) (plusp (length id)) id) at 11-13; correct in Lisp because and-returns-last-value is the idiom for value-or-nil guards, and "no default model" is a normal outcome modeled as the :no-default-model keyword branch (23-24) rather than a condition — the file already speaks keywords, ecase (38), values (23-34), and docstrings (16, 61). | 20 |
| `src/cadr-cli/models/matching.lisp` | 398 | 17 | Resolve exact, partial, scoped, and globbed model selections. | pass | done | push/nreverse scoped accumulators. I0: first scoped still wins. | 20 |
| `src/cadr-cli/models/registry.lisp` | 846 | 38 | Build, refresh, authenticate, and project the cohesive runtime model registry. | pass · large | done | available-models cached on registry by models.json/auth.json mtime. I0: one provider-then-id order. | 20 |
| `src/cadr-cli/models/store.lisp` | 197 | 12 | Read and mutate provider-scoped `models.json` entries. | pass | done | copy-model + three setfs. I0: no 13-slot restatement. | 20 |
| `src/cadr-cli/modes/print.lisp` | 578 | 17 | Render agent events for print and JSON command-line modes. | pass | done | shared retry json-put. I0: two keys one block. | 20 |
| `src/cadr-cli/modes/rpc/commands.lisp` | 460 | 4 | Validate and dispatch the closed RPC command set through the shared response sink. | pass | done | parse-queue-mode. I0: one all/one-at-a-time parse. | 20 |
| `src/cadr-cli/modes/rpc/jsonl.lisp` | 123 | 16 | Read/write and validate the RPC JSONL envelope. | pass | no-rewrite | Most TS-like: `require-rpc-boolean` L113 `(member value '(nil t))` — but the JSON parser maps true/false to t/nil, so after the `json-present-p` pre-check (L110) this membership test *is* the exact boolean type check; gensym sentinels (L26-27), mutex-typed defstruct slots, and the single-CR trim (L74-81, byte-contract vs `string-right-trim` which would over-trim) are all correct Lisp choices. | 20 |
| `src/cadr-cli/modes/rpc/mode.lisp` | 96 | 3 | Own RPC line dispatch, event subscription, stream lifetime, and shutdown. | pass | no-rewrite | Most TS-like: L9-13 `(string= (or (json-get object "type") "") "extension_ui_response")` nil-punting — but an absent `type` must neither error nor match, and the nested `handler-case` split (parse-level L35-42 vs command-level L25-34) plus `unwind-protect` restoration of `agent-on-event` (L78-96) is proper condition-system usage, not nil-check layering. | 20 |
| `src/cadr-cli/modes/rpc/models.lisp` | 226 | 13 | Project, select, and cycle RPC models and thinking levels. | pass | no-rewrite | Most TS-like: `rpc-clamp-thinking-level` L168-181 walks the level list with `position`/`nthcdr`/`reverse (subseq ...)` like index arithmetic — but the domain is a fixed ordered 7-element constant and the forward-then-backward search directly encodes the baseline "prefer higher, else nearest lower, else :off" rule; a vector gains nothing at this size, and per-command `nth (mod ...)` cycling (L216-220) is O(n) over a ≤7 list. | 20 |
| `src/cadr-cli/modes/rpc/prompt-bash.lisp` | 248 | 9 | Start, steer, abort, and observe RPC prompt and bash work. | pass | done | apply-input-or-queue. I0: one hook-then-steer. | 20 |
| `src/cadr-cli/modes/rpc/sessions.lisp` | 283 | 10 | Create, switch, fork, compact, and inspect RPC sessions and trees. | pass | no-rewrite | Most TS-like: `rpc-session-stats` L178-220 is a hand-rolled 8-counter fold — but it is a single-pass accumulation over heterogeneous message types where the assistant branch also sums usage fields, which `loop ... count/sum` clauses cannot express without obscuring the pass; the three `(eq :message ...)` guards (L92, L119, L188) are plain keyword compares, and the two-pass tree build with `vector-push-extend` (L240-283) is standard. | 20 |
| `src/cadr-cli/modes/rpc/ui.lisp` | 288 | 12 | Bridge extension UI requests to RPC dialogs with cancellation and timeout. | pass · large | done | rpc-dialog-request-object. I0: one builder; default is nil. | 20 |
| `src/cadr-cli/output-accumulator.lisp` | 199 | 17 | Accumulate split UTF-8 process output into a bounded tail and spill file. | pass | no-rewrite | Most TS-like: per-octet vector-push-extend loop (L144-146), but push-extend on an adjustable octet vector is the standard CL accumulation idiom, pre-spill volume is bounded by max-bytes (fill-pointer reset at L134), and verbatim raw bytes are the baseline spill-file contract; the file otherwise uses fill-pointers, handler-case (L51-55) and multiple values, not nil-ladder TS shapes. | 20 |
| `src/cadr-cli/packages/config-selector.lisp` | 1,518 | 71 | Own the standalone config selector, resource projection, and scoped persistence interaction. | pass · large | done | config-resource-kinds + entry-target. I0: one kind list. | 20 |
| `src/cadr-cli/packages/commands.lisp` | 764 | 9 | Parse package commands and execute help/list/install/update/remove workflows. | pass | no-rewrite | Most TS-like: mutable options record + first-wins note-* closures feeding a ~100-line cond (L45-160), but the contract is parsePackageCommand's record-don't-throw semantics with byte-observable stderr precedence and texts (quoted usage hint with trailing period L440-447, fixed fail order L456-514), per-command option validity is irregular per branch (L71-82), and real failures already signal configuration-error (L577-580) — a data-driven rewrite removes no decision. | 20 |
| `src/cadr-cli/packages/manifest.lisp` | 142 | 5 | Parse package manifests and project resource paths. | pass | done | kind buckets from +package-manifest-resource-fields+. I0: one classify. | 20 |
| `src/cadr-cli/packages/settings.lisp` | 214 | 10 | Persist, remove, deduplicate, and materialize configured package records. | pass | no-rewrite | Most TS-like: the position→nth→(setf nth) index dance in persist-package-source (L85-106), but entries is the baseline-owned settings.json packages array — order is observable, string elements are immutable so replacement must be positional, and the cons-cell-pointer variant saves one O(n) walk on a user-authored handful of entries: a style preference, not a checkable benefit. | 20 |
| `src/cadr-cli/packages/source.lisp` | 338 | 12 | Parse and canonicalize npm, Git, SSH, and local package sources. | pass | done | seen stores the cons cell. I0: no nth overwrite. | 20 |
| `src/cadr-cli/package.lisp` | 289 | 1 | Declare the public `cadr-cli` package surface. | pass | no-rewrite | most TS-like is the 280-symbol flat export barrel (L3-287), but an explicit defpackage export list is CL's only access-control mechanism; splitting interface packages adds indirection with no checkable benefit. | 20 |
| `src/cadr-cli/remote-repl.lisp` | 67 | 8 | Manage the opt-in Slynk server and active-agent binding. | pass | no-rewrite | most TS-like is the global singleton with hand-rolled mutex (L3-24), correct in Lisp because Slynk serves on other threads where dynamic binding cannot reach — a shared cell + with-mutex check-and-set is the only channel (contrast L28, where *debug-io* rebinding uses dynamic scope properly). | 20 |
| `src/cadr-cli/repl.lisp` | 112 | 4 | Run the basic line-oriented REPL mode. | pass | no-rewrite | most TS-like is the L36-38 return-from guard plus kwargs threaded verbatim into dispatch-user-input (L104-106), but early exit from a dispatcher is return-from's job, empty input is not exceptional (no condition warranted), and one hop of explicit functions keeps the seam testable; kinds are already keywords with multiple values. | 20 |
| `src/cadr-cli/resource-loader.lisp` | 353 | 14 | Discover and reload scoped prompts, skills, themes, context, and extensions. | pass · large | done | load-resources-at-paths; hoisted no-X-p. I0: one loader walk. | 20 |
| `src/cadr-cli/sdk/agent-session.lisp` | 481 | 17 | Construct and expose the in-process agent-session facade. | pass | done | sdk-agent-session-dispatch. I0: one listener snapshot. | 20 |
| `src/cadr-cli/sdk/cache-version.lisp` | 498 | 27 | Detect cache anomalies, restore proxy state, and perform release/version checks. | pass | done | previous + any-reported-cache-p. I0: no append prior. | 20 |
| `src/cadr-cli/sdk/model-service.lisp` | 349 | 20 | Implement the SDK model runtime and shared atomic credential path. | pass | done | sdk-configured-models-unshadowed. I0: one shadow rule. | 20 |
| `src/cadr-cli/sdk/resource-service.lisp` | 370 | 13 | Implement reloadable SDK resource discovery and overrides. | pass | done | multiple-value-setq chain. I0: no 3-deep bind. | 20 |
| `src/cadr-cli/sdk/session-manager.lisp` | 107 | 8 | Resolve, create, continue, open, and list SDK sessions. | pass | no-rewrite | Most TS-like: the :unresolved-sentinel memoization in session-manager-resolve (L78-105), but resolve-once-under-mutex with keyword modes dispatched by ecase (L85-104) is the direct Lisp expression of the baseline's lazy-resolve contract; nothing checkable to gain. | 20 |
| `src/cadr-cli/sdk/session-runtime.lisp` | 277 | 15 | Own replaceable SDK session services and runtime disposal. | pass | no-rewrite | Most TS-like: function-agent-session-runtime-factory (L97-116), a single-method interface wrapper, but normalize-agent-session-runtime-factory's etypecase (L151-158) accepting either a lambda or a CLOS object is idiomatic adaptability, and the replace/dispose race handling (L189-211, L265-277) is lock-correct rather than transcribed. | 20 |
| `src/cadr-cli/sdk/settings-service.lisp` | 171 | 20 | Adapt persistent and in-memory settings to the SDK contract. | pass | done | field flet. I0: one hash fallback. | 20 |
| `src/cadr-cli/sdk/system-prompt.lisp` | 218 | 5 | Build the SDK system prompt and extension-aware provider stream. | pass | no-rewrite | Most TS-like: the wall of literal format-string prompt assembly (L63-133) and string tool names with string= membership tests (L38, L50-56) — both are byte-level output contracts: the system prompt goes verbatim into model requests under fixture-replay parity, and tool names are the external tool-name string contract; interning or restructuring gains nothing checkable. | 20 |
| `src/cadr-cli/settings/config-values.lisp` | 198 | 15 | Resolve environment and command-backed configuration values and JSON merges. | pass | no-rewrite | The template index loop at :29-60 is lookahead parsing over a string (O(1) per char) with with-output-to-string accumulation; environment override order is the documented contract. | 20 |
| `src/cadr-cli/settings/manager.lisp` | 512 | 28 | Own layered settings reload, mutation, defaults, and keybindings. | pass | no-rewrite | defstruct+mutex with thin accessors (:70-340); most-TS is the getf nesting in settings-nested-value (:147-156), which is the JSON object shape contract, not a decision copy. | 20 |
| `src/cadr-cli/settings/trust.lisp` | 216 | 13 | Persist and resolve inherited project-trust decisions. | pass | no-rewrite | Mutex-scoped store with multiple values and pathname discipline; most-TS is the :path/:decision plist entry at :69-71, a two-key record at the JSON boundary. | 20 |
| `src/cadr-cli/system-prompt.lisp` | 53 | 4 | Resolve the default, replacement, and appended system prompt. | pass | no-rewrite | most TS-like is L37 sniffing "Permission denied" in the printed condition, correct here because portable CL exposes no errno slot on stream-open failure and the emitted text must be Node's literal "EACCES: permission denied, open '...'" (baseline resource-loader.ts:62 byte contract), so message-matching is the only portable route. | 20 |
| `src/cadr-cli/tool-manager.lisp` | 286 | 25 | Locate, download, extract, and quarantine optional host tools. | pass | no-rewrite | Most TS-like: arch detection by string-sniffing machine-type (:39-45); correct because CL exposes no portable arch keyword (mirrors process.arch mapping), and the ecase asset tables (:53-67) already buy machine-checked exhaustiveness — a Lisp benefit actually used | 20 |
| `src/cadr-cli/tools/bash.lisp` | 591 | 23 | Execute bash with live output, process-group abort/timeout, truncation, and tool wrapping. | pass · large | no-rewrite | Most TS-like: abort detected by string-matching condition messages ("Command aborted", :144-146); correct because abort crosses the extension/operations boundary where message text is the only stable contract (baseline discriminates identically, bash.ts:441/443) — the in-house path already uses the typed user-bash-aborted condition (:14-28, :399-416) | 20 |
| `src/cadr-cli/tools/powershell.lisp` | 115 | 8 | Execute PowerShell with UTF-8 output prefixing, truncation, and Windows-only availability. | pass | done | +powershell-args+ and get-powershell-config gate. I0: one non-Windows fail-closed owner. | 21 |
| `src/cadr-cli/tools/edit.lisp` | 753 | 32 | Match replacements and produce/apply exact edit diffs. | pass · large | done | edit-no-changes-error. I0: one no-change message. | 20 |
| `src/cadr-cli/tools/find.lisp` | 101 | 3 | Implement the bounded find tool. | pass | no-rewrite | optional-integer now owns null→default; the or-wrapper is gone. Remaining file is sort/truncate over baseline-locked notice bytes. | 20 |
| `src/cadr-cli/tools/glob.lisp` | 218 | 13 | Implement recursive globbing with parseable gitignore rules. | pass | no-rewrite | Most TS-like: manual cursor loop with lookahead incf in glob-regex-source (:9-34); correct because glob→regex needs variable-width consumption ("**/" = 3 chars), which `loop across` cannot express (12F-4 base==cwd reuse at :179-184 assessed as landed) | 20 |
| `src/cadr-cli/tools/grep.lisp` | 331 | 7 | Implement bounded regex/literal grep with context. | pass | done | ripgrep-file-lines octet-reads then utf8-string into a fixnum line table. I0: no nth per match. | 20 |
| `src/cadr-cli/tools/ls.lisp` | 100 | 3 | Implement the bounded directory-listing tool. | pass | no-rewrite | optional-integer now owns null→default; the or-wrapper is gone. Remaining file is sort-with-:key / truncate-head. | 20 |
| `src/cadr-cli/tools/path.lisp` | 333 | 32 | Normalize tool paths/arguments/errors and serialize file mutations. | pass · large | done | optional-integer coerces JSON null. I0: callers drop or-wrappers. | 20 |
| `src/cadr-cli/tools/read.lisp` | 192 | 2 | Implement the bounded line-oriented read tool. | pass | no-rewrite | Most TS-like: ub8 newline table then utf8-string of the offset/limit/truncation window | 20 |
| `src/cadr-cli/tools/write.lisp` | 70 | 3 | Implement the UTF-8 write tool and baseline result count. | pass | no-rewrite | Most TS-like: hand-formatted Node-style "EEXIST: file already exists, mkdir '...'" with manual slash trim (:8-12); required by the byte-exact Node error contract the baseline surfaces to the model | 20 |
| `src/cadr-cli/truncation.lisp` | 235 | 12 | Adapt agent truncation results to the CLI tool-result detail contract. | pass | no-rewrite | Most TS-like: harness-truncation-details plist; one-pass octet 0x0A starts plus text-line-table | 20 |
| `src/cadr-cli/extensions/llama/ui.lisp` | 763 | 36 | Render the interactive llama.cpp manager surface: context labels, model descriptions, compact counts, the framed selector, live Hugging Face search, and cancellable progress. | pass · large | done | nthcdr walk; :searching status. I0: no string flag. | 20 |
| `src/cadr-cli/interactive/selectors/login-dialog.lisp` | 279 | 13 | Own the login dialog frame, OAuth/device-code sections, and manual authorization input. | pass | no-rewrite | Most TS-like: nested ifs instead of cond at login-dialog.lisp:141-153, but the structure is a genuine two-priority dispatch (cancel keys vs input delegation) matching the baseline's handleInput; the keyword-tagged plist sections consumed by a case renderer (login-dialog.lisp:162-264) and define-redacted-print-object (login-dialog.lisp:15-18) use Lisp's data-driven and print-object protocols. | 20 |
| `src/cadr-cli/packages/update-checks.lisp` | 293 | 14 | Run background package update checks with process-group isolation and the candidate scan. | pass | no-rewrite | Most TS-like: 10 ms busy-poll timeout loop (L88-95), but UIOP has no timed wait-process, so the alternative is a waiter thread + semaphore to delete a sleep inside a background check already bounded by a 10 s deadline (L63) under unwind-protect cleanup (L86-118); the worker pool already uses vectors/aref/mutex (L226-248) where random access actually matters. | 20 |

Part K9 (2026-08-18): 54 needs-rewrite rows done. find.lisp / ls.lisp keep reasons updated after optional-integer started coercing JSON null. Report: `docs/acceptance/goal-v20-part-k9.md`.

### 2.4 `cadr-evals`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-evals/artifacts.lisp` | 168 | 11 | Validate, hash, persist, and reference eval artifacts. | pass | no-rewrite | The slash-joined path at :136-138 doubles as the persisted JSON reference (byte-pinned in runs.jsonl); structs and keyword dispatch are native. | 20 |
| `src/cadr-evals/harness-table.lisp` | 339 | 17 | Define eval harness rows/tables, canonical group keys, and iteration wrappers. | pass · large | done | wrap-eval-harness calls run-eval-harness. I0: one copy+overlay owner. | 20 |
| `src/cadr-evals/harness.lisp` | 737 | 29 | Run a coding-agent eval lifecycle and normalize transcript, usage, and cleanup. | pass · large | done | last-assistant-since keeps the pre-prompt tail cons. I0: no integer index into the message list. | 20 |
| `src/cadr-evals/main.lisp` | 158 | 6 | Parse eval CLI arguments, dispatch suites, and validate result shape. | pass | done | argument-after-prefix owns --flag=. I0: prefix length computed once. | 20 |
| `src/cadr-evals/package.lisp` | 100 | 2 | Declare the public eval package and session snapshot artifact name. | pass | no-rewrite | Flat export list is the defpackage idiom; defparameter (not defconstant) for a string constant is the correct portable choice. | 20 |
| `src/cadr-evals/reporter.lisp` | 314 | 14 | Persist eval case records and finish a harness report. | pass · large | done | push then nreverse at finish. I0: record is O(1), summary order unchanged. | 20 |
| `src/cadr-evals/suites.lisp` | 468 | 22 | Define the smoke and extension-authoring eval suites and judges. | pass · large | done | json-string owns empty-string coalesce. I0: one accessor for the hello judge. | 20 |
| `src/cadr-evals/summary.lisp` | 732 | 31 | Pair observations, compute correctness/efficiency summaries, and render comparison reports. | pass · large | done | format-summary-signed is one-argument. I0: vestigial TS fractionDigits gone. | 20 |

Part K5 (2026-08-18): six needs-rewrite rows done. Two
no-rewrite rows kept (I wc/duty undrifted). Report:
`docs/acceptance/goal-v20-part-k5.md`.

### 2.5 `cadr-protocol`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-protocol/cbor.lisp` | 492 | 38 | Encode and decode bounded RFC 8949 CBOR values. | pass · large | done | Encoder limits now live on cbor-writer, matching cbor-reader. I0: one owner of the three limits, not four positionals on every recursive arm. | 20 |
| `src/cadr-protocol/codec.lisp` | 121 | 10 | Compose message validation, CBOR, and framing into incremental client/server codecs. | pass | no-rewrite | Condition flattening at :29-33 is the wire-observable error text (bounded, parity-pinned); CL has no standard :cause to preserve instead. | 20 |
| `src/cadr-protocol/framing.lisp` | 170 | 18 | Encode and incrementally decode bounded length-prefixed frames. | pass | done | consume-pending advances offset; compact is amortized on append. I0: O(1) consume, same cursor as cbor-reader. | 20 |
| `src/cadr-protocol/package.lisp` | 33 | 1 | Declare the public `cadr-protocol` package surface. | pass | no-rewrite | Defpackage-only; flat :export list is the CL API-surface idiom. | 20 |
| `src/cadr-protocol/schema.lisp` | 610 | 34 | Validate and parse every protocol v2 client/server message shape. | pass · large | done | optional-field-p owns absent-or-valid. I0: one decision, identical validators. | 20 |

Part K3 (2026-08-18): three needs-rewrite rows done. package.lisp
and codec.lisp kept no-rewrite (I reasons still hold; wc 33 / 121).
Report: `docs/acceptance/goal-v20-part-k2.md` is K2;
`docs/acceptance/goal-v20-part-k3.md` is this close.

### 2.6 `cadr-server`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-server/config.lisp` | 45 | 6 | Resolve server state, auth, instance, and socket paths. | pass | no-rewrite | Four path accessors (:19-45) each add only a contract filename over the single directory-resolution decision at :9-17. | 20 |
| `src/cadr-server/handler.lisp` | 100 | 2 | Dispatch one local server request to supervisor operations. | pass | done | handle-instance-request owns extract+unknown. I0: one miss policy. | 20 |
| `src/cadr-server/ipc.lisp` | 317 | 14 | Serve and call the framed Unix-socket server transport. | pass · large | no-rewrite | Stringly-typed upgrade sniff at :154-168 is the wire contract; stream lifecycle, per-message handler-case, and mutex writes are native. | 20 |
| `src/cadr-server/main.lisp` | 208 | 12 | Parse server CLI operations and run server or stream-client entry points. | pass | done | run-ipc-command + client-ipc-request. I0: a new verb is a builder, not a fifth wrap. | 20 |
| `src/cadr-server/package.lisp` | 59 | 1 | Declare the public `cadr-server` package surface. | pass | no-rewrite | Pure defpackage manifest; canonical idiom, nothing TS-shaped. | 20 |
| `src/cadr-server/protocol.lisp` | 49 | 5 | Encode/decode the server control-plane JSON messages. | pass | no-rewrite | String keys are the byte-level client contract; optional-field emission is already data-driven (:36-48). | 20 |
| `src/cadr-server/radius.lisp` | 731 | 44 | Manage opt-in Radius registration, heartbeat, recovery, and redacted token use. | pass · large | done | heartbeat-retry-or-reregister owns backoff. I0: machine/pi only own POST and reregister. | 20 |
| `src/cadr-server/rpc-process.lisp` | 417 | 26 | Own one child `cadr --mode rpc` process, pending calls, event/UI callbacks, and teardown. | pass · large | no-rewrite | Interface-style setter generics are the mock seam; condition-variable rendezvous and pending-map rollback are Lisp-native. | 20 |
| `src/cadr-server/storage.lisp` | 196 | 15 | Persist server machine and instance records. | pass | done | upsert-instance uses member+setf-car. I0: one match owner. | 20 |
| `src/cadr-server/supervisor.lisp` | 638 | 27 | Supervise live RPC child instances, streams, persistence, and recovery. | pass · large | no-rewrite | Defensive clone-instance-record snapshots are the machine-enforced invariant against cross-thread mutation of persisted records. | 20 |
| `src/cadr-server/types.lisp` | 24 | 4 | Define machine/instance record values and timestamps. | pass | no-rewrite | Two defstructs plus a named copy alias naming the snapshot discipline; minimal and native. | 20 |

Part K4 (2026-08-18): four needs-rewrite rows done. Seven
no-rewrite rows kept (I wc/duty undrifted). Report:
`docs/acceptance/goal-v20-part-k4.md`.

### 2.7 `cadr-storage`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-storage/package.lisp` | 19 | 1 | Declare the minimal SQLite adapter package. | pass | no-rewrite | Pure defpackage facade; import-from/re-export is the canonical CL mechanism for a stable API surface. | 20 |
| `src/cadr-storage/sqlite.lisp` | 12 | 3 | Wrap SQLite open, close, and migration operations. | pass | no-rewrite | A deliberate 12-line forwarding shim; the double-colon reference at :4 is fixed at cadr-agent's defpackage, not here. | 20 |

Part K2 (2026-08-18): both rows kept no-rewrite. I line
counts still match (`wc -l` 19 / 12). package.lisp is still
only a defpackage facade; sqlite.lisp is still the 12-line
forwarder, `cadr-agent::open-sqlite-session-database` still
at :4. No rewrite invented. Report:
`docs/acceptance/goal-v20-part-k2.md`.

### 2.8 `cadr-tui`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-tui/autocomplete.lisp` | 594 | 37 | Parse completion context and provide cancellable command/file suggestions and application. | pass · large | done | dead when gone. I0: no empty-when guard. editor-line-at indexes vector or list. | 20 |
| `src/cadr-tui/components/image.lisp` | 40 | 1 | Render image bytes or the baseline text fallback. | pass | done | fallback-lines flet. I0: one fallback owner. | 20 |
| `src/cadr-tui/components/markdown.lisp` | 1,553 | 45 | Render Markdown, ANSI tables, inline spans, and visually truncated text. | pass · large | done | table widths aref. I0: no nth on width lists. | 20 |
| `src/cadr-tui/components/select-list.lisp` | 305 | 8 | Own filterable two-column selection state, navigation, and rendering. | pass | done | clamp-select-index; height default 5. I0: one clamp owner. | 20 |
| `src/cadr-tui/components/status.lisp` | 253 | 6 | Render footer and status-bar projections. | pass | no-rewrite | The 17-keyword render-footer signature (:65-78) is the canonical Lisp encoding of the TS options bag; sentinels are baseline-cited. | 20 |
| `src/cadr-tui/components/tool-block.lisp` | 623 | 23 | Render tool titles, previews, diffs, elapsed time, and result states. | pass · large | done | pop remaining, no reparse. I0: one walk owns the pair. | 20 |
| `src/cadr-tui/composition/loaders.lisp` | 235 | 22 | Own animated and cancellable loader components using the shared cleanup policy. | pass | done | loader-frames / loader-interval-seconds. I0: one default owner. | 20 |
| `src/cadr-tui/composition/protocol.lisp` | 143 | 30 | Define the component, focus, container, render, event, and disposal protocols. | pass | done | :documentation on six defgenerics. I0: TUI contract is documented. | 20 |
| `src/cadr-tui/composition/rich-content.lisp` | 276 | 10 | Compose cached Markdown and image components. | pass | no-rewrite | cons+make-list assembly at :239-259 copies image.ts char-for-char, but emitted bytes are the render-diff contract and dispatch is keyword-native. | 20 |
| `src/cadr-tui/composition/root.lisp` | 317 | 23 | Own the TUI root, focus routing, render scheduling, and overlay stack. | pass | no-rewrite | The 11-field keyword double-spelling (:106-149) is exported public API with external callers; compile-time keyword checking beats brevity. | 20 |
| `src/cadr-tui/composition/settings-list.lisp` | 470 | 30 | Implement settings-list behavior and the shared editor-component adapters. | pass · large | done | nthcdr walk; Space already baseline. I0: no nth-per-row. | 20 |
| `src/cadr-tui/composition/text-box.lisp` | 280 | 23 | Implement text, spacer, box, and truncated-text components. | pass | done | :blank cache + tab write-string. I0: blank hits the cache. | 20 |
| `src/cadr-tui/editor.lisp` | 2,014 | 90 | Implement the grapheme-aware multiline editor, history, editing, autocomplete, wrapping, and rendering. | pass · large | done | editor-atomic-span. I0: paste spans have named slots. editor-lines is a simple-vector. | 20 |
| `src/cadr-tui/fuzzy.lisp` | 134 | 8 | Score and filter fuzzy text matches. | pass | no-rewrite | Mutation-heavy index loop at :18-51 is idiomatic over CL string-vectors; score constants are the observable ordering contract. | 20 |
| `src/cadr-tui/input-component.lisp` | 408 | 20 | Implement the grapheme-aware single-line Input component and software cursor. | pass · large | done | single-line-input-clear-action. I0: one 3-form reset. | 20 |
| `src/cadr-tui/input.lisp` | 333 | 16 | Incrementally decode terminal bytes, bracketed paste, and control sequences into input events. | pass · large | done | event-kinds table at rebuild. I0: parse-key once. | 20 |
| `src/cadr-tui/keybindings.lisp` | 268 | 14 | Store configurable keybinding definitions and resolve conflicts/actions. | pass | no-rewrite | The string->string-list registry (:4-79) is the external keybindings.json contract users write; rebuild/conflict detection is already idiomatic. | 20 |
| `src/cadr-tui/keys.lisp` | 606 | 37 | Parse and canonicalize Kitty, xterm, modified, and legacy key encodings. | pass · large | done | +kitty-scanner+ et al. I0: scanners compiled at load. | 20 |
| `src/cadr-tui/kill-ring.lisp` | 38 | 5 | Implement kill-ring push/peek/rotate operations. | pass | no-rewrite | Ring rotation via append/last/butlast at :32-34 runs once per yank-pop on a human-scale ring; front-push is the natural CL form. | 20 |
| `src/cadr-tui/mermaid/ansi.lisp` | 17 | 0 | Hold the grok-mermaid ansi.js port attribution; cadr paints via mermaid-themed-lines. | pass | no-rewrite | No executable forms. Class names ("border", "edge", "edgeLabel", "title") are written by canvas/layout and read by transform; the unused class→SGR convenience was deleted. | 20 |
| `src/cadr-tui/mermaid/canvas.lisp` | 336 | 34 | Implement the edge-mask raster grid that clips labels and box borders during layout. | pass | no-rewrite | nth boundary trim at :297-300 runs once per side after the dominating O(w*h) paint; output bytes are fixture-locked. | 20 |
| `src/cadr-tui/mermaid/graph.lisp` | 106 | 18 | Define the shared graph model shared by all Mermaid diagram kinds. | pass | no-rewrite | nth group lookup at :61 is bounded by +gm-max-groups+ 24; a parallel vector would duplicate the push site. | 20 |
| `src/cadr-tui/mermaid/index.lisp` | 109 | 5 | Render the five supported diagram kinds from the shared graph model. | pass | done | +gm-draw-kinds+. I0: one parse-layout table. | 20 |
| `src/cadr-tui/mermaid/transform.lisp` | 428 | 30 | Replace top-level mermaid fences using marked 18 fence rules and the Part B renderer. | pass | done | consume-list streams. I0: no per-line concatenate. | 20 |
| `src/cadr-tui/mermaid/labels.lisp` | 332 | 28 | Normalize Mermaid edge/node labels before measurement and drawing. | pass | done | char on string. I0: no nth char-list. | 20 |
| `src/cadr-tui/mermaid/layout.lisp` | 1,090 | 36 | Implement the Sugiyama layered-graph layout used by flow diagrams. | pass · large | no-rewrite | gm-lex5< nth-walks 5-tuples in a sort comparator (:283-289) bounded by +gm-max-edges+; dominated by the canvas paint, fixture-locked. | 20 |
| `src/cadr-tui/mermaid/layout-seq.lisp` | 254 | 9 | Implement the sequence-diagram layout and lane projection. | pass | no-rewrite | String kind dispatch at :61-195 is parse.lisp's item vocabulary; capped at 512 items, below the measurement floor. | 20 |
| `src/cadr-tui/mermaid/parse.lisp` | 1,197 | 61 | Parse Mermaid source into the shared graph model for all diagram kinds. | pass · large | done | gm-char. I0: string index, no nth. gm-read-shape writes the label to a stream. | 20 |
| `src/cadr-tui/mermaid/source-box.lisp` | 93 | 3 | Fall back to rendering raw Mermaid source in a box when parsing fails. | pass | no-rewrite | Per-cluster concatenate at :39 is bounded by the column limit (cost O(text*limit), not quadratic); boxed bytes fixture-locked. | 20 |
| `src/cadr-tui/mermaid/width-data.lisp` | 1,008 | 1 | Provide the generated code-point width table consumed by the width engine. | pass · large | no-rewrite | Nested vectors preserve the generated JS table; shape is owned by the generator script, reads are O(1) aref. | 20 |
| `src/cadr-tui/mermaid/width.lisp` | 72 | 7 | Compute grapheme display width for Mermaid layout and truncation. | pass | no-rewrite | Hand-rolled binary search at :26-36 is the right form over the sorted generated table; CL stdlib has no custom-run bsearch. | 20 |
| `src/cadr-tui/native-modifiers.lisp` | 78 | 11 | Query Apple Terminal modifier flags through CoreGraphics when supported. | pass | no-rewrite | named-p keyword-or-string acceptance (:9-13) is locked test behavior; reader conditionals and handler-case around the alien call are native. | 20 |
| `src/cadr-tui/overlay.lisp` | 485 | 30 | Resolve overlay geometry, composite frames, and manage overlay focus/stack state. | pass · large | done | composite result vector. I0: aref, not setf-nth. | 20 |
| `src/cadr-tui/package.lisp` | 355 | 1 | Declare the public `cadr-tui` package surface. | pass | no-rewrite | The flat export list is CL's canonical interface mechanism; zero executable code. | 20 |
| `src/cadr-tui/renderer/alt-screen.lisp` | 610 | 14 | Prepare, crop, render, and restore alternate-screen documents. | pass | done | +synchronized-update-*. I0: one wire pair. | 20 |
| `src/cadr-tui/renderer/alt-screen-search.lisp` | 181 | 9 | Match and present transcript search for the fullscreen viewport: whitespace-normalizing corpus, source mapping, and the search bar. | pass | done | +search-whitespace-characters+. I0: one alphabet. | 20 |
| `src/cadr-tui/renderer/lifecycle-input.lisp` | 1,353 | 46 | Own renderer state, lifecycle, viewport, selection, mouse, and input dispatch. | pass · large | done | coerce lines vector. I0: aref scroll scan. last-document is a vector. | 20 |
| `src/cadr-tui/renderer/main-screen.lisp` | 595 | 15 | Render incremental main-screen frames and manage terminal images. | pass · large | done | +kitty-control-prefix+. I0: one Kitty marker. | 20 |
| `src/cadr-tui/renderer/terminal-protocol.lisp` | 73 | 23 | Define the terminal output, cursor, lifecycle, query, and capability protocol. | pass | no-rewrite | The nine default-method stubs (:28-73) are the native CLOS protocol idiom encoding the baseline optional-capability semantics. | 20 |
| `src/cadr-tui/renderer/virtual-terminal.lisp` | 184 | 13 | Implement the deterministic in-memory terminal and screen snapshot. | pass | no-rewrite | The byte-stream state machine at :113-173 needs variable advance (CSI skips); it is the test double for the byte contract. | 20 |
| `src/cadr-tui/stdin-buffer.lisp` | 232 | 11 | Buffer terminal bytes until complete atomic control/key sequences can be emitted. | pass | done | index walk. I0: no per-char subseq tail. | 20 |
| `src/cadr-tui/terminal-colors.lisp` | 191 | 15 | Parse terminal background/color-scheme/cell-size responses. | pass | no-rewrite | The nil-ladder at :77-123 is the contract: malformed wire replies must fall through to passthrough, not signal. | 20 |
| `src/cadr-tui/terminal-image.lisp` | 686 | 44 | Detect image capabilities, encode Kitty/iTerm images, inspect dimensions, crop, link, and fall back. | pass · large | done | +base64-decode-table+. I0: 256-entry lookup. | 20 |
| `src/cadr-tui/terminal.lisp` | 916 | 48 | Own the real process terminal lifecycle, raw mode, keyboard protocol, Apple normalization, queries, and progress. | pass · large | done | protocol scanners. I0: compiled at load. | 20 |
| `src/cadr-tui/theme.lisp` | 562 | 38 | Resolve semantic theme colors/styles and terminal color downgrades. | pass · large | done | ensure-theme-keyword. I0: one canonicalizer. | 20 |
| `src/cadr-tui/threads.lisp` | 6 | 1 | Provide bounded cleanup of one SBCL thread. | pass | no-rewrite | A deliberate package-facade convention replicated identically across systems; nothing TS-shaped to rewrite. | 20 |
| `src/cadr-tui/undo-stack.lisp` | 20 | 5 | Implement undo-stack push/pop/clear operations. | pass | no-rewrite | Unconditional copy-tree on push (:8) is what undo correctness requires over the mutable paste tree; textbook defstruct stack. | 20 |
| `src/cadr-tui/unicode.lisp` | 1,302 | 54 | Implement terminal Unicode/grapheme/ANSI width, slicing, truncation, and wrapping semantics. | pass · large | done | extract/wrap streams. I0: no per-cluster concatenate. | 20 |
| `src/cadr-tui/word-navigation.lisp` | 118 | 10 | Move over whitespace, punctuation, CJK, and editor-atomic word segments. | pass | done | scan-word-while. I0: one mirrored scan. | 20 |
| `src/cadr-tui/latex.lisp` | 1,948 | 66 | Render basic LaTeX math to terminal-friendly Unicode, ported from the fixed baseline LatexParser. | pass · large | done | layout/node vectors. I0: aref / vector-push-extend. | 20 |

Part K8 (2026-08-18): 29 needs-rewrite rows done. `mermaid/width-data.lisp`
untouched. Report: `docs/acceptance/goal-v20-part-k8.md`.

### 2.9 `cadr-core`

| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |
|---|---:|---:|---|---|---|---|---|
| `src/cadr-core/atomic-file.lisp` | 106 | 8 | Atomically replace files with durability policy and private-mode enforcement. | pass | no-rewrite | Most-TS spot: plain string errors at :8/:41 instead of typed conditions. Right in Lisp: call-with-X + unwind-protect is the CL idiom, and the zero-dependency base layer deliberately stays below the condition hierarchies that import it. | 20 |
| `src/cadr-core/cancellation.lisp` | 70 | 7 | Own the shared cancellable-state primitive and its thread-safe propagation. | pass | no-rewrite | Most-TS spot: ignore-errors around the user predicate at :21-22. Right in Lisp: the contract is that a failing predicate must never crash the canceller; defstruct+mutex+waitqueue is the native shape. | 20 |
| `src/cadr-core/package.lisp` | 43 | 1 | Declare the public `cadr-core` package surface. | pass | no-rewrite | Most-TS spot: the explicit export list reads like a TS barrel file. Right in Lisp: defpackage is the boundary mechanism — this list is what the 12E-3 leak metric is measured against. | 20 |
| `src/cadr-core/paths.lisp` | 95 | 19 | Own the single user-level path layout consumed by every cadr system. | pass | no-rewrite | Most-TS spot: eleven isomorphic one-line merge-pathnames bodies at :42-84. Right in Lisp: the set is a registry of distinct paths with per-entry provenance comments, one decision owned once — a macro would add indirection without removing a decision. | 20 |
| `src/cadr-core/redacted-print.lisp` | 44 | 6 | Provide the secret-safe print-object registry that keeps credentials opaque everywhere. | pass | no-rewrite | Most-TS spot: hand-rolled replace-all at :22-36. Right in Lisp: cadr-core is the zero-dependency layer, and define-redacted-print-object at :13-20 is the tree-wide model of a machine-enforced benefit. | 20 |
| `src/cadr-core/threads.lisp` | 47 | 2 | Bound cleanup waits and terminate unresponsive workers instead of hanging exit paths. | pass | no-rewrite | Most-TS spot: the catch-all (condition () timed-out) at :19. Right in Lisp: bounded cleanup must never throw, the sentinel disambiguates timeout from result, and keyword outcomes are idiomatic. | 20 |
| `src/cadr-core/time.lisp` | 71 | 5 | Own UTC/ISO time and ID formatting primitives. | pass | done | unix-milliseconds used get-universal-time (*1000) so every clock/ID landed on .000. Now sb-ext:get-time-of-day (real ms), matching baseline Date.now(). I0: named milliseconds actually are milliseconds — contract/可测. | 20 |

Part J (2026-08-17) amended the K process: consume I verdicts
instead of re-asking the two questions; no new pairing harness when
Part H has no cell; assertions-first may share the rewrite commit
when the new test is red on the old body. Full text:
`docs/acceptance/goal-v20-part-j.md` and `goal20-draft.md` K
unified requirements 7–9.

## 3. Verdict summary and expected distribution

| System | pass | pass · large | should split | should merge | Total |
|---|---:|---:|---:|---:|---:|
| `cadr-agent` | 28 | 13 | 0 | 0 | 41 |
| `cadr-ai` | 46 | 15 | 0 | 0 | 61 |
| `cadr-cli` | 90 | 27 | 0 | 0 | 117 |
| `cadr-core` | 7 | 0 | 0 | 0 | 7 |
| `cadr-evals` | 3 | 5 | 0 | 0 | 8 |
| `cadr-protocol` | 3 | 2 | 0 | 0 | 5 |
| `cadr-server` | 7 | 4 | 0 | 0 | 11 |
| `cadr-storage` | 2 | 0 | 0 | 0 | 2 |
| `cadr-tui` | 30 | 19 | 0 | 0 | 49 |
| **Total** | **215** | **85** | **0** | **0** | **299** |

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
`13cbf77df` the actual comparison is:

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
baseline `13cbf77df2396303013a41646bcfa77b4271ae56` records all 38 providers and
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

### Part L upgrade routing (v0.86.1, goal 18 runbook step 10)

Goal 18 Part L upgraded the fixed baseline from `74caa2649` to `13cbf77df`
(v0.86.1). This subsection is the required retrospective on how the §1a
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
