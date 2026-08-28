# Grok Bot / Cloud Agent handoff (2026-08-28)

Pickup of the Goal 20 leftover-pairing fleet after Grok Bot quota
ran out. Playbook: cadr-mode → pstack `session-pickup.md` →
`g20-leftover-pair.md` or `babysit.md`. Do not merge.

## What the prior fleet was doing

Grok Bot spawned Cursor Cloud agents (`source: sand`, model
`cursor-grok-4.6-medium`) to pair leftover Goal 20 paths: three unused
slugs per file, measure-only, append freeze JSON, READY PRs, **do not
merge**. Coordinator inventory refresh:
https://cursor.com/agents/bc-6a8aba70-ff7a-4d32-9ecb-bc9e440446fa

## Open PRs at pickup (base `cadr-migration`)

35 open PRs. GitGuardian is the only check on most; that is not a cadr
gate. PR #50 is draft. PR #63 is the paired-path history shard split
(~500k-line ledger move), not a leftover trio.

| PR | Trio / topic | Head branch |
|---:|---|---|
| 32 | tui_theme 319–321 | `cursor/goal20-pair-319-321-tui-796d` |
| 38 | evals harness 349–351 | `cursor/evals-leftover-pairs-349-351-46e3` |
| 39 | cli_settings 352–354 | `cursor/pair-352-354-cli-settings-leftovers-9088` |
| 40 | evals harness 355–357 | `cursor/evals-harness-pairs-355-357-f964` |
| 41 | oauth_pkce_device 334–336 | `cursor/pair-334-336-oauth-callback-leftovers-3839` |
| 42 | core wait/types/join 337–339 | `cursor/pair-337-339-core-rest-leftovers-5e64` |
| 43 | oauth 358–360 | `cursor/pair-358-360-oauth-openai-anthropic-ff5f` |
| 44 | evals harness 364–366 | `cursor/evals-harness-pairs-364-366-d90b` |
| 45 | image_runtime 367–369 | `cursor/pair-367-369-image-runtime-leftovers-d240` |
| 46 | core cancellation 361–363 | `cursor/pair-361-363-core-rest-leftovers-0556` |
| 47 | evals harness 370–372 | `cursor/evals-harness-leftovers-370-372-1fdc` |
| 48 | grep_tool 373–375 | `cursor/pair-373-375-grep-leftovers-eb2d` |
| 49 | edit_tool 388–390 | `cursor/pair-388-390-edit-leftovers-b6da` |
| 50 | tui 340–342 (draft) | `cursor/pair-340-342-tui-theme-leftovers-102a` |
| 51 | evals main 400–402 | `cursor/evals-main-leftovers-400-402-03ad` |
| 52 | resource-loader 394–396 | `cursor/pair-394-396-resource-loader-leftovers-b350` |
| 53 | tui_loaders 397–399 | `cursor/pair-tui-loaders-leftovers-397-399-f441` |
| 54 | oauth xai 379–381 | `cursor/pair-379-381-oauth-xai-leftovers-8969` |
| 55 | core predicate/register/replace 385–387 | `cursor/pair-385-387-core-rest-leftovers-4e7e` |
| 56 | evals harness 376–378 | `cursor/evals-harness-leftovers-376-378-6135` |
| 57 | execution-env 391–393 | `cursor/pair-391-393-execution-env-leftovers-494e` |
| 58 | provider_registry_defs 403–405 | `cursor/pair-403-405-runtime-projection-ff1b` |
| 60 | tool_manager 409–411 | `cursor/pair-409-411-tool-manager-leftovers-766a` |
| 61 | tui 415–417 | `cursor/pair-tui-loaders-leftover-415-417-fcad` |
| 62 | evals reporter 412–414 | `cursor/evals-reporter-leftovers-412-414-412b` |
| 63 | split paired-path history shards | `cursor/split-paired-paths-history-c88e` |
| 64 | oauth openai-device 421–423 | `cursor/pair-421-423-oauth-openai-device-0de9` |
| 65 | grep_tool helpers 406–408 | `cursor/pair-406-408-grep-leftovers-4050` |
| 66 | file-mutation-queue 328–330 | `cursor/pair-fmq-leftovers-328-330-ce29` |
| 67 | evals harness 418–420 | `cursor/evals-harness-leftovers-418-420-b700` |
| 68 | tui_loaders 433–435 | `cursor/pair-tui-loaders-leftover-433-435-4fbd` |
| 69 | oauth openrouter 436–438 | `cursor/pair-436-438-oauth-openrouter-31c4` |
| 70 | output_accumulator 427–429 | `cursor/pair-427-429-output-accumulator-leftovers-154d` |
| 71 | tui stdin 424–426 | `cursor/pair-tui-stdin-leftover-424-426-8d33` |
| 72 | evals reporter 430–432 | `cursor/evals-reporter-leftovers-430-432-124c` |

## Already closed (do not redo)

| PR | Trio | Note |
|---:|---|---|
| 33 | core 322–324 | closed |
| 30 | evals harness 325–327 | closed |
| 36 | evals harness 331–333 | closed |
| 35 | write_tool 343–345 | closed |
| 37 | evals harness 346–348 | closed |
| 59 | cli_settings 382–384 | closed |

Confirm merged-vs-abandoned on each before opening a replacement.

## Resume point

- **Do not merge** the open leftover stack. The original knives said
  READY, not land. Main executor owns ledger merges.
- **Do not rewrite** files those PRs already claim. Next leftover
  trio starts after 438 on a still-`needs-pair` file whose next three
  slugs are not in an open PR.
- PR #50 (draft tui 340–342) is the babysit exception: inspect why it
  stayed draft before opening a sibling on the same file.
- PR #63 is a ledger split; treat as its own babysit, not a trio.

## Concurrent-agent rule

Those leftover branches remain owned by their original Cloud Agents
until the user lands or abandons them. A new writer must pick an
unclaimed file. Pins, `CHANGELOG`, ledgers, and `RATIO_CEILINGS` stay
on the main executor.
