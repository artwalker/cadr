# Goal 10 Part B acceptance

Date: 2026-08-01. Status: user-adjudicated no-op, committed and closed.

## Decision

The fixed behavioral baseline remains
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.
It describes as `v0.83.0-38-g74caa2649`. The published `v0.83.0` tag resolves
to `845d6ff1f6643aba440341cce877ce1c43ebbc39`, which is 38 commits behind the
current baseline. The user and independent reviewer confirmed that no newer
published tag exists; by instruction, no further upstream polling was done.

Locking `v0.83.0` would therefore be a downgrade, not an upgrade:

| Reference | Package directories | TypeScript `*.test.ts` files |
|---|---:|---:|
| `v0.83.0` / `845d6ff1f` | 7 | 352 |
| current baseline / `74caa2649` | 8 | 363 |

The seven tag packages are `agent`, `ai`, `coding-agent`, `evals`, `server`,
`storage`, and `tui`. The current baseline additionally contains
`packages/protocol`. Reverting to the tag would make the already implemented
`cadr-protocol` a component with no baseline owner and would move the parity
ledger backwards.

## No available upgrade point

The tag policy is now:

1. if a published tag leads the current fixed baseline, lock that tag;
2. otherwise retain the current baseline and state its exact relationship to
   the latest published tag.

This preserves the original policy objective—never lock a half-finished
development ref—without manufacturing a downgrade. The next published
`v0.84.0` alignment is a separate small goal and is expected to produce cadr
0.3.0; Goal 10 does not wait for it.

## Existing parity conclusion

Goal 9 Part A already completed the full re-audit at `74caa2649`:

```text
362 C / 0 U / 0 M / 1 N/A / 363 total
```

Because Part B changes neither the reference commit nor production behavior,
there are no fixture regenerations, source changes, reclassifications, or new
visual A/B items. The existing ledger remains the controlling evidence.

## Reproduction

```bash
git describe --tags --long 74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
git rev-parse v0.83.0^{commit}
git ls-tree -d --name-only v0.83.0:packages
git ls-tree -d --name-only 74caa2649f10ed71b4378ce69f5d9fbfd2466ca5:packages
git ls-tree -r --name-only v0.83.0 -- packages | rg '\.test\.ts$' | wc -l
git ls-tree -r --name-only 74caa2649f10ed71b4378ce69f5d9fbfd2466ca5 -- packages | rg '\.test\.ts$' | wc -l
```

Observed results are `v0.83.0-38-g74caa2649`, tag commit `845d6ff1f...`,
package counts `7/8`, and test-file counts `352/363` respectively.
