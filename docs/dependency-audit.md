# Production dependency audit

Audit date: 2026-07-30.

## Production systems

| System | Direct dependencies | Decision |
|---|---|---|
| `pi-ai` | `cl+ssl` | Retained solely as the permitted system-OpenSSL TLS binding. HTTP itself is native. |
| `pi-agent` | `cl-ppcre`, `pi-ai` | `cl-ppcre` is the explicitly deferred full regex engine used by JSON Schema `pattern`; `pi-ai` is in-repository. |
| `pi-cli` | `cl-ppcre`, `pi-agent`, `pi-tui` | `cl-ppcre` is also used directly by glob/grep; the other systems are in-repository. |
| `pi-tui` | `sb-posix` | SBCL contrib used for terminal state; not a third-party dependency. |

ASDF/UIOP, `sb-thread`, `sb-bsd-sockets`, `sb-posix`, `sb-gray`, and SBCL
Unicode/UTF-8 facilities are implementation-provided and do not add external
production packages.

## Test and TLS-transitive systems

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
separately covered by the TLS exception.
