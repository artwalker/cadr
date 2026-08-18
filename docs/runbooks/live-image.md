# Live image: reload vs rebuild

Product loop for a **running** cadr (`./cadr --slynk <port>` or a
normal TUI). This is not load-and-probe of a fresh SBCL.

## Disk extensions reload

Files under `~/.cadr/agent/extensions/` and a trusted project's
`.cadr/extensions/` are read at startup and again on `/reload`
(`docs/extensions.md`). `/reload` re-reads settings, keybindings,
extensions, skills, prompt templates, themes, and context files
without killing the process. A reload load failure keeps the last
good extension set.

`examples/extensions/reload-runtime.lisp` is the same path:
`extension-context-reload`.

Changing a disk extension and `/reload` is enough. Do not treat
that as a rebuild of cadr itself.

## Host-in-image changes need a rebuild

Code that is compiled into the `./cadr` image (`src/cadr-agent`,
`src/cadr-cli`, `src/cadr-tui`, `src/cadr-ai`, …) is not reloaded
by `/reload`. After editing those files:

1. Rebuild the image (`./scripts/build.sh` or the project’s usual
   image target).
2. Restart the process.
3. For a defect already showing on a running cadr, attach Slynk
   first (`docs/development-policy.md` §6.1). Rebuild is for the
   next image, not the first diagnosis.

Slynk eval can patch a running image for diagnosis. That patch dies
with the process. Ship the change in source and rebuild.

## Restarts

Tool failure on a live agent uses the existing
`retry-tool-call` / `skip-tool-call` / `abort-agent-run`
(`src/cadr-agent/loop/tool-execution.lisp`). Do not add a
`restart-case` on a pairable user-visible failure so the code
“looks native”.
