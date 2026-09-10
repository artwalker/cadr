GOAL: For slash commands, CLI flags, RPC methods, and tool files on the Goal 28 pin dump, write a presence table that says name-present or missing. Do not mark match.

SCOPE: Exclusive worktree /tmp/cadr-g28-presence on branch g28-presence from tip 219a3edd0. You may add scripts/goal28-capability-presence.py and docs/benchmarks/goal28-presence.tsv. Do not edit src/. Do not edit /root/projects/cadr. Copy the inventory script and TSV from tip into the worktree if the worktree is created from HEAD without untracked files. Patch to /tmp/g28-presence.patch. TSV copy /tmp/g28-presence.tsv.

CONTEXT: Inventory is docs/benchmarks/goal28-capabilities.tsv on tip, 959 rows, all open. Regenerator scripts/goal28-capability-inventory.py. Pin d981de1229ef899957bbe968bc8dcda02a21f477 in /root/projects/pi-mono. cliFlags contains a row named `---` from the flag regex. That is extractor noise, not a missing flag. toolFiles includes helper files such as index.ts, path-utils.ts, render-utils.ts. Presence for tools is "cadr can run that tool", not "a file with the same name exists". Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Columns: class, name, presence, status, note.
- Only these classes: slashCommands, cliFlags, rpcMethods, toolFiles.
- status is open on every row.
- presence is name-present, missing, or extractor-noise.
- `---` is extractor-noise, not missing.
- A helper .ts file that is not a user-invocable tool is extractor-noise, with the note naming the real tool registry you used.
- name-present means the cadr tree has a registry or parser entry for that name. Cite the file in note. It is not a behavior proof.
- Script --check exits 0 only if every inventory row in those four classes appears once, no status is match, and `---` is extractor-noise.

VERIFY: python3 scripts/goal28-capability-presence.py --write /tmp/g28-presence.tsv && python3 scripts/goal28-capability-presence.py --check /tmp/g28-presence.tsv. Print counts of name-present, missing, extractor-noise per class.

TIMEBOX: 45 minutes. On expiry, return the partial table and stop.

FORBIDDEN: no product src edits; no match; no commit; no push; no gt; no rebase; no dirty tip; do not rewrite the inventory TSV status column.

REPORT: status, counts, patch path, verify output, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
