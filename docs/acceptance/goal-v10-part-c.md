# Goal 10 Part C stage report

> Status: CI has really run green in the private backup repository; the Part C implementation and tests are both committed to the ledger.

## 1. Remote gate

- Workflow: `.github/workflows/ci.yml`, triggered on push and pull request.
- Successful run: <https://github.com/artwalker/cadr/actions/runs/30685999360>
- head: `4bf24c96ea67210f7f11603e49933702f80a3dae`
- job: `verify`, conclusion `success`, duration `2m46s`.
- The workflow calls `./scripts/verify.sh` only once; there is no parallel copy of build/test logic.
- Permissions are only `contents: read`; checkout is pinned to
  `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd` with credential
  persistence disabled. There is no cache, artifact, `pull_request_target`, or
  secret reference.

Supply-chain inputs are pinned to:

| Input | Pinned value |
|---|---|
| runner | `ubuntu-24.04` |
| SBCL | `2.6.7` |
| SBCL tarball SHA-256 | `4ed82aa7d5b1d87cbafb41ab9abc87d942d18eeac2485ee5a6c46b95aa694d19` |
| Quicklisp bootstrap SHA-256 | `4a7a5c2aebe0716417047854267397e24a44d0cce096127411e9ce9ccfeb2c17` |
| Quicklisp dist | `2026-01-01/distinfo.txt` |

SBCL and Quicklisp are installed in the runner's temporary directory; `HOME`,
`QUICKLISP_SETUP`, and `SBCL` are all established from `RUNNER_TEMP` after the job
starts, which avoids reading runner or user state. Quicklisp downloads only the
systems already registered in the dependency audit. CI explicitly clears the
Anthropic, DeepSeek, and OpenAI environment credentials, and the fresh HOME has no
OAuth auth store either.

## 2. Mechanical acceptance figures

The deterministic suite of `verify.sh` actually ran three times inside the same
remote job: once at the entry point, once for the isolated `cadr` build, once for
the isolated `cadr-server` build; the three runs agree item by item:

| suite | checks | pass | skip | fail |
|---|---:|---:|---:|---:|
| cadr-ai | 1907 | 1907 | 0 | 0 |
| cadr-agent | 623 | 623 | 0 | 0 |
| cadr-tui | 1178 | 1178 | 0 | 0 |
| cadr-cli | 2700 | 2700 | 0 | 0 |
| cadr-storage | 23 | 23 | 0 | 0 |
| cadr-server | 45 | 45 | 0 | 0 |
| cadr-evals | 117 | 117 | 0 | 0 |
| cadr-protocol | 497 | 497 | 0 | 0 |
| **Total (per run)** | **7090** | **7090** | **0** | **0** |

The isolated builds do not have `sb-core-compression` on that SBCL; both images
degraded to an uncompressed build under the established contract and succeeded.
All of the following process-level/terminal-level gates are `PASS`:

- native acceptance smoke;
- native process modes;
- migration PTY smoke;
- Unix socket server smoke;
- terminal lifecycle PTY;
- deterministic TUI harness.

The terminal lifecycle log additionally confirms item by item that normal, ctrl-c,
suspend-resume, input-editor, completion, and overlay all restore the terminal; the
manual TUI harness covers overlay focus, CJK, image fallback, resize, and terminal
restore.

## 3. Credential-free live semantics and the difference from local coverage

CI injected no provider credentials, so the credential-gated FiveAM completes
normally and reports item by item:

| Item | CI result and reason |
|---|---|
| DeepSeek chat stream | skip: `DEEPSEEK_API_KEY is not set` |
| Anthropic two-turn stream | skip: `ANTHROPIC_API_KEY is not set` |
| DeepSeek print mode | skip: `DEEPSEEK_API_KEY is not set` |
| OpenAI Codex explicit model | skip: OAuth is not configured |
| DeepSeek eval smoke | skip: `DEEPSEEK_API_KEY is not set` |
| OpenAI Codex eval smoke | skip: OAuth is not configured |
| DeepSeek self-extension eval | skip: `DEEPSEEK_API_KEY is not set` |
| DeepSeek fail/fix/pass eval | skip: `DEEPSEEK_API_KEY is not set` |

The remote assertion locks `Items: 8, run: 0, pass: 0, skip: 8, fail: 0` and
`Checks: 8, pass: 0, skip: 8, fail: 0`; the independent DeepSeek live TUI likewise
skips explicitly for the missing key. It did not rewrite skip into pass. The local
`verify.sh`, which has a DeepSeek key and Codex OAuth, is still responsible for the
real live calls; Anthropic runs only when the corresponding credential is present.
This agrees with the actual effect of the upstream official CI, which injects no
provider credentials and whose live blocks naturally skip.

## 4. Problems revealed by the first clean run

The remote failures were not covered up by "rerunning"; they were resubmitted only
after being corrected item by item:

1. run `30685462833` failed before the job was created: `runner.temp` cannot be used
   in job-level `env` evaluation. Changed to `GITHUB_ENV` after the job starts, and
   a contract test forbids that invalid form.
2. run `30685517244` exposed the TUI autocomplete test hard-coding
   `/root/.local/bin/fd`. Changed so that the test itself creates a deterministic
   fake fd.
3. run `30685606013` further exposed two CLI autocomplete tests depending on the fd
   in the development machine's PATH. A shared test helper was added that explicitly
   injects a fake fd and a temporary PATH; no production code was modified.
4. run `30685837703` exposed, in the third deterministic suite, that
   `BASH-TIMEOUT-KILLS-THE-PROCESS-GROUP` equated the existence of `/proc/<pid>` with
   the process still being executable. Container PID 1 can temporarily retain an
   orphaned zombie that has already been SIGKILLed; the test now reads the proc
   state and accepts only the process disappearing or the `Z/X` terminal states,
   still rejecting any runnable state. That test was pushed again only after 12
   consecutive local runs came out green; the case was not closed by rerunning the
   original assertion.

The last two were not caught locally before because the development machine has
both `/root/.local/bin/fd` and `/usr/bin/fdfind`; the clean runner does not. After
the fix, a search of the whole test tree no longer contains a host path to a real
fd. The CI contract test
`GOAL10-PART-C-CI-WORKFLOW-IS-PINNED-MINIMAL-AND-CREDENTIAL-FREE`
now has 50 checks, locking the action SHA, the supply-chain checksums, the fresh
HOME, the existing dependency closure, the single verify entry point, the absence
of secrets/cache/artifact, and the full text of the credential-free report.

## 5. Commits and boundary

| commit | Content |
|---|---|
| `dc8052ee6` | pinned credential-free workflow and contract test |
| `0797a7472` | defer the runner paths to job execution time |
| `a1f23d8a2` | decouple the TUI autocomplete fixture from the host |
| `1691bc643` | decouple the CLI autocomplete fixture from the host |
| `4bf24c96e` | timeout process-group test decides by execution state rather than proc inode |

- New third-party project dependencies: `0`; what CI installs is the existing
  run/test closure.
- `origin` was not modified; the workflow pushes only to the private `backup`.
- The user's existing modification of `docs/acceptance/goal-v8-final.md` is neither
  staged nor committed.
- Part C implementation plus remote iteration took about 35 minutes; the system did
  not provide a per-Part auditable token count, and no estimated value was
  fabricated.
