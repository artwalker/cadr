# Production dependency audit

Audit date: 2026-08-01.

## Production systems

| System | Direct dependencies | Decision |
|---|---|---|
| `cadr-ai` | `cl+ssl` | Retained solely as the permitted system-OpenSSL TLS binding. HTTP itself is native. |
| `cadr-agent` | `cl-ppcre`, `sqlite`, `cadr-ai` | `sqlite` is the ASDF system supplied by `cl-sqlite`, the second registered self-build exception; it binds the system SQLite library through CFFI. `cl-ppcre` is the explicitly deferred full regex engine used by JSON Schema `pattern`; `cadr-ai` is in-repository. |
| `cadr-cli` | `cl-ppcre`, `cl-jpeg`, `png-read`, `cadr-agent`, `cadr-tui` | `cl-ppcre` is used directly by glob/grep; `cl-jpeg` and `png-read` are the approved pure-Lisp replaceable image codecs; the other systems are in-repository. |
| `cadr-tui` | `sb-posix` | SBCL contrib used for terminal state; not a third-party dependency. |
| `cadr-storage` | `cadr-agent` | In-repository facade over the already audited SQLite repository/storage implementation; no new dependency. |
| `cadr-server` | `cadr-ai`, `sb-bsd-sockets`, `sb-posix` | In-repository protocol/runtime plus SBCL's Unix-socket/process contribs; no new third-party dependency. |
| `cadr-evals` | `cadr-cli` | In-repository behavioral harness and runners; no new third-party dependency. |

ASDF/UIOP, `sb-thread`, `sb-bsd-sockets`, `sb-posix`, `sb-gray`, and SBCL
Unicode/UTF-8 facilities are implementation-provided and do not add external
production packages.

## Registered self-build exceptions

The complete exception list is:

1. `cl+ssl`, which binds the system OpenSSL library. The project implements
   HTTP itself and does not implement cryptography.
2. `cl-sqlite` (ASDF system `sqlite`), which binds the system `libsqlite3`.
   The project implements the storage/repository contract and schema behavior,
   but does not reimplement the SQLite engine or its FFI binding.

`cl-ppcre` is an explicitly authorized deferral for a complete regular
expression engine, not a third registered self-build exception.

## Pure-Lisp replaceable production dependencies

The user authorized the following category for Goal 8 Part B before any build
dependency was added:

| Direct system | Pinned Quicklisp release | Purpose | Audited closure |
|---|---|---|---|
| `cl-jpeg` | `cl-jpeg-20230214-git` | Decode and encode JPEG pixels for baseline image conversion/resizing | ASDF only |
| `png-read` | `png-read-20170830-git` | Decode PNG scanlines, filters, and color data for baseline image conversion/resizing | `babel`, `chipz`, `iterate` |

These are pure Common Lisp implementation libraries with no system ABI,
cryptographic trust, database-engine, or sandbox boundary. They are therefore
registered as **pure-Lisp replaceable dependencies**, not as additional
self-build exceptions: an in-tree implementation may replace them later
without changing cadr's public contracts.

The complete `png-read` closure in the audited Quicklisp distribution is:

- `png-read` → `babel`, `chipz`, `iterate`;
- `babel` → `alexandria`, ASDF, `trivial-features`;
- `chipz` → ASDF;
- `iterate` → ASDF.

`babel`, `alexandria`, `trivial-features`, and `iterate` were already present
through the registered `cl-sqlite` closure. `chipz` is the only newly admitted
transitive system. ASDF is implementation-provided. This authorization was
recorded before `cadr-cli.asd` was changed, as required by the dependency gate.

## Explicitly enabled debugging service

Goal 10 Part D separately authorized Slynk for the opt-in `--slynk <port>`
runtime REPL. It is not a self-build exception or a pure-Lisp replaceable
library: it is a debugging service that permits arbitrary in-process Common
Lisp evaluation and is therefore a distinct security-relevant category.

The audited snapshot is Quicklisp 2026-01-01 `sly-20260101-git`, upstream
commit `e01c7b4b`, archive MD5 `129945ec9a674a1efe353e2d3742fb00`.
The complete admitted closure is:

- `slynk/mrepl` → `slynk` → ASDF;
- the SBCL backend may `require` implementation contribs, which are not
  third-party systems.

`slynk/fancy-inspector`, `slynk/arglists`, `slynk/profiler`,
`slynk/stickers`, and every other contrib remain excluded. Production builds
preload only `slynk/mrepl` into the native image; a source checkout loads it
only after the explicit `--slynk` option. Both build and deterministic test
entry points use a fresh empty temporary `HOME` while preserving the resolved
absolute `QUICKLISP_SETUP`, preventing build-user `.slynkrc` or `.slynk.lisp`
side effects from entering the image or tests.

## Browser-executed session-export assets

Goal 13 Part C separately authorized two browser scripts copied byte-for-byte
from immutable blobs already present in the repository object database.  They
are embedded only in the standalone HTML produced by `/export`; they are not
ASDF systems, add no Lisp/FFI/subprocess runtime closure, and execute only in
the user's browser when the exported file is opened.

| Artifact | Version | License | Git blob | SHA-256 | Bytes |
|---|---|---|---|---|---:|
| `marked.min.js` | 18.0.5 | MIT | `9d79575e45d0f6b88158097f5f4622ab938d76d9` | `d5487edc7258b404bfa74c393d74a6393155f02517bd5e7e77cd64f8187f39a0` | 42,882 |
| `highlight.min.js` | 11.9.0 (`f47103d4f1`) | BSD-3-Clause | `5d699ae6a4cfc9544a22a9ac394b01db2e5abd4f` | `837a6fa5b0c736b52bbde2b2b6190f305da3fc9ed41681db5321507057b5c846` | 121,727 |

Both minified files retain their complete upstream header comments, including
copyright statements, license identifiers, and the Marked source URL.  No
compression or build-time transform strips those notices.  The five export
template/assets are read while `cadr-agent` loads and retained as strings in
the saved SBCL image, so the release binary does not read the source asset
directory at runtime.  The generated HTML has no external script, stylesheet,
font, image, fetch, XHR, WebSocket, EventSource, or worker import; source URLs
inside preserved license comments are inert and cause no network request.

## Ported source: grok-mermaid@0.2.2 (goal 19 Part B)

Goal 19 ports the baseline Mermaid renderer into Common Lisp as a pure-Lisp
implementation.  The port is a **source port, not a runtime dependency**:
`grok-mermaid@0.2.2` enters neither the ASDF closure nor the release binary;
the binary ships the Common Lisp files under `src/cadr-tui/mermaid/` instead.
The artifact is retained in-repo only as the audited port source and golden
reference:

| Field | Value |
|---|---|
| Artifact | `grok-mermaid@0.2.2` (dependency-free ESM, 11 dist files, 4,224 lines) |
| Registry | `https://registry.npmjs.org/grok-mermaid/-/grok-mermaid-0.2.2.tgz` |
| SHA-256 | `61f98236a93be5f0b4f8caeb9956a728dc22b275d012b190639d3c03ae942934` |
| License | Apache-2.0 (standard, unmodified 205-line text) |
| License copy in repo | `docs/third-party/grok-mermaid-LICENSE.txt` |
| Retained artifact | `test/fixtures/mermaid-golden/grok-mermaid-0.2.2.tgz` |
| Source chain | xai-org/grok-build `crates/codegen/xai-grok-markdown/src/mermaid.rs` (Copyright 2023-2026 SpaceXAI) → TypeScript port (Copyright 2026 Alexey Zaytsev) → Common Lisp port by the cadr authors |
| Port relationship | `src/cadr-tui/mermaid/*.lisp` are direct ports (module headers carry `grok-mermaid@0.2.2 dist/*.js:NN-MM` provenance); `width-data.lisp` is mechanically converted by `scripts/gen-mermaid-width-data.py`; golden fixtures are generated by `scripts/gen-mermaid-golden-data.py` from the reference output of the retained artifact |

Per the 2026-08-12 adjudication, this is a Common Lisp port under
Apache-2.0 with no new ASDF system, FFI binding, subprocess, or network
fetch.  Release binaries must ship `THIRD-PARTY-NOTICES` with the two
copyright lines, the Apache-2.0 full text, and the port modification
statement (goal 19 Part B, merged with goal 18 Part G release preparation).

## Golden fixture: marked@18.0.5 (goal 19 Part C)

The mermaid markdown transformer goldens are produced by
`scripts/mermaid-transform-golden.mjs` using the same `marked@18.0.5`
block lexer the baseline transformer imports.  The tarball is a **test
fixture only**: it is not loaded by ASDF, not linked into the release
binary, and not executed in the cadr process.

| Field | Value |
|---|---|
| Artifact | `marked@18.0.5` |
| Registry | `https://registry.npmjs.org/marked/-/marked-18.0.5.tgz` |
| SHA-256 | `7d0ea56f8c29c0e6dec5665e62ad8089136819ca7028612e52301c2ba279dac2` |
| License | MIT |
| License copy in repo | `docs/third-party/marked-LICENSE.txt` |
| Retained artifact | `test/fixtures/mermaid-golden/marked-18.0.5.tgz` |
| Nature | Offline golden generator input. Distinct from the already-audited `marked.min.js` 18.0.5 browser embed used by `/export`. |

## Test and exception-transitive systems

- `fiveam`: assertions and ASDF `test-op`.
- `babel`, `flexi-streams`, `trivial-gray-streams`: independent octet and
  fragmented-stream fixtures.
- `usocket`: loopback HTTP test server.
- `bordeaux-threads`: test-side concurrency and historical comparison only.

`cl+ssl` itself transitively loads CFFI, `trivial-gray-streams`,
`flexi-streams`, `bordeaux-threads`, `usocket`, and their utilities in the
Quicklisp distribution. This transitive closure is accepted as part of the
explicit TLS-binding exception; none is a direct production-system dependency
or referenced by production source.

`cl-sqlite` directly loads `iterate` and `cffi`. On the audited Linux/SBCL
Quicklisp distribution, CFFI's transitive closure is `alexandria`, `babel`,
and `trivial-features`; Babel in turn depends on Alexandria and
trivial-features. CFFI conditionally uses ASDF/UIOP on Darwin, which is
implementation-provided. This entire closure, plus the system `libsqlite3`
shared library, belongs to the `cl-sqlite` exception. Production source calls
the `sqlite` package but does not call CFFI or those transitive utility systems
directly.

## Dependency authorization gate

Every future goal must audit proposed direct and transitive dependencies during
Part A. Discovery of any new third-party dependency marks that goal `blocked`
until the user explicitly authorizes it and this audit plus the README
exception list are updated. Adding a dependency first and seeking approval
afterward is a process violation.

## Removed production dependencies

- `dexador` → native HTTP/1.1 client.
- `com.inuoe.jzon` → native JSON parser/stringifier.
- `clingon` → native fixed-contract CLI parser.
- `cl-jschema` → native tool-schema validator.
- `bordeaux-threads` → `sb-thread`.
- `babel`, `flexi-streams`, `usocket` → SBCL facilities in production.

Reproduce the source audit with:

```bash
rg -n 'dexador|com\.inuoe\.jzon|clingon|cl-jschema|bordeaux-threads:|\bbt:|babel:|flexi-streams:|usocket:' \
  src *.asd scripts
```

Expected `src/` result: no matches. Matches under test-system dependency lists
are intentional and listed above. The ASDF transitive closure of `cl+ssl` is
separately covered by the TLS exception; the `sqlite:` production references
and CFFI closure are covered by the `cl-sqlite` exception.
