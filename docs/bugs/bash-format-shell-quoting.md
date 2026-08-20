# Bug — bash tool surfaces FORMAT + bash `(` syntax error

**Status**: closed as **not-product** (class 1, 2026-08-21). Not G.17.

## Symptom (user-facing)

While using cadr, a bash tool call failed with output shaped like:

```text
Error: error in FORMAT: No more arguments
    /bin/bash: -c: line 19: syntax error near unexpected token `('
  /bin/bash: -c: line 19: `      (format t "gethash equal 6-char (hit): ~,1F
  ns/call~%"'


  Command exited with code 2
```

`Command exited with code N` is the normal cadr bash-tool footer
(`src/cadr-cli/tools/bash.lisp`). The body is stderr/stdout from the
child. So the **product surface** is: bash tool ran a command that
exit 2'd; the interesting part is **who constructed that command**.

## What is known

- The string `gethash equal 6-char (hit)` is **not** in shipped cadr
  product sources (searched 2026-08-21).
- The bash error is classic: Lisp `(format t "… (hit): …")` was fed to
  `/bin/bash -c` without safe quoting; `(` broke the shell.
- `error in FORMAT: No more arguments` is SBCL: `~,1F` ran without its
  float argument (often because the Lisp form was truncated by the
  same quoting failure).

## Hypotheses (executor must classify)

1. **Model-emitted bad bash** (agent asked bash to run ad-hoc SBCL /
   inline Lisp). Then: not a cadr core defect; optional UX/docs only.
2. **Product or extension path** builds/runs a microbench or eval
   script that embeds this FORMAT line into `bash -c`. Then: fix that
   path (write a `.lisp` file + `sbcl --script`, or correct quoting).
3. **Working-tree / agent harness leftover** from load knives (hash /
   gethash microbench) invoked by mistake. Then: remove or quarantine
   the harness; do not leave runnable broken scripts on PATH.

## Classification

**Class 1 — model-emitted bad bash.** Not a cadr core defect.

Evidence:

- `gethash equal 6-char (hit)` is absent from `src/` (rg 2026-08-21).
- The only live hit is user paste in
  `~/.cadr/agent/sessions/01a02029-42cf-7677-8079-249dd991d434.jsonl`
  (the user asking "这个啥情况"); that JSONL has no matching tool
  `command` field. Concurrent load-knife sessions were writing
  gperf/`gethash` microbenches as **bash tool input**.
- Shipped wrapper (`src/cadr-cli/tools/bash.lisp` `run-bash-command`)
  is `setsid` → `/bin/bash -lc "$2"` with `command` as argv `$2`.
  Inner `/bin/bash: -c: line 19` plus SBCL `error in FORMAT: No more
  arguments` is the **model's** script: Lisp `(format t "… (hit): ~,1F")`
  leaked into an unquoted `bash -c` body, so `(` is a shell token and
  `~,1F` ran without its float.
- Regression: `bash-wrapper-passes-paren-payload-as-argv-not-inner-minus-c`
  drives `make-bash-tool` / `invoke-tool` with the same FORMAT payload
  quoted as data; exit 0, no `unexpected token`.

No cadr FORMAT rewrite. No extra quoting layer (that would change
observable bash vs pi).

## Required delivery

1. Reproduce from a real session if possible (tool call args in the
   session JSONL that produced this stderr).
2. Classify 1 / 2 / 3 with evidence (file path or tool `command` field).
3. If 2 or 3: fix + `scripts/test-cl.sh` green + short note here.
4. If 1 only: book as model/tooling misuse, close this note as
   **not-product**, do not invent a cadr "FORMAT" rewrite.
5. Do **not** mark G.17 `met`. Do not block load knife 2 on this.

## Pointers

- Bash tool: `src/cadr-cli/tools/bash.lisp`
- Board: `goal20-state.md` `[ready]` for this bug
- Load work continues separately (knife 1 @ `108d9184a`; Friend-MachineD
  remesure still owed before knife 2).
