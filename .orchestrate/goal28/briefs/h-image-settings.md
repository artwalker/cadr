GOAL: Pin settings keys Image.autoResize and Image.blockImages work on cadr as images.autoResize and images.blockImages. A JSON settings object changes the caller-visible resize and block flags the same way the pin does. Defaults stay true and false.

SCOPE: Exclusive worktree /tmp/cadr-g28-image-settings on branch g28-image-settings. You may add test/cadr-cli/goal28-image-settings-test.lisp and one asd entry. You may edit only the settings reader that already loads images, if the pin JSON path is ignored. Do not copy cadr-ai. Do not replace settings.lisp, commands.lisp, or cadr-cli.asd. Patch /tmp/g28-image-settings.patch. Parent lands.

CONTEXT: Pin v0.85.1 d981de1229ef899957bbe968bc8dcda02a21f477 reads settings.images.autoResize (default true) and settings.images.blockImages (default false) in packages/coding-agent/src/core/settings-manager.ts. Inventory names are Image.autoResize and Image.blockImages. Cadr already reads images then autoResize/blockImages in src/cadr-cli/bootstrap/settings.lisp and commands.lisp. Alias note docs/benchmarks/goal28-settings-gaps.tsv. Presence is not match. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE: FiveAM asserts default autoResize true and blockImages false, and JSON {"images":{"autoResize":false,"blockImages":true}} flips both on the live reader the product uses. Missing or null leaves the default. No process-wide special.

VERIFY: Run the new FiveAM file from the worktree with sbcl. Report Did N checks and Fail. Do not mark the capability table. Parent overlays after tip rerun.

TIMEBOX: 25 minutes. On expiry return the patch and what failed.

FORBIDDEN: no commit, no push, no gt, no rebase, no force-push, no wholesale file copy onto tip, no source-parity as proof, no npm installer, no Goal 20-27 reopen.

REPORT: status, test command, pass count, patch path, files touched, deviations.

STANDING:
1. Repo /root/projects/cadr tip cadr-migration. Goal 28 only. Never reopen Goal 20-27 as incomplete.
2. Pin is BASELINE d981de1229ef899957bbe968bc8dcda02a21f477 v0.85.1. Named sets come from /root/projects/pi-mono at that commit, not from cadr git.
3. Capability means a named caller-visible item. CLI flags, slash commands, exit codes, settings keys, session format versions, RPC methods, providers, error classes, public API exports, extension events, extension type fields, exported components, keybinding actions, theme tokens, environment variables, tool files.
4. A name present in source-parity.md or presentation-parity.md is not match. Every inventory row starts open.
5. intentional-difference only if an existing adjudication says the user can still do the thing. pi can do it and cadr cannot is a defect, never a style row.
6. Product invent only in /tmp worktrees. Parent lands proven files. Never dirty tip src mid-invent. Do not touch other sessions' dirty files.
7. No commit, no push, no PR, no gt, no rebase, no force-push unless the operator asks.
8. One writer per worktree. Model for this inventory worker: cursor-grok-4.6-medium. Local machine. This tree is not in cloud.
9. Stop for the program is open-capability=0 on the generated table. This inventory unit stops when the table and gate exist and every row is open.
10. Do not implement missing features in the inventory unit.
11. Per-session settings are arguments on the call that owns them. No process-wide special for a timeout, path, or prefix.
12. Non-open status on docs/benchmarks/goal28-capabilities.tsv comes only from docs/benchmarks/goal28-adjudications.tsv. Presence is not a status. source-parity and presentation-parity are not evidence. fixed and match require an existing test file. intentional-difference requires an existing adjudication that the user can still do the thing. npmCommand stays open until a production caller installs.
