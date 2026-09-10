GOAL: Make `scoped-model-selector-search-text` strictly faster on fair Friend-MachineD remesure without changing the returned string.

SCOPE: Exclusive worktree /tmp/cadr-g27-search-text. Product selector search text only. Copy tip harness files into the worktree. Do not dirty /root/projects/cadr.

CONTEXT:
- Function is `scoped-model-selector-search-text` in `src/cadr-cli/interactive/selectors/models.lisp`. It `format`s id, provider, qualified id, and optional name.
- Goal 26 best hop cached fragments then concatenated. 1.315× then final 1.634×. Reverted. Do not repeat that exact knife.
- Allowed knife: store the identical string on the model (or an eq cache filled before the timed read) so the timed call does not rebuild it. Warmup may fill the cache. Returned text must `string=` HEAD.
- Standing: /root/projects/cadr/.orchestrate/goal27/preferences.md
- Charter: /root/projects/cadr/docs/acceptance/goal-v27.md

ACCEPTANCE:
- Behavior: same search string as HEAD on the fixture models, including empty name.
- Remesure `--only-enforce cli_selectors.scoped_model_selector_search_text`. Slices unset. SYNC_TIP_PY.
- Keep only if strictly faster than HEAD. Prefer ≤1.0×. Full revert otherwise.
- /tmp/g27-search-text-REPORT.md + decisions.tsv + patch if kept.

FORBIDDEN: no gt/rebase/force-push; no dirty tip; no leftover win; no memo of the six fixture strings that diverges from HEAD format; no silent freeze.

STANDING: read preferences.md verbatim and obey
