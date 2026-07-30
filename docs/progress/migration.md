# cadr migration report

Date: 2026-07-30

## Scope

This change is a namespace, repository-location, and user-data migration from
the Common Lisp implementation's former identity to `cadr`. It deliberately
does not change provider protocols, agent-loop behavior, tool policy, session
semantics, extension behavior, or TUI behavior.

The repository was moved, including `.git`, from `/root/projects/pi-mono` to
`/root/projects/cadr`; it was not copied into a new history.

After the naming commits, the upstream TypeScript working tree was split into
a legacy worktree while remaining in the same object database and history.
The current tracked `cadr` tree now contains only the Common Lisp
implementation, its reference-fixture tooling, tests, and project
documentation.

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

## Legacy worktree and preserved user state

The legacy worktree was created with the required command:

```bash
git worktree add /root/projects/pi-mono -b pi-mono-legacy 48b9a05f2
```

The resulting branch is `pi-mono-legacy`, rooted at full commit
`48b9a05f2cfc3f34f749ac4a2d8d17aec0f843a1`.

Before the corresponding paths were cleared from the `cadr` worktree, the
four user-modified files were copied to the legacy worktree, compared with
`cmp`, and verified byte-identical with SHA-256:

| Path | SHA-256 |
|---|---|
| `packages/ai/src/models.generated.ts` | `701da0bb69b7f55df7b9c4cc07933c9513f9e155330642ad8c61378b533b6fe6` |
| `packages/mom/CHANGELOG.md` | `7e0277bfa9eea2eb4ceef48499207d65284274fdbe0ee23fffe03251a4bf707f` |
| `packages/mom/README.md` | `b00dd963aa1ff805d42b44c503833c7098fba3951a2b5353fcb4b08b0251ea66` |
| `packages/mom/src/agent.ts` | `ccf1751fc1221264faef0e72a7403f0f0c294ab48dab1aafb241a648ff483cf7` |

They remain modified and uncommitted on `pi-mono-legacy`; the preservation
operation did not commit them to any branch. The four `MiMo_*.md` files and
root/package-local generated Node artifacts were moved into
`/root/projects/pi-mono/`. The untracked Rust workspace was moved to
`/root/projects/pi-mono-rs/`.
`docs/.obsidian/` remained untouched in the `cadr` worktree.

The TypeScript removal is the pure-deletion commit `78018990c`: 780 files and
218,710 lines deleted, with no added, modified, or renamed path. Removed
tracked top-level entries:

- `.github/`
- `.husky/`
- `.pi/`
- `AGENTS.md`
- `CONTRIBUTING.md`
- `biome.json`
- `package-lock.json`
- `package.json`
- `packages/`
- `pi-test.sh`
- `test.sh`
- `tsconfig.base.json`
- `tsconfig.json`

The retained `scripts/` directory lost only these upstream TypeScript support
files:

- `browser-smoke-entry.ts`
- `build-binaries.sh`
- `check-browser-smoke.mjs`
- `cost.ts`
- `edit-tool-stats.mjs`
- `profile-coding-agent-node.mjs`
- `release.mjs`
- `session-transcripts.ts`
- `sync-versions.js`

`scripts/export-ts-payloads.ts`,
`scripts/export-ts-payloads.runner.ts.txt`, and all of `test/fixtures/` were
preserved byte-for-byte; this check returns no diff:

```bash
git diff --exit-code 48b9a05f2..78018990c -- \
  scripts/export-ts-payloads.ts \
  scripts/export-ts-payloads.runner.ts.txt \
  test/fixtures
```

## Commit and history evidence

| Commit | Purpose |
|---|---|
| `e3f6912d4` | Original repository HEAD before the Common Lisp migration checkpoint |
| `c07b5a668` | Frozen pre-migration Common Lisp baseline |
| `90350d9ac` | ASDF systems, packages, symbols, paths, scripts, and executable identity |
| `b8738e62f` | User-data and environment transition |
| `d0e449ad0` | README, architecture, test matrix, and migration report |
| `a7fc1b438` | Exact residual-namespace audit |
| `48b9a05f2` | Reference payload type-name regression guard |
| `78018990c` | Pure deletion of the upstream TypeScript working tree |

Both ancestry checks succeed:

```bash
git merge-base --is-ancestor e3f6912d4 HEAD
git merge-base --is-ancestor c07b5a668 HEAD
```

All ancestors of the source repository remain reachable. The fixed audit
commit `71efc6f0c1909874ec8c944637a9ae7fc0e2d508` is also present in this
repository's object database:

```bash
git cat-file -e \
  71efc6f0c1909874ec8c944637a9ae7fc0e2d508^{commit}
```

For future fixture regeneration, check out that exact object into a temporary
worktree and pass its path to `scripts/export-ts-payloads.ts` as
`--reference`. Do not substitute the moving `pi-mono-legacy` branch tip for
the pinned audit commit.

## Verification evidence

The migration baseline contained 632 Common Lisp checks. The isolated build
on SBCL 2.6.7 ran 690 checks:

| Suite | Checks | Result |
|---|---:|---|
| `cadr-ai/tests` | 256 | pass |
| `cadr-agent/tests` | 156 | pass |
| `cadr-tui/tests` | 59 | pass |
| `cadr-cli/tests` | 219 | pass |
| Total | 690 | pass |

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
  Before the pure deletion commit, Biome, tsgo, browser smoke, and web-ui
  checks passed
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

The goal's literal command is recorded here:

```bash
grep -ri "pi-cl\|pi-ai\|pi-agent\b" \
  --exclude-dir=.git \
  --exclude-dir=docs/progress .
```

GNU grep compares `--exclude-dir` with directory basenames, so
`--exclude-dir=docs/progress` does not exclude a directory whose basename is
`progress`. The equivalent command actually used for acceptance is:

```bash
grep -ri "pi-cl\|pi-ai\|pi-agent\b" \
  --exclude-dir=.git \
  --exclude-dir=progress .
```

Its complete output is the six permitted compatibility references:

```text
./README.md:| `pi-ai` | `cadr-ai` |
./README.md:| `pi-agent` | `cadr-agent` |
./README.md:| `pi-cli` | `cadr-cli` |
./README.md:| `pi-cl` | `cadr` |
./README.md:| `~/.pi-cl/` | `~/.cadr/` |
./README.md:At startup, when `~/.pi-cl/` exists and `~/.cadr/` does not, an interactive
```

Excluding the README as the sole current-tree exemption produces no output
and grep exit status `1`:

```bash
grep -ri "pi-cl\|pi-ai\|pi-agent\b" \
  --exclude-dir=.git \
  --exclude-dir=progress \
  --exclude=README.md .
```

The exhaustive exemption list and reasons:

- README relationship/thanks: required attribution and no-affiliation
  statement for the fixed reference implementation.
- README migration table and compatibility timeline: users need the former
  names to migrate paths and environment variables.
- `docs/progress/`, including this report: immutable historical evidence and
  the required migration explanation.
- CHANGELOG: no CHANGELOG remains in the current tree. Released upstream
  CHANGELOGs remain unmodified in Git history and the `pi-mono-legacy`
  worktree, where their historical product names are immutable.

A broader audit also intentionally retains `originator=pi` in the OpenAI OAuth
and Codex wire protocol plus their tests. That value is required by the fixed
reference protocol and is not a cadr product or package name. References to
`earendil-works/pi@71efc6f0c1909874ec8c944637a9ae7fc0e2d508` are retained as
the required behavioral attribution.
