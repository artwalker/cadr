GOAL: Dump every named pi capability at d981de1229ef899957bbe968bc8dcda02a21f477 into a TSV whose rows all start open, plus a script that regenerates that TSV and fails if a required class is missing.

SCOPE: Exclusive worktree /tmp/cadr-g28-inventory on branch g28-inventory from tip 219a3edd0. You may add scripts/goal28-capability-inventory.py and docs/benchmarks/goal28-capabilities.tsv there. Do not edit src/. Do not edit /root/projects/cadr. Write the patch to /tmp/g28-inventory.patch and a copy of the TSV to /tmp/g28-capabilities.tsv.

CONTEXT: Extractors already live in /root/projects/cadr/scripts/enumerate-baseline-diff.py. They git-show packages paths. Point git -C at /root/projects/pi-mono, not cadr. Pin file /root/projects/cadr/BASELINE. Class list is in /root/projects/cadr/docs/acceptance/goal-v28.md. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md. The g23 fixture test/fixtures/source-parity/g23-0851-enumeration.json is a delta, not the absolute set. Do not use it as the inventory.

ACCEPTANCE:
- Script prints one TSV to stdout and writes the same bytes when --write PATH is passed.
- Columns: class, name, status, evidence. status is open on every row.
- Required classes: cliFlags, slashCommands, exitCodes, settingsKeys, sessionFormatVersions, rpcMethods, providers, errorClasses, publicApiExports, extensionEvents, extensionTypeFields, exportedComponents, keybindingActions, themeTokens, environmentVariables, toolFiles.
- publicApiExports is one row per export name, not a count.
- A class empty on the pin emits one row name=__empty__ status=open evidence=pin-empty.
- No row reads docs/source-parity.md to set status.
- Running the script twice on the same pin yields the same TSV bytes.

VERIFY: From the worktree, python3 scripts/goal28-capability-inventory.py --write /tmp/g28-capabilities.tsv && python3 scripts/goal28-capability-inventory.py --check /tmp/g28-capabilities.tsv. Check exits 0 only if every required class appears and no status is match. Print class counts to the report.

TIMEBOX: 45 minutes. On expiry, return the partial script and stop.

FORBIDDEN: no product src edits; no match from existing ledgers; no commit; no push; no gt; no rebase; no dirty tip.

REPORT: status, worktree, patch path, row count, class counts, verify command output, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
