GOAL: For the remaining Goal 28 inventory classes except publicApiExports, write a presence table that says name-present, missing, or extractor-noise. Do not mark match.

SCOPE: Exclusive worktree /tmp/cadr-g28-presence-rest on branch g28-presence-rest from tip 219a3edd0. You may add scripts/goal28-capability-presence-rest.py and docs/benchmarks/goal28-presence-rest.tsv. Do not edit src/. Do not edit /root/projects/cadr. Copy tip inventory files into the worktree if HEAD lacks them: /root/projects/cadr/scripts/goal28-capability-inventory.py, /root/projects/cadr/docs/benchmarks/goal28-capabilities.tsv, /root/projects/cadr/scripts/goal28-capability-presence.py, /root/projects/cadr/docs/benchmarks/goal28-presence.tsv. Patch /tmp/g28-presence-rest.patch. TSV copy /tmp/g28-presence-rest.tsv.

CONTEXT: Pin d981de1229ef899957bbe968bc8dcda02a21f477 in /root/projects/pi-mono. First presence unit already covered slashCommands, cliFlags, rpcMethods, toolFiles. Do not redo those. Skip publicApiExports. Cover exitCodes, settingsKeys, sessionFormatVersions, providers, errorClasses, extensionEvents, extensionTypeFields, exportedComponents, keybindingActions, themeTokens, environmentVariables. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md. Charter /root/projects/cadr/docs/acceptance/goal-v28.md.

ACCEPTANCE:
- Columns: class, name, presence, status, note.
- Every inventory row in the covered classes appears once.
- status is open on every row.
- presence is name-present, missing, or extractor-noise.
- name-present means a cadr registry, parser, or declared constant contains that name. Cite the file in note. Not a behavior proof.
- missing means you looked at the cadr registry for that class and the name is absent. Do not mark missing because you did not look.
- If a class has no cadr registry you can name, stop and report that class as blocked in the report. Do not invent name-present.
- Script --check exits 0 only if coverage is 1:1 with inventory for those classes, no status is match, and publicApiExports is absent.

VERIFY: python3 scripts/goal28-capability-presence-rest.py --write /tmp/g28-presence-rest.tsv && python3 scripts/goal28-capability-presence-rest.py --check /tmp/g28-presence-rest.tsv. Print name-present, missing, extractor-noise per class.

TIMEBOX: 45 minutes. On expiry, return the partial table and stop.

FORBIDDEN: no product src edits; no match; no commit; no push; no gt; no rebase; no dirty tip; do not rewrite goal28-capabilities.tsv status; do not treat source-parity aligned as name-present.

REPORT: status, counts, registries cited, blocked classes, patch path, verify output, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
