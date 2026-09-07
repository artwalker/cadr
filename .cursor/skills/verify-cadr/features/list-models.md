# List models

List models lets a user print the models cadr would offer, filtered by an optional search string, without entering the TUI.

## Sub-features

- `list-empty` reports that no models are available when the isolated store has no credentials.
- `list-search-empty` reports no matches when a search string is given and the catalog is still empty.

## How to get to it (user POV)

- Run `cadr --list-models` in a terminal.
- Run `cadr --list-models <search>` to fuzzy-filter the same list.

## Driving it with control-cadr

Preconditions:

- Isolated HOME has no `auth.json` and no `models.json` overrides.
- Provider API keys are unset.
- `control-cadr doctor` passed.

- **Empty catalog.** Ask for the model list. Run `CADR_VERIFY_FEATURE=list-models .cursor/skills/verify-cadr/bin/control-cadr cli -- --list-models`. Exit code `0`. `stdout.txt` contains `No models available.` and `Use /login to log into a provider via OAuth or API key.`
- **Empty search.** Run `CADR_VERIFY_FEATURE=list-models .cursor/skills/verify-cadr/bin/control-cadr cli -- --list-models nosuchmodel`. With an empty catalog the same `No models available.` copy is printed (there is nothing to filter). Exit code `0`.
- **Proof.** `exit.txt` is `0`. Stderr may be empty. Do not require a six-column table unless credentials were seeded.

## Gotchas

- `--list-models` exits `0` even when it prints the no-models guidance. Exit `0` is not "models exist".
- The no-models paragraph points at `docs/providers.md` and `docs/models.md` using absolute paths from the image. Assert the `Use /login` sentence, not a hardcoded docs pathname.
- Seeding operator credentials into HOME makes this feature a different path (a table). Do not mix that with the empty-store proof.
- Parent-shell `DEEPSEEK_API_KEY` / `OPENAI_API_KEY` / … also populate the catalog. Rely on `control-cadr` scrubbing those unless `CADR_VERIFY_KEEP_CREDENTIALS=1`.
