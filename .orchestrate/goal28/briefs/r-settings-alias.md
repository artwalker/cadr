GOAL: Split the 33 settingsKeys marked missing into alias (cadr already stores the same setting under another JSON path) or truly-absent. Do not mark match. Do not edit product src.

SCOPE: Exclusive worktree /tmp/cadr-g28-settings-alias on branch g28-settings-alias from tip 219a3edd0. You may add scripts/goal28-settings-alias.py and docs/benchmarks/goal28-settings-gaps.tsv. Do not edit src/. Do not edit /root/projects/cadr. Copy tip files into the worktree if HEAD lacks them: scripts/goal28-capability-presence-rest.py, docs/benchmarks/goal28-presence-rest.tsv, docs/benchmarks/goal28-capabilities.tsv. Patch /tmp/g28-settings-alias.patch. TSV copy /tmp/g28-settings-gaps.tsv.

CONTEXT: presence-rest marked 33 settingsKeys missing. The mapper turns Image.autoResize into image.autoResize. cadr stores that under images / autoResize in src/cadr-cli/bootstrap/settings.lisp. Pin d981de1229ef899957bbe968bc8dcda02a21f477. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Input is every settingsKeys row with presence=missing in docs/benchmarks/goal28-presence-rest.tsv. One output row each.
- Columns: name, disposition, cadr_path, evidence, status.
- disposition is alias or truly-absent.
- status is open on every row.
- alias requires the cadr JSON path or setting id you found, cited by file. Image.autoResize is alias if images.autoResize or :id "auto-resize-images" exists.
- truly-absent means you read the settings bootstrap and manager and the value is not stored under any path.
- Script --check exits 0 only if all 33 missing names appear once, no status is match, and Image.autoResize is alias.

VERIFY: python3 scripts/goal28-settings-alias.py --write /tmp/g28-settings-gaps.tsv && python3 scripts/goal28-settings-alias.py --check /tmp/g28-settings-gaps.tsv. Print alias and truly-absent counts.

TIMEBOX: 40 minutes. On expiry, return the partial table and stop.

FORBIDDEN: no product src edits; no match; no commit; no push; no gt; no rebase; no dirty tip; do not rewrite presence-rest.tsv.

REPORT: status, counts, alias examples, truly-absent names, patch path, verify output, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
