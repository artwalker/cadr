# cli_selectors.* fair ruler (seven metrics)

Shared note. Goal 25 timed leftover constructors inside the collect slot. Cadr paid `make-model-selector-state` (sort, search-text table, apply-filter, select-current, keybindings). Pi paid object literals and leftover replicas of unexported helpers. That pair is unfair-ruler.

## Option A (landed)

Constructors and fixture lists run in `collect` prepare. The timed thunk calls the product function only.

| metric | cadr timed | pi timed |
|---|---|---|
| `model_selector_active_models` | `model-selector-active-models` | `scope === "scoped" ? scopedModels : allModels` |
| `model_selector_clamp_selected` | restore `selected` then `model-selector-clamp-selected` | restore then leftover clamp matching `Math.min(selected, count-1)` |
| `model_selector_select_current` | `model-selector-select-current` on prefiltered state | `findIndex` / `modelsEqual` leftover of `loadModelsFromSnapshot` |
| `scoped_model_selector_search_text` | `scoped-model-selector-search-text` | product `getModelSearchText` |
| `scoped_models_enable_ids` | `scoped-models-enable-ids` | leftover of unexported `enableAll` |
| `scoped_models_clear_ids` | `scoped-models-clear-ids` | leftover of unexported `clearAll` |
| `scoped_models_enabled_set` | `scoped-models-enabled-set` hash-table | `new Set(enabled)` as in `getSortedIds` |

Observed keys for these seven (`msa_*`, `msc_*`, `msel_*`, `smsst_*`, `smei_*`, `smci_*`, `smes_*`) still come from the encode wrappers and still match.

## What this is not

Not a leftover-only win. Not a RATIO_CEILINGS drop. Goal 25 freeze ratios stay history. `GOAL20_COLLECT_ONLY` is remesure-only. It does not change the product path.

## Friend-MachineD fair remeter

n=5, warmups=1, slices unset. Host Friend-MachineD.

| metric | cadr µs | pi µs | ratio | disposition |
|---|---|---|---|---|
| `model_selector_active_models` | 0.093 | 1.982 | 0.047× | met-beat |
| `model_selector_clamp_selected` | 0.107 | 12.785 | 0.008× | met-beat |
| `model_selector_select_current` | 0.397 | 0.870 | 0.456× | met-beat |
| `scoped_models_clear_ids` | 0.516 | 5.475 | 0.094× | met-beat |
| `scoped_models_enable_ids` | 1.005 | 4.592 | 0.219× | met-beat |
| `scoped_model_selector_search_text` | 7.306 | 1.333 | 5.482× | open-parity |
| `scoped_models_enabled_set` | 2.876 | 1.787 | 1.610× | open-parity |

`format nil` vs V8 template on search-text, and `make-hash-table :test #'equal` vs `Set` on enabled-set, remain H invent. One concatenate rewrite on search-text reached 1.99× and was fully reverted. The bar is ≤1.0×.
