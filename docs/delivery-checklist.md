# Delivery checklist

This checklist is mandatory before every user-facing delivery that may be
tested through the root `./cadr` executable.

1. Commit every intended `src/` change. An uncommitted source edit still counts
   as a newer source modification.
2. Run `./build.sh` from the repository root. Do not substitute the isolated
   image produced inside `verify.sh`; the user runs the root image.
3. Run `./scripts/check-root-binary.sh`. It must report `root cadr binary is
   fresh` and exit zero.
4. Run `./scripts/smoke-first-run.sh`. It must exit zero (version, help,
   offline no-key copy, one `-p` prompt when keys are present, freshness).
5. Run `./scripts/verify.sh`. If a root image exists, its first deterministic
   stage repeats the freshness check and stops the remaining gate when stale.
6. If `src/` is edited or committed after step 2, restart at step 2.
7. Include the checker's `binary build time`, `latest src commit`, and `binary
   version` lines in the delivery report. A completion claim without this
   evidence is invalid.

Freshness is strict: the binary timestamp must be later than both the latest
commit that touches `src/` and the latest filesystem mtime under `src/`. This
catches the failure mode where an image is built, source is committed a minute
later, and the old image is accidentally handed to manual A/B.

Clean CI checkouts have no root binary. `verify.sh` records the root stage as
N/A there and continues with its isolated build. N/A is not acceptable for a
user-facing delivery: steps 2 and 3 remain mandatory locally.

Before creating a release tag, run `./scripts/verify-release.sh` on the exact
commit to be tagged. It runs the ordinary verifier first and then the complete
fixed-baseline render inventory; either failure blocks the tag. Any subsequent
change to HEAD invalidates that evidence and requires rerunning the command.
The script verifies only and never creates or pushes a tag.

The Goal 17 cross-implementation evidence is channel-specific and none may be
substituted for another: the ordinary verifier must pass the core PTY render
matrix, exact tool-result differential, and JSON/RPC event differential; the
pre-tag wrapper must then pass the full 74-capture baseline-visible branch
inventory. Record the exact command summaries in the active goal acceptance
report. A green historical fixture or an earlier commit is not delivery
evidence.
