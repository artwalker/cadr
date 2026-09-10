GOAL: Make `scoped-models-enabled-set` strictly faster on fair Friend-MachineD remesure without changing membership or id order.

SCOPE: Exclusive worktree /tmp/cadr-g27-enabled-set. Product enabled-set and its two call sites in `src/cadr-cli/interactive/selectors/models.lisp` only. Copy tip harness. Do not dirty /root/projects/cadr.

CONTEXT:
- `scoped-models-enabled-set` builds an EQUAL hash table. Callers `gethash` in `scoped-models-sorted-ids` and `scoped-models-selector-rebuild-items`.
- Goal 26 :size hint slowed to 1.915×. Shared empty table 1.670× and is unsafe. Do not repeat those.
- Allowed knife: a cheaper membership structure, and update both call sites so enabled-p and sorted id order match HEAD. Lists are length 0-3.
- Standing: /root/projects/cadr/.orchestrate/goal27/preferences.md

ACCEPTANCE:
- Behavior: same enabled membership and same append order as HEAD `gethash`.
- Remesure `--only-enforce cli_selectors.scoped_models_enabled_set`. Slices unset. SYNC_TIP_PY.
- Keep only if strictly faster than HEAD. Prefer ≤1.0×. Full revert otherwise.
- /tmp/g27-enabled-set-REPORT.md + decisions.tsv + patch if kept.

FORBIDDEN: no gt/rebase/force-push; no dirty tip; no shared mutable empty table; no leftover win.

STANDING: read preferences.md verbatim and obey
