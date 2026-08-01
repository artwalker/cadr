# Goal 10 Part D acceptance

Date: 2026-08-01. Status: implemented, verified, committed, and re-frozen.

## D1: restartable tool failures

Commit `55094c9d7` implements the approved condition/restart contract:

- executor and schema failures create `cadr-agent:tool-execution-error` while
  the failure stack is live;
- `retry-tool-call`, `skip-tool-call`, and `abort-agent-run` are available only
  in that dynamic extent;
- `:tool-call-error` is extension lifecycle event 34 and never enters the
  agent-event, JSON, or RPC wire surfaces;
- retry re-enters `:tool-call-before`, resolves the effective tool again, and
  revalidates every replacement argument object;
- one logical call emits one `:tool-execution-start`, one
  `:tool-call-after`, and one `:tool-execution-end`; parallel restart state is
  call-local;
- with no selecting hook, the existing error result text and all existing
  observable event behavior remain unchanged.

The full `cadr-agent` suite passed `674 checks / 674 pass / 0 skip / 0 fail`.
The regression names are:

- `GOAL10-TOOL-EXECUTION-CONDITION-KEEPS-STACK-LIVE-AND-RETRIES-WITH-NEW-ARGUMENTS`
- `GOAL10-SCHEMA-FAILURE-SKIP-PRESERVES-THE-OLD-RESULT-TEXT`
- `GOAL10-ABORT-RESTART-COMMITS-ERROR-WITHOUT-ANOTHER-PROVIDER-REQUEST`
- `GOAL10-TOOL-CALL-ERROR-HOOK-RETRIES-AT-THE-LIVE-CONDITION-SITE`
- `GOAL10-PARALLEL-TOOL-ERROR-RESTARTS-ARE-CALL-LOCAL`
- `GOAL10-SCHEMA-RETRY-REVALIDATES-EVERY-ATTEMPT-AND-FINALIZES-ONCE`
- `GOAL10-EXTENSION-EVENT-SET-IS-REFROZEN-AT-THIRTY-FOUR`

## D2: opt-in Slynk REPL

Commit `65052f7a6` implements `--slynk <port>` with these fixed properties:

- default off, no config/environment activation path;
- strict decimal port range `1..65535`;
- explicit `slynk:create-server` arguments `:interface "127.0.0.1"`,
  `:style :spawn`, and `:dont-close t`;
- bind failure is fatal; normal and exceptional exits stop the server and
  clear the active agent;
- `cadr-cli:active-agent` returns the live agent under a mutex;
- an actual Slynk protocol client inspected the active session and redefined a
  tool function; the next call changed while agent identity, session identity,
  and history were retained;
- the built native `./cadr` image was also started with `--slynk 45433 --mode
  rpc`; a separate Slynk wire client evaluated the live image, observed
  `cadr-cli:active-agent`, and read the exact `0.2.0` release identity; EOF
  stopped the process and `ss` confirmed that the listener was gone;
- the source path loads Slynk only when enabled, while production build
  preloads only `slynk/mrepl` into the native image.

`GOAL10-SLYNK-INIT-IS-ISOLATED-FROM-THE-BUILD-USERS-HOME` places a side-effecting
`.slynkrc` in the parent build user's HOME, loads Slynk in a child with a fresh
empty HOME and the resolved absolute Quicklisp setup, and proves the sentinel
was not created. The same empty-HOME boundary is implemented by `build.sh` and
`scripts/test-cl.sh`.

The complete deterministic entry point `./scripts/test-cl.sh` passed after
both implementations. No provider credential or user settings were read.

## Dependency decision

The pre-authorized snapshot and closure are unchanged:

```text
Quicklisp 2026-01-01 sly-20260101-git
upstream commit e01c7b4b
archive MD5 129945ec9a674a1efe353e2d3742fb00
slynk/mrepl -> slynk -> ASDF
```

No additional Slynk contrib, third-party system, C ABI, database, or
cryptographic dependency was admitted.

## Re-freeze

Reproduction commands:

```bash
sed -n '/#:define-tool/,/#:make-extension-hook-result/p' \
  src/cadr-agent/package.lisp | sha256sum
sed -n '/(defparameter +extension-hook-events+/,/    :user-bash))/p' \
  src/cadr-agent/extensions.lisp | sha256sum
```

Results:

```text
bb4665245ef9df19b274535071fcc5f6e56c79ab29db2152cd41afaa4df3b1e0  extension exports
12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a  34-event set
```

Frozen implementation object IDs:

```text
bc2c6e079e69e313a6806ca72d520a8f2116f2ce  src/cadr-agent/package.lisp
44cd0609bc31cbdc609190202f9c190422365674  src/cadr-agent/tool.lisp
798347aea9c74aded413ba7e452d3dca62b53cb4  src/cadr-agent/loop.lisp
2ecd00a85c043193e35d5603015376564d460f2c  src/cadr-agent/extensions.lisp
827c3edd901b5193d4dad3d06dc0827f585839a8  cadr-cli.asd
3501bff3c5b1bfd6729deb75d783d1ba46f921ab  src/cadr-cli/arguments.lisp
431dc8c8a2cd19e46b7fa6acd1901fb0e5324040  src/cadr-cli/remote-repl.lisp
308f6f168273fcf55c75eae5eac74039a8b0a567  src/cadr-cli/main.lisp
a21511b7c086baf84ce191bd528ed7bc5575abaf  src/cadr-cli/package.lisp
8056d085b06e86a280d97a4d34a36ac4430d595c  scripts/test-cl.sh
c60433c7befb591b19ccc86bfd60dedb4dff7285  build.sh
65c7a511cf1a61c952a36b80873a531109a56384  build.lisp
```

`src/cadr-cli/main.lisp` and `cadr-cli.asd` were re-frozen after the separately
approved Part E release-identity change and the user-directed visual/output
follow-up. The latter adds only the internal TUI status consumer and base-screen
regression system entry. The Slynk branch, listener policy, cleanup path, and
active-agent surface are unchanged.

Any later extension event, restart semantic, Slynk surface, dependency, or
listener-policy change requires a new written proposal and explicit user
approval.
