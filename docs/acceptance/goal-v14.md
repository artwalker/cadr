# Goal 14 acceptance ledger

## Part A0 — Goal 13 presentation carry-over

### Result

The three approved authentication-presentation corrections are complete.  The
implementation fixes ownership rather than painting individual call sites:
authentication overlays obtain their title and border semantics from shared
overlay primitives, while the generic single-line Input component owns the
software cursor.  Provider status text is a projection of the credential
producer's source identity; no display-only `configured` to `stored` rewrite
exists.

| Item | Fixed-baseline evidence | Cadr implementation | Regression |
|---|---|---|---|
| Cyan bold title and blue border | `packages/coding-agent/src/modes/interactive/components/oauth-selector.ts:67-96` constructs both borders through `DynamicBorder` and the title through `accent` plus bold | `src/cadr-cli/interactive-services.lisp:1421-1448,7351-7466,7757-7832` centralizes the three auth overlay families on `auth-overlay-border-line` and `selector-overlay-title-line`; ordinary selectors retain `border-muted` | `GOAL14-A0-AUTH-OVERLAYS-OWN-BASELINE-TITLE-AND-BORDER-SEMANTICS` |
| Visible software cursor | `packages/tui/src/components/input.ts:378-445` owns inverse-video cursor placement, grapheme selection, horizontal scrolling, and right padding | `src/cadr-tui/input-component.lisp:342-423`; auth search/API-key renderers delegate through `selector-input-line` instead of rebuilding `> value` | `GOAL14-A0-PROVIDER-SEARCH-AND-LOGIN-INPUTS-RENDER-A-VISIBLE-CURSOR`; `SINGLE-LINE-INPUT-RENDERS-BASELINE-SOFTWARE-CURSOR-AT-END-AND-OVER-TEXT`; `SINGLE-LINE-INPUT-CURSOR-PRESERVES-GRAPHEMES-AND-NARROW-WIDTHS` |
| Credential source identity | `packages/coding-agent/src/core/model-runtime.ts:428-437` fixes precedence as runtime, stored, configured request, then native auth; `provider-composer.ts:534-548` defines command/env/literal sources; `oauth-selector.ts:164-181` only formats the supplied source | `src/cadr-cli/model-services.lisp:924-1063`; `src/cadr-cli/main.lisp:3145-3150`; `src/cadr-cli/interactive-services.lisp:7619-7654` | `GOAL14-A0-PROVIDER-STATUS-SOURCE-CONTRACT-MATCHES-BASELINE` |

### Ownership conclusion

The old Cadr path made presentation decisions at each renderer: borders were
generic muted lines, titles were plain fitted strings, and authentication
inputs concatenated `"> "` with a value.  That is the repeated-decision defect
Goal 14 is intended to remove.  The corrected ownership is:

- authentication overlay composition owns `border` and accent/bold title;
- the reusable Input component owns cursor visibility, grapheme placement,
  scrolling, and padding;
- authentication producers own the status source; the selector only formats
  that source.

The generic selector border remains `border-muted`.  Changing it globally
would alter non-authentication overlays outside A0 and violate the byte-stable
boundary.

### Authentication source contract

| Producer state | Fixed baseline source | Previous Cadr source | Corrected Cadr source | Selector text |
|---|---|---|---|---|
| request-local credential override | `runtime` | not projected | `runtime` | `✓ runtime` |
| credential in persistent auth store | `stored` | `stored credential` on the live login path | `stored` | `✓ stored` |
| native OAuth auth check | `OAuth` | `OAuth` | `OAuth` | `✓ configured` |
| legacy/logout projection | `stored credential` | `stored credential` | unchanged | `✓ configured` |
| built-in environment credential | environment label/name | provider environment name | provider environment name | `✓ env: NAME` |
| models.json environment template | comma-separated variable names | not projected | comma-separated variable names | `✓ env: NAME[, NAME]` |
| models.json command | `models_json_command` | not projected | `models_json_command` | `✓ models_json_command` |
| models.json literal key | `models_json_key` | not projected | `models_json_key` | `✓ models_json_key` |
| no usable credential | absent | absent | absent | `• unconfigured` |

`OAuth`, absent source, and the deliberately retained legacy phrase `stored
credential` still render as `configured`, exactly as the baseline selector
defines.  Environment detection also accepts the baseline's comma-separated
uppercase-name form.

### Observable changes and unchanged boundary

Only the approved A0 surface changed:

- the three authentication overlay families now use blue borders and
  cyan/bold titles;
- provider search and API-key input show the inverse-video cursor;
- a persistent credential on the live model-registry path displays `stored`
  because its source is now correctly `stored`.

The login-provider and logout-provider full-screen SHA fixtures changed for
those approved pixels.  Every other full-screen/overlay SHA, payload fixture,
wire fixture, session behavior, extension export, and non-authentication
selector remained byte-identical.

### Freeze audit

The historical whole-tree `src/cadr-ai` object freeze ended when Goal 13 made
separately approved provider and OAuth changes.  The still-active freezes are
the public extension export surface, the 34-event extension contract, and
published public behavior.  A0 touches none of them and makes no `src/cadr-ai`
change.  Any later Goal 14 batch that changes those surfaces remains blocked
pending a separate proposal.

### Mechanical verification

The complete deterministic suite after A0:

```text
cadr test summary: systems=8 checks=12511 pass=12511 skip=0 fail=0
```

Part A starts only after this A0 implementation and ledger are committed.
