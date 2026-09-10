GOAL: Make the three `cli_support.write_*` metrics strictly faster on fair Friend-MachineD remesure without changing replaced file bytes or atomic rename.

SCOPE: Exclusive worktree /tmp/cadr-g27-atomic-write. `src/cadr-core/atomic-file.lisp` and the cadr-cli wrapper only. Copy tip harness including the Goal 26 fair remeter if it is only on the dirty tip (`scripts/goal20-paired-paths.lisp` and `.mjs`). Do not dirty /root/projects/cadr.

CONTEXT:
- HEAD paired ratios about 3.329× / 5.760× / 10.994×. Isolated hello already ~129µs vs leftover 140µs.
- Goal 26 posix invent best 1.585× / 1.777× / 1.341× was reverted only because Goal 26 keep bar was ≤1.0×. Goal 27 lands a strictly faster keep even if still above 1.0×, if bytes and atomicity match.
- Required: temp sibling plus rename. Missing parent directories still created. Nested `a/b/c` still works. Empty file still created. Overwrite replaces bytes.
- `:durability :flush` stays unless you prove leftover `writeFileSync` does not fsync and dropping flush does not change bytes. Isolated hello did not move when flush was skipped, so do not spend the hypothesis on flush alone.
- Preferred first knife: skip `ensure-directories-exist` when the parent already exists, still create on ENOENT. Then posix open/write/rename if that is still faster and bytes match.
- Standing: /root/projects/cadr/.orchestrate/goal27/preferences.md

ACCEPTANCE:
- Behavior: hello/overwrite/empty bytes match HEAD. Missing parent still created. Rename atomicity stays.
- Remesure the three write keys. Slices unset. SYNC_TIP_PY. Reuse pi JSON from `/tmp/g26-support-invent-remesure7` if leftover slot unchanged.
- Keep only if all three are strictly faster than HEAD, or keep a knife that speeds all three without slowing any. Full revert otherwise.
- /tmp/g27-atomic-write-REPORT.md + decisions.tsv + patch if kept.

FORBIDDEN: no gt/rebase/force-push; no dirty tip; no leftover-only win; no dropping rename atomicity.

STANDING: read preferences.md verbatim and obey
