# Goal 15 Part C: repair batches

## Batch 1: D05-D07 tool behavior

Commit: the batch commit containing this section.

### Result

The three tool-result defects that can change the model's next decision are
closed before composition work:

| ID | Fixed-baseline contract | Cadr implementation | Regression |
|---|---|---|---|
| D05 | `grep.ts:215-229,270-331` delegates matching to `rg --json` and preserves its streamed match order. | `src/cadr-cli/tools/grep.lisp:3-89,131-268` now consumes the same `rg` event stream instead of sorting a Lisp filesystem walk. | `GOAL15-GREP-PRESERVES-FIXED-BASELINE-RIPGREP-STREAM-ORDER` |
| D06 | `ls.ts:124-150` resolves and reads the requested directory. | `src/cadr-cli/tools/ls.lisp:11-29` passes UIOP's canonical directory-form pathname to `directory-files` and `subdirectories`. | `GOAL15-LS-RELATIVE-SUBDIRECTORY-LISTS-THE-REQUESTED-DIRECTORY` |
| D07 | `read.ts:238-243` exposes the path-bearing filesystem access error to the tool result. | `src/cadr-cli/tools/read.lisp:3-18` emits the exact baseline `ENOENT: no such file or directory, access '<absolute-path>'` copy. | `GOAL15-READ-MISSING-RELATIVE-PATH-PRESERVES-BASELINE-ENOENT-COPY` |

All three regressions were introduced red and failed on the original paths:
`grep` returned `alpha,beta`, `ls notes` listed the workspace root, and missing
`read` returned `File not found: notes/missing.txt`. They pass after the
production changes.

The differential was recaptured in both `100x32` and `48x20`. The `grep`,
subsequent `find`, and `ls` checkpoints now show the fixed baseline's
`beta.md` then `alpha.txt` stream; `ls notes` shows only `alpha.txt` and
`beta.md`; and the missing-read block has the same wrapped ENOENT copy. D05,
D06, and D07 were consequently removed from the fail-closed disposition
ledger. Remaining differences at those checkpoints are the independently
classified I01 and D01-D03 composition classes.

### Common Lisp pathname audit

The D06 root cause was confirmed: `resolve-tool-path` returned a file-form
pathname such as `#P"/cwd/notes"`; `directory-exists-p` accepted it and
returned a directory-form pathname, but the old code discarded that value and
fed the file-form pathname to UIOP enumeration, which interpreted the last
component as a name and listed its parent.

| Tool | Directory/file-form use | Disposition |
|---|---|---|
| `ls` | Directory enumeration | Fixed to retain the directory-form pathname returned by `directory-exists-p`. |
| `grep` | Directory argument passed to external `rg`; directory-form value used only for relative result paths | Correct; regression covers a relative subdirectory and the real `rg` stream. |
| `find` | Canonicalizes the root with `ensure-directory-pathname` and `truename` before walking | Correct; covered by `GOAL15-DIRECTORY-TOOL-PATHNAME-FORMS-STAY-ROOTED-IN-RELATIVE-SUBDIRECTORIES`. |
| `glob` | Its shared tree collector canonicalizes the root before walking | Correct; covered by the same regression. |
| `write` | Intentionally passes the target file pathname to `ensure-directories-exist`, which creates its parent directories | Correct; the same regression writes `notes/generated/result.txt`. |
| `edit` | Operates on a file pathname and never enumerates it as a directory | Not affected. |

Two older tests were corrected because their fixtures encoded Cadr behavior,
not the fixed baseline. The grep context/limit case now uses the exact
single-file fixture from `tools.test.ts:786-805`, so filesystem traversal
order cannot masquerade as a context assertion. The `.gitignore` fixture now
contains a `.git/` directory because the baseline delegates ignore semantics
to real ripgrep, which only applies `.gitignore` inside a repository.

### Verification

Deterministic suite before the batch commit:

```text
cadr test summary: systems=9 checks=14401 pass=14401 skip=0 fail=0
```

The full fixed-baseline analyzer accepted all 88 remaining differences only
through their explicit dispositions:

```text
render-diff analysis: aligned=6 requires-disposition=88 adjudicated=88
```

`./scripts/verify.sh` completed every deterministic stage successfully:

```text
root cadr binary freshness                       PASS
code organization gate                           PASS
real source parity ledger                        PASS
source parity drift self-test                    PASS
deterministic FiveAM                             PASS
isolated cadr build                              PASS
isolated cadr-server build                       PASS
Goal 11 performance and stability gate           PASS
native acceptance smoke                          PASS
native process modes                             PASS
migration PTY smoke                              PASS
Unix socket server smoke                         PASS
terminal lifecycle PTY                           PASS
deterministic TUI harness                        PASS
```

Its credential-gated stage returned nonzero only because
`LIVE-DEEPSEEK-EVAL-SMOKE` received `The capital of France is Paris.` where
the baseline-derived live assertion requires the model to return exactly
`Paris`. The same unchanged live assertion and failure class were explicitly
accepted by the user during Goal 14 B4; this batch does not alter the provider,
model-resolution, or eval path. The other six runnable live items passed, one
Anthropic item skipped for its missing credential, and the DeepSeek TUI live
harness passed.
