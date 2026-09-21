# websocket_stream.stream_roundtrip fair ruler

Option A. Both sides use the product websocket client against a loopback TCP server on 127.0.0.1.

## Why this option

Pair 102 timed cadr `stream-chat` `:transport :websocket` over usocket TCP, and pi `stream` `transport: "websocket"` through `Goal20MockWebSocket` with no socket. That is not the same transport class. Goal 26 charter forbids mocking cadr and forbids leaving only one side on TCP.

Option B would add an in-process mock on cadr. That is the banned mock. Option A keeps cadr's existing product path and puts pi on the same class of work.

## What both sides pay

| side | client | wire |
|---|---|---|
| cadr | `stream-chat` `:transport :websocket` (`src/cadr-ai/websocket.lisp`) | usocket listen on `127.0.0.1:ephemeral`, HTTP 101, one request frame, recorded `response.*` text frames |
| pi | `stream` `transport: "websocket"` (`packages/ai/src/api/openai-codex-responses.ts` at Goal 23 baseline `13cbf77df`) | Node `http` listen on `127.0.0.1:ephemeral`, HTTP 101, one request frame, the same recorded `response.*` text frames |

Both close cached websocket sessions before each timed call. Both point `base-url` / `baseUrl` at `http://127.0.0.1:<port>` so the client opens `ws://127.0.0.1:<port>/codex/responses`. Native `globalThis.WebSocket` stays installed on pi. Fetch is still forbidden.

Observed exact keys are unchanged: `ws_text`, `stop_reason`, `text_characters`, `usage_input`, `usage_output`. Fixture text is still `Hello`, stop `stop`, usage 1/1.

## What this is not

Not a one-sided mock. Not a RATIO_CEILINGS drop. Goal 25 freeze 229.69× remains the unfair-ruler history, not a Goal 25 reopen.

## Evidence hygiene

Friend-MachineD fair remeter before any product knife: **14.47×** (44751.6 / 3093.0 µs), n=5, slices unset. Cited in `/tmp/g26-websocket-REPORT.md` and `.audit/goal26-decisions.tsv`.

The `summary.json` / `ratios.tsv` currently in this directory hold **3.05×** from the later TCP_NODELAY-only invent that was **reverted** during the pilot. Do not treat those JSON files as the pre-invent fair baseline. Post-invent beat evidence lives under `websocket_stream-invent/` (0.653× keep).
