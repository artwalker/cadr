# cadr migration report

Date: 2026-07-30

## Scope

This change is a namespace, repository-location, and user-data migration from
the Common Lisp implementation's former identity to `cadr`. It deliberately
does not change provider protocols, agent-loop behavior, tool policy, session
semantics, extension behavior, or TUI behavior.

The repository was moved, including `.git`, from `/root/projects/pi-mono` to
`/root/projects/cadr`; it was not copied into a new history.

## Naming map

| Former name | Current name |
|---|---|
| `pi-ai`, `pi-ai/tests` | `cadr-ai`, `cadr-ai/tests` |
| `pi-agent`, `pi-agent/tests` | `cadr-agent`, `cadr-agent/tests` |
| `pi-cli`, `pi-cli/tests` | `cadr-cli`, `cadr-cli/tests` |
| `pi-tui`, `pi-tui/tests` | `cadr-tui`, `cadr-tui/tests` |
| `PI-AI` package | `CADR-AI` package |
| `PI-AGENT` package | `CADR-AGENT` package |
| `PI-CLI` package | `CADR-CLI` package |
| `PI-TUI` package | `CADR-TUI` package |
| `PI-ERROR` | `CADR-ERROR` |
| `pi-cl` executable | `cadr` executable |
| `pi>` prompt | `cadr>` prompt |
| `~/.pi-cl/` | `~/.cadr/` |
| `PI_CL_PROVIDER` | `CADR_PROVIDER` |
| `PI_CL_MODEL` | `CADR_MODEL` |
| `PI_CL_BASE_URL` | `CADR_BASE_URL` |

The stable extension registration macros are external symbols of
`CADR-AGENT`: `DEFINE-TOOL`, `DEFINE-COMMAND`, `DEFINE-EVENT-HOOK`, and
`DEFINE-PROMPT-TEMPLATE`. No former package nickname or compatibility alias is
installed. This is the sole namespace break; the current extension namespace
is frozen.

## User-data migration

Startup checks the former and current data roots before parsing normal CLI
options. Migration is offered only when the former root exists and the current
root does not.

1. Interactive input and an explicit `y` or `yes` are required.
2. The complete directory is moved with a filesystem rename, preserving
   sessions, extensions, configuration, and credentials as one tree.
3. A migrated `auth.json` is forced to mode `0600`.
4. Decline, EOF, non-interactive input, and a raw `--yolo` argument fail
   closed and print a shell-quoted manual `mv` command.
5. If post-move permission repair fails, the implementation attempts to rename
   the directory back before reporting the configuration error.

`--yolo` is not a supported core option and does not authorize tool execution
or data movement. Its raw-argument check exists only at the pending migration
gate.

Session v1 and v2 headers contain no product-name field, so no session schema
alias or rewrite was required.

## Environment transition

`CADR_PROVIDER`, `CADR_MODEL`, and `CADR_BASE_URL` are authoritative. Their
former `PI_CL_*` counterparts are fallback-only during `0.1.x`; a fallback
value emits a deprecation warning and a current value wins silently. The
fallback is scheduled for removal in `0.2.0`.

The former names are assembled at runtime in the compatibility reader so the
legacy namespace does not remain as a product symbol or package alias.

## Commit and history evidence

| Commit | Purpose |
|---|---|
| `e3f6912d4` | Original repository HEAD before the Common Lisp migration checkpoint |
| `c07b5a668` | Frozen pre-migration Common Lisp baseline |
| `90350d9ac` | ASDF systems, packages, symbols, paths, scripts, and executable identity |
| `b8738e62f` | User-data and environment transition |

Both ancestry checks succeed:

```bash
git merge-base --is-ancestor e3f6912d4 HEAD
git merge-base --is-ancestor c07b5a668 HEAD
```

The current history contains 3,629 commits. All ancestors of the source
repository remain reachable.

## Verification evidence

The migration baseline contained 632 Common Lisp checks. The isolated build
on SBCL 2.6.7 ran 686 checks:

| Suite | Checks | Result |
|---|---:|---|
| `cadr-ai/tests` | 256 | pass |
| `cadr-agent/tests` | 156 | pass |
| `cadr-tui/tests` | 59 | pass |
| `cadr-cli/tests` | 215 | pass |
| Total | 686 | pass |

The isolated build command used a temporary HOME and the installed Quicklisp:

```bash
HOME="$isolated_home" \
QUICKLISP_SETUP=/root/quicklisp/setup.lisp \
./build.sh
```

The installed SBCL lacks `sb-core-compression`. The build printed the explicit
degradation notice, omitted the unsupported `:compression` keyword, produced
an ELF native executable, and `./cadr --version` printed `cadr 0.1.0`.

Additional passing checks:

```text
./scripts/acceptance-smoke.sh
  executable help, --continue, and exact --resume passed

./scripts/migration-smoke.sh
  non-interactive refusal, complete interactive move, auth mode 0600,
  extension preservation, and --continue passed

./scripts/live-openai-oauth-smoke.sh
  OpenAI Codex Responses streaming passed using an isolated temporary HOME

npm run check
  Biome, tsgo, browser smoke, and web-ui checks passed
```

Unit coverage also proves:

- only the `cadr-*` ASDF systems and packages exist;
- the frozen extension macros are exported from `CADR-AGENT`;
- the public root condition is `CADR-AI:CADR-ERROR`;
- current environment variables take precedence without consulting deprecated
  values;
- deprecated values work for one transition release and warn;
- interactive data migration moves sessions, extensions, and credentials;
- non-interactive, declined, and `--yolo` migration paths leave source data
  unchanged;
- native-image options omit `:compression` when the SBCL feature is absent.

## Residual-name audit

The required final command is:

```bash
grep -ri "pi-cl\|pi-ai\|pi-agent\b" \
  --exclude-dir=.git \
  --exclude-dir=docs/progress .
```

Final permitted matches are limited to:

- the README relationship, migration table, and compatibility timeline;
- this migration report;
- immutable historical reports under `docs/progress/`;
- released CHANGELOG history, if retained.

A broader audit also intentionally retains `originator=pi` in the OpenAI OAuth
and Codex wire protocol plus their tests. That value is required by the fixed
reference protocol and is not a cadr product or package name. References to
`earendil-works/pi@71efc6f0c1909874ec8c944637a9ae7fc0e2d508` are retained as
the required behavioral attribution.

The final zero-residual gate is not yet satisfied. The tracked-file audit
finds 190 files: 185 under the upstream TypeScript `packages/` tree, the
README, and four upstream TypeScript root/support files
(`.pi/extensions/tps.ts`, `package-lock.json`,
`scripts/browser-smoke-entry.ts`, and `tsconfig.json`).

The literal filesystem grep currently finds 7,984 files. Of those, 7,517 are
inside the untracked `pi-mono-rs/` workspace, 430 are in the upstream
TypeScript `packages/` tree, and 17 are generated `node_modules/` files. It
also reports 13 historical files because GNU grep matches `--exclude-dir`
against directory basenames: `--exclude-dir=docs/progress` does not exclude
the `progress` directory. The operational equivalent is:

```bash
grep -ri "pi-cl\|pi-ai\|pi-agent\b" \
  --exclude-dir=.git \
  --exclude-dir=progress .
```

None of these results is silently exempted. Removing or renaming the tracked
reference implementation and relocating user-owned untracked work are
repository-shape decisions that must be resolved before this report can be
declared final.
