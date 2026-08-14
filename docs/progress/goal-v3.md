# GOAL v3: project rename and repository migration (pi-cl → cadr)

## 0. Preconditions and positioning

This goal runs after all of goal-v2's acceptance has passed. This is a **pure migration task**: no new features, no fixing of non-blocking bugs, no refactoring of logic. Any "improvement along the way" is treated as out of bounds. If a functional bug is found during the migration, record it in docs/open-questions.md; it is not fixed inside this goal.

New name: **cadr**. Meaning of the name (to be written into the README): cadr takes the second element of a list, and this project is pi's second implementation; it is at the same time a tribute to the MIT CADR Lisp Machine.

## 1. Migration steps

### 1. Repository migration
- Migrate the existing repository in full to the new directory/repository `cadr`, **preserving the complete git history** (move the whole repository, then complete the rename commits in the new repository; copying files and restarting the history is forbidden — the evolution record in the phase reports and the test-matrix is part of this project's auditability).
- Split the rename-related changes into a clear sequence of commits (for example: directory and system rename → symbol and package rename → documentation rename → migration logic); do not make one giant commit.

### 2. Global rename at the code layer
- ASDF systems: pi-ai → cadr-ai, pi-agent → cadr-agent, pi-cli → cadr-cli (including the /tests variants), with the .asd filenames and contents updated in step.
- All CL package names and nicknames change to the cadr-* prefix; exported symbols containing the string pi are renamed along with them.
- **The extension API's package name must be finalized at this moment**: after the migration, the extension system's stable interface (define-tool, define-command, define-event-hook, define-prompt-template) is exported from cadr-agent (or the interface package it designates). The "released means stable" promise of goal-v2 counts from the renamed names onward — this is the one and only interface namespace change that is allowed, and it is frozen afterwards.
- Executable: pi-cl → cadr; build.sh, build.lisp and test.sh updated in step.
- The product name in the REPL prompt, --version, --help and error messages is updated throughout.

### 3. User-side paths and environment variables (including data migration)
- Configuration directory: ~/.pi-cl/ → ~/.cadr/ (sessions, extensions and auth.json all migrate with it).
- If at startup the old directory is detected to exist and the new directory does not: prompt the user and migrate automatically after confirmation (move rather than copy; auth.json stays 0600 after the migration). Under --yolo or in a non-interactive environment, refuse the automatic migration and give manual migration instructions, fail closed.
- Environment variable prefix: PI_CL_* → CADR_*. The old variables are still read for one transitional version but print a deprecation warning; the README records the deprecation timeline.
- If a session file internally contains a product-name field, new writes use the new name and reads stay compatible with the old value.

### 4. Documentation
- Rewrite the README header: project name cadr, meaning of the name, one-sentence positioning.
- **Must be kept**: the behavioral-reference declaration for the earendil-works/pi fixed reference commit, the acknowledgements, the MIT license information, and the difference list (including the disclaimer that "this project has no affiliation with the baseline pi").
- Apart from the above reference and acknowledgements, no old name may remain anywhere in the repository (code, comments, documentation, scripts, fixture naming). The historical reports under docs/progress/ are historical records and are not rewritten.

## 2. Acceptance criteria

1. `grep -ri "pi-cl\|pi-ai\|pi-agent\b" --exclude-dir=.git --exclude-dir=docs/progress` gets zero hits in the new repository apart from the README reference section and the CHANGELOG/migration notes (the grep command and the exemption list are written into the migration report).
2. The full test suite (all of v1+v2) is green in the new repository, with a count no lower than before the migration.
3. A one-command build in an isolated environment produces the executable `cadr`; --version shows the new name.
4. Data migration test: seed an old ~/.pi-cl/ (containing sessions, extensions and auth.json) → after interactive confirmation it migrates completely, permissions are preserved, and --continue can restore an old session; plus a fail-closed test for the non-interactive scenario.
5. The transitional compatibility for old environment variables and the deprecation warning have test coverage.
6. The git history is complete (the hash of the last commit before the migration is reachable in the new repository's history).
7. Migration report docs/progress/migration.md: rename mapping table, data migration strategy, exempted-residue list, test and build evidence.

## 3. Principles

- Feature development is frozen for the duration of this goal; functional problems that are found are recorded only, not fixed.
- The extension API namespace is frozen from this rename onward, and no subsequent goal may change it again.
- The migration report must honestly list every exempted old-name residue and its reason; silent retention is not allowed.
