# Goal 20 P0 — OpenCode Go live vehicle

Default live vehicle is OpenCode Go `mimo-v2.5`. Native DeepSeek
FiveAM items keep their skip gates.

## Default live (2026-08-18, `DEEPSEEK_API_KEY` unset)

| item | result |
|---|---|
| DeepSeek chat / print / eval / self-ext / repo | SKIP (key unset) |
| Anthropic two-turn | SKIP (key unset) |
| opencode-go print (`mimo-v2.5`) | PASS |
| opencode-go eval smoke (`mimo-v2.5`) | PASS |
| opencode-go mimo thinking stream | PASS (3 checks) |

`Items: 9, run: 3, pass: 3, skip: 6, fail: 0`.

`prepare-opencode-go-credential` accepts `auth.json` or
`OPENCODE_API_KEY` (file wins). Isolated live TUI smoke writes that
key into the smoke HOME; `verify.sh` skips as
`OpenCode Go live TUI` / `OpenCode Go API key is not configured`.
CI empty-key greps paired (9 skips). `CADR_PROVIDER` unchanged.

## Catalog sweep (`CADR_LIVE_OPENCODE_GO_SWEEP=1`)

Local instrument. Not in `test-live.sh` / CI.

| id | API | kind | notes |
|---|---|---|---|
| mimo-v2.5 | completions | ok | `reasoning` string |
| mimo-v2.5-pro | completions | ok | `reasoning` |
| deepseek-v4-flash/pro | completions | ok | `reasoning_content` |
| glm-5.1/5.2, hy3, kimi-k2.7-code/k3 | completions | ok | `reasoning_content` or `reasoning` |
| kimi-k2.6 | completions | skip-endpoint | `Endpoint is unavailable` |
| qwen3.7-plus/max, qwen3.8-max, minimax-m3 | anthropic | ok | `thinking` |
| grok-4.5 | responses | provider-hidden | `reasoning: {effort, summary:null}`; output is message-only; no thinking text on the wire |
| gpt-5.6-luna | responses | provider-hidden | same shape |
| minimax-m2.7 | completions | provider-hidden | long empty `choices:[]` then text; no reasoning/thinking string |
| qwen3.6-plus | completions | skip-endpoint | `Endpoint is unavailable` |

A row is a product defect only when the SSE carries a nonempty
`reasoning` / `reasoning_content` / `reasoning_text` / `thinking`
**string** that we did not turn into a thinking event. Usage counters
and `{effort, summary}` echoes do not count.

No parse fix in this commit: the three non-ok live models did not
send thinking text. Anthropic and completions string fields already
parse (34467622f + this live lock).
