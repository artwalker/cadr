# Production dependency audit

Audit date: 2026-07-31.

## Production systems

| System | Direct dependencies | Decision |
|---|---|---|
| `cadr-ai` | `cl+ssl` | Retained solely as the permitted system-OpenSSL TLS binding. HTTP itself is native. |
| `cadr-agent` | `cl-ppcre`, `sqlite`, `cadr-ai` | `sqlite` is the ASDF system supplied by `cl-sqlite`, the second registered self-build exception; it binds the system SQLite library through CFFI. `cl-ppcre` is the explicitly deferred full regex engine used by JSON Schema `pattern`; `cadr-ai` is in-repository. |
| `cadr-cli` | `cl-ppcre`, `cl-jpeg`, `png-read`, `cadr-agent`, `cadr-tui` | `cl-ppcre` is used directly by glob/grep; `cl-jpeg` and `png-read` are the approved pure-Lisp replaceable image codecs; the other systems are in-repository. |
| `cadr-tui` | `sb-posix` | SBCL contrib used for terminal state; not a third-party dependency. |

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
