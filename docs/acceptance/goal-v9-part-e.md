# Goal 9 Part E stage report

> Status: the pre-release wrap-up, the repository hygiene and the final local
> gates are all complete; no tag has been created, awaiting acceptance of
> Goal 9 as a whole.

## 1. A single source for the version

The root `version.sexp` holds the current development version `0.1.0`. All
eight production ASDF systems use `(:read-file-form "version.sexp")`; a helper
inside `cadr-ai` supplies the same value to:

- `cadr --version` and `cadr-server --version`;
- the TUI startup banner;
- the HTTP User-Agent;
- Radius machine registration.

No new public export was added.
`GOAL9-PART-E-PRODUCTION-VERSION-HAS-ONE-SOURCE` was red at `1/0/0/1` first,
while the file did not exist, and green at `28/28/0/0` after implementation;
`GOAL9-PART-E-VERSION-REACHES-SERVER-CLI-AND-RADIUS-REGISTRATION` is
`2/2/0/0`, and it checks a real Radius payload. Grepping the production
source/ASD/build/scripts for the old `0.1.0` literal gives zero hits.

This goal keeps `0.1.0` and creates no tag. The suggestion is to use `0.2.0`
after Goal 10 has completed the re-lock to a stable upstream, removed the
established `PI_CL_*` compatibility window and passed the release gate; that
coincides exactly with the removal version of the existing compatibility
contract. The actual version and tag are still the user's decision.

## 2. Changelog, documentation and cleanup

- A root `CHANGELOG.md` was added, recording the Goal 1–9 milestones, the key
  fixes and the dependency/OAuth security constraints under Keep a Changelog's
  `Unreleased`.
- `docs/README.md` was added, stating the responsibilities of architecture,
  parity-map, visual-parity, test-matrix, dependency-audit, open-questions,
  progress, proposals and acceptance.
- `goal9.md` and `goal10.md` were archived as `docs/progress/goal-v9.md` and
  `goal-v10.md`. Goal 9's original byte SHA-256 stays
  `021f269a66c585dce0d0cbdf5815edde9e3032f229f7a8ec90c9cca730739aee`; for
  Goal 10, only the trailing whitespace of one blank line was cleared so that
  it passes the repository whitespace gate, the semantic text is unchanged, and
  the archived SHA-256 is
  `1dafba73f6461e94a0be2906a19cc444087e07afe13f765f94b3a99d8cba862c`.
- Before the cleanup, the inventory of files and symlinks under `packages/` was
  empty; only `rmdir` was used, to delete the seven empty directories
  `agent/ai/coding-agent/mom/pods/tui/web-ui` and the empty `packages/` root.
- One regenerable bytecode file was deleted:
  `scripts/__pycache__/goal9-a2-pty-driver.cpython-312.pyc`, followed by the
  now-empty cache directory; no source code and no user data was deleted.
- `.gitignore` gained the local goal drafts, `.codex`, Obsidian, `.tmp-home`
  and Python bytecode. The root `.obsidian/`, `docs/.obsidian/`, `.tmp-home/`
  and the goal 6–8 drafts are retained in place.

`GOAL9-PART-E-REPOSITORY-HYGIENE-AND-NAVIGATION-CONTRACT` was red first,
exposing the missing changelog/index/ignore/archive and the leftover
directories; after convergence it is `35/35/0/0`.

## 3. Full verification

`./scripts/verify.sh` was executed with credentials, taking `3m21s`:

| Stage | Result |
|---|---|
| deterministic FiveAM | PASS, 7019/7019, 0 skip, 0 fail |
| isolated cadr build | PASS, repeating 7019/7019/0/0 |
| isolated cadr-server build | PASS, repeating 7019/7019/0/0 |
| six native/process/PTY/socket harnesses | all PASS; terminal lifecycle 3/3 |
| credential-gated FiveAM | 8 items / 7 run / 7 pass / 1 Anthropic skip / 0 fail; 32 checks / 31 pass / 1 skip / 0 fail |
| DeepSeek live TUI | PASS |

`./build.sh` and `./build-server.sh` were then run separately in the root
working tree; each of them repeats `7019/7019/0/0`, and each degrades normally
to an uncompressed image because this machine's SBCL does not carry
`sb-core-compression`. Final evidence:

```text
cadr 0.1.0
cadr-server 0.1.0
cadr        66462712 bytes mode=755
cadr-server 57122504 bytes mode=755
```

Raw logs:

- `/tmp/cadr-goal9-part-e-verify.log`
- `/tmp/cadr-goal9-part-e-build.log`
- `/tmp/cadr-goal9-part-e-build-server.log`

New third-party dependencies: `0`. The Part took about 1 hour in total,
covering the audit, the red/green tests, the cleanup and five full
deterministic gate runs; the product does not provide an auditable exact
per-Part token count, and no estimate was fabricated. This Part is recorded in
the ledger by its own commit.

## 4. Closeout independent-review correction

At closeout, two independent `test-cl.sh` processes ran concurrently, and one
of them consistently exposed `623 checks / 622 pass / 0 skip / 1 fail` in
`ALL-PARALLEL-TOOLS-FINISH-BY-COMPLETION-BUT-RESULTS-STAY-IN-SOURCE-ORDER`:
the test releases the slow executor from inside the fast executor while the
fast one's `:tool-execution-end` has not been emitted yet, so under load the
slow one may emit its end event first. The product's parallel logic did not
fail; it was the test's handshake that synchronized only the executor body and
not the event boundary it actually asserts on.

The gate was changed so that the slow executor is released by the agent's real
fast `:tool-execution-end` callback; the slow one can therefore finish only
after the fast event has been observed, without depending on scheduling speed
or on sleep. After the correction:

- targeted `cadr-agent`: `623/623/0/0`;
- the four `cadr-agent` suites re-checked under concurrent stress with separate
  temporary roots: all four runs are `623/623/0/0`;
- final `test-cl.sh`: `7040/7040/0/0`.

The same closeout audit also corrected two renamed OAuth test references in
parity-map, and synchronized the user's Part B closure adjudication, which had
already happened, into acceptance, visual-parity and the README. No production
code was modified and no dependency was introduced.

The audit then found two intersection gaps in the A2 evidence: the existing
editor/completion/overlay gates use virtual input rather than a real PTY; and
the existing process modes and the faux provider belong to two separate test
sets. After the correction, `scripts/goal9-a2-pty.sh` adds full snapshots of 6
editor frames, 5 completion frames and 5 settings overlay frames inside a
separate `openpty` process, which together with lifecycle sum to 6/6; the three
`GOAL9-A2-PROCESS-FAUX-*` gates lock down the actual faux text, the exact
JSONL event sequence and the RPC round trip inside a separate SBCL subprocess,
for 21/21 in total. Both are test/evidence corrections, the production source
diff is zero, and the final suite grows to `7040/7040/0/0`.

After the test correction was committed, the full `./scripts/verify.sh` was run
again and finally exited `0`: the root deterministic gate, the isolated `cadr`
build and the isolated `cadr-server` build are `7040/7040/0/0` in all three;
the six retained native/process/PTY/socket/TUI harnesses are all green, with A2
PTY at 6/6; live is
`8 items / 7 run / 7 pass / 1 Anthropic skip / 0 fail` and `32 checks / 31 pass /
1 skip / 0 fail`, and the DeepSeek live TUI also passed. Raw log:
`/tmp/cadr-goal9-closeout-verify.log`.
