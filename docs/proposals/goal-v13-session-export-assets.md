# Goal 13 session-export vendored asset proposal

Status: **blocked pending explicit dependency authorization**.

Goal 13 Part C has closed presentation clusters 1–10.  The remaining cluster
is session export.  The fixed baseline does not merely style a static HTML
tree: it embeds a complete responsive application together with Marked and
Highlight.js (`packages/coding-agent/src/core/export-html/index.ts:108-174`,
`template.html:1-56`, `template.js:1-1830`).  Cadr currently emits a fixed
light nested list and does not consume the already parsed
`pageBg/cardBg/infoBg` values (`src/cadr-agent/session.lisp:2124-2235`,
`src/cadr-cli/interactive-services.lisp:2573-2597`).

The two JavaScript files would be new third-party bytes in the Cadr release
image.  They are not ASDF systems and add no Lisp dependency closure, but the
project's dependency gate covers release content as well as load-time systems.
They therefore cannot be added under the presentation-change authorization
alone.

## 1. Requested authorization

Authorize exactly the two already-vendored browser artifacts from audit commit
`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`:

| Artifact | Version/license evidence | Git blob | Bytes | SHA-256 |
|---|---|---|---:|---|
| `vendor/marked.min.js` | file header: Marked `18.0.5`, MIT | `9d79575e45d0f6b88158097f5f4622ab938d76d9` | 42,882 | `d5487edc7258b404bfa74c393d74a6393155f02517bd5e7e77cd64f8187f39a0` |
| `vendor/highlight.min.js` | file header: Highlight.js `11.9.0`, commit `f47103d4f1`, BSD-3-Clause | `5d699ae6a4cfc9544a22a9ac394b01db2e5abd4f` | 121,727 | `837a6fa5b0c736b52bbde2b2b6190f305da3fc9ed41681db5321507057b5c846` |

The source artifact is the immutable Git blob already present in this
repository's object database, not a mutable CDN or package-manager resolution.
The Marked npm lock record independently identifies version `18.0.5` and
integrity
`sha512-S6GcvALHg6K4ohtu4E7x0a1AqhAjp6cV8KhLSyN9qVapnzJkusVBxZRcIU9AeYsbe6P1hKDusSbEOzGyyuce6w==`.
The Highlight.js vendored header is authoritative for its `11.9.0` browser
bundle; the historical package-lock entry is `10.7.3` and will not be used as
the source or silently substituted.

Runtime closure: none.  Both are self-contained browser scripts embedded into
the standalone exported HTML.  They perform no network access and require no
Node, npm, shell command, FFI library, or Lisp system at runtime.

Platform matrix: identical bytes on Linux, macOS, and Windows; execution is in
the browser that opens the exported file.  Deterministic tests will execute no
browser or network code and will verify the embedded artifact hashes, template
substitution, theme values, escaping, and session-data round trip.

## 2. Minimal implementation and file surface

If approved, implementation is limited to:

```text
cadr-agent.asd
src/cadr-agent/session.lisp
src/cadr-agent/export-html/template.html
src/cadr-agent/export-html/template.css
src/cadr-agent/export-html/template.js
src/cadr-agent/export-html/vendor/marked.min.js
src/cadr-agent/export-html/vendor/highlight.min.js
src/cadr-cli/interactive-services.lisp
src/cadr-cli/main.lisp                 # only the existing interactive /export call
test/cadr-agent/session-v2-test.lisp
test/cadr-cli/part-b-interactive-test.lisp
docs/dependency-audit.md
README.md
docs/presentation-parity.md
docs/acceptance/goal-v13.md
```

The five template/vendor assets will be read while loading `cadr-agent` and
retained as strings in the saved SBCL image.  A built root binary therefore
does not depend on the checkout at runtime.  Build and test retain their fresh
temporary HOME and isolated ASDF cache; no lifecycle script or package manager
runs.  Tests will prove the built image can export after the source asset
directory has been made unavailable.

The exporter gains optional theme data while its existing two-argument call
remains valid.  Interactive `/export` passes the resolved theme and exact
`pageBg/cardBg/infoBg`; non-interactive CLI and RPC export use deterministic
baseline-derived defaults.  Session entries, IDs, parent links, message text,
tool results, payloads, and wire events do not change.

Any need to add another third-party asset, ASDF system, subprocess, network
fetch, or file outside this list returns the goal to blocked before code is
changed.

## 3. Alternatives considered and rejected

| Alternative | Reason rejected |
|---|---|
| Keep the current server-rendered list and apply only three background colors | Closes the color rows cosmetically but leaves the audited responsive tree, branching, filters, Markdown, code highlighting, and export interactions absent.  It would make the ledger lie. |
| Load Marked/Highlight.js from a CDN | Breaks offline standalone export, introduces mutable network execution, and diverges from the baseline's vendored mechanism. |
| Write a partial ad-hoc Markdown/highlight parser | Repeats mature parsers, is observably incomplete on tables, links, fenced languages, nested lists, and sanitizer edges, and expands a presentation-only goal into a parser project. |
| Reimplement the complete browser renderer in Common Lisp | Still requires equivalent browser interaction code, has a much larger verification surface, and buys no product capability over the audited baseline assets. |
| Use the package-lock Highlight.js `10.7.3` artifact | It is not the bytes the audited export template embeds; substituting versions would invalidate exact baseline evidence. |

## 4. Requested ruling

Approve or reject separately:

1. **Marked asset**: authorize only the `18.0.5` blob and hash above.
2. **Highlight.js asset**: authorize only the `11.9.0` blob and hash above.
3. **Embedding mechanism and file surface**: authorize the load-time embedding,
   dependency-audit/README registration, and listed files only.

No session-export implementation will begin before all three are approved.
