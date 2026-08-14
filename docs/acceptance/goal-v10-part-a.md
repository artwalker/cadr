# Goal 10 Part A stage report

> The user completed manual acceptance on 2026-08-01: independently verifying
> the remote, a full-history credential scan, and building from scratch after a
> temporary clone from GitHub; Part A is formally closed.

> Status: the private off-site backup is established, and every local branch and
> tag has been pushed; a real build was completed after an independent clone
> from the remote default branch.

## 1. Remote and branches

- Repository: `https://github.com/artwalker/cadr`; the GitHub API returns
  `visibility=PRIVATE`.
- The local remote name is fixed as `backup`; the existing `origin` was not
  modified and is still `git@github.com:badlogic/pi-mono.git`.
- The remote default branch is `cadr-migration`, which makes a plain clone land
  directly on the Cadr mainline rather than on the upstream TypeScript tracking
  tree.
- `git push backup --all` pushed three local branches:
  `cadr-migration@13a8c9472c7c82b54716a0286492d9a4888c3bd9`,
  `main@0d43c5804b57f5fb19e67f62051103a85d38fb42`,
  `pi-mono-legacy@48b9a05f2cfc3f34f749ac4a2d8d17aec0f843a1`.
- `git push backup --tags` pushed all 308 distinct local tags; the remote's 312
  tag ref lines also contain four annotated-tag dereferences, which are not
  miscounted as extra tags; no published Release was created.

Remote re-check:

```text
13a8c9472c7c82b54716a0286492d9a4888c3bd9 refs/heads/cadr-migration
0d43c5804b57f5fb19e67f62051103a85d38fb42 refs/heads/main
48b9a05f2cfc3f34f749ac4a2d8d17aec0f843a1 refs/heads/pi-mono-legacy
```

## 2. Pre-push credential and artifact audit

Neither the current tracked tree nor the two branches that must be backed up
contains `auth.json`, `.env*`, `.tmp-home/`, `.codex/`, or the root `cadr` or
`cadr-server` binaries. The full-history path audit found none of this local
state; all refs were additionally scanned for OpenAI/Anthropic/GitHub/Google/AWS
tokens and for the PEM format, with zero real-credential hits. The only two
high-confidence materials are Cadr's
`test/fixtures/auth/service-account-private-key.pem` (whose identity is fixed as
`fixture@example.invalid`) and the proxy-agent test certificate from upstream
history; both are synthetic test fixtures, not user credentials that can be
logged in with or deployed. The initial loose `sk-` scan hit only the
`task-...`/`markdown-...` substrings in test names and web-scrape artifacts that
upstream had already deleted; after tightening to token boundaries there were
zero token hits, and no false positive was passed off as a leak, nor was
anything ignored in the other direction.

`.gitignore` already covered the following before the push:

```text
/cadr
/cadr-server
*.core
*.fasl
.cadr/
.env
/.codex
/.tmp-home/
__pycache__/
*.py[cod]
```

The blocking condition "if credentials ever entered history, rewriting history
is forbidden" was therefore not triggered.

## 3. Independent clone and build

The private repository was plain-cloned to
`/tmp/cadr-backup-clone.2mZyvH/repository`, which automatically checked out
`cadr-migration@13a8c9472`. Running `./build.sh` inside the clone gave exit `0`:

- the eight deterministic test suites totalled
  `7040 checks / 7040 pass / 0 skip / 0 fail`;
- this machine's SBCL does not carry `sb-core-compression`, and an uncompressed
  image was built per the established fallback;
- the artifact `cadr` is 66,429,936 bytes, mode `0755`;
- `./cadr --version` outputs `cadr 0.1.0`.

Raw build log: `/tmp/cadr-goal10-part-a-clone-build.log`.

## 4. Boundary and ledger entry

- Outward actions were strictly limited to the private repository creation,
  branch/tag push and default-branch configuration that the user pre-authorized;
  nothing was switched to public, no Release was created, and no history was
  rewritten.
- New third-party dependencies: `0`.
- The Part took about 25 minutes, including the history sensitive-information
  audit, the remote transfer and the independent build; the product does not
  provide a per-Part auditable token count, and no estimate was fabricated.
- This report and the remote configuration are entered on the ledger as an
  independent Part A commit; after the commit, `cadr-migration` is pushed again.
