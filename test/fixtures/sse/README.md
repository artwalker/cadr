# SSE fixture provenance

The `*-tool.sse` files are byte-for-byte copies of published live integration
recordings:

| Local file | Source commit | Upstream recording | Git blob |
|---|---|---|---|
| `anthropic-tool.sse` | [`wuhu-labs/wuhu-ai`](https://github.com/wuhu-labs/wuhu-ai/tree/cea4f747f42b3041fcf8dd14d7eb7e440db41eac), Apache-2.0 | `Tests/WuhuAITests/IntegrationTests/Recordings/claude-sonnet-4-6-tool-loop/1.output.sse` | `8a72d982f1f3505139581cd2f1e7e9fece022b2f` |
| `openai-tool.sse` | [`wuhu-labs/wuhu-ai`](https://github.com/wuhu-labs/wuhu-ai/tree/cea4f747f42b3041fcf8dd14d7eb7e440db41eac), Apache-2.0 | `Tests/WuhuAITests/IntegrationTests/Recordings/gpt-5.4-tool-loop/1.output.sse` | `d8ed1155eab240937f7a86c9a7308090c3acc58d` |
| `google-tool.sse` | [`faremeter/interchange`](https://github.com/faremeter/interchange/tree/d57799efef2327cf8738513372ec09cdc1214d14), LGPL-2.1 | `packages/inference-discovery-google-genai/wire/google-genai/gemini-3.6-flash/function-calling-multi-turn-streaming/turn-1/response.sse` | `7a98f6ba7bf2410700b33e76e8bd8a0a10d64e74` |

The upstream projects identify these as recorded integration-test or wire
responses. They contain provider-generated opaque identifiers and signatures
but no API keys or authorization headers.
