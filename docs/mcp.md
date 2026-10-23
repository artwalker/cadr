# MCP servers

cadr connects to Model Context Protocol servers over stdio or streamable HTTP and exposes their tools and resources to the model.

## Commands

Outside a session, `cadr mcp` reads `~/.cadr/agent/mcp.json` and, in a trusted project, `.pi/mcp.json`.

```bash
cadr mcp add filesystem -- npx -y @modelcontextprotocol/server-filesystem .
cadr mcp add docs --url https://example.com/mcp --bearer-token-env-var DOCS_TOKEN
cadr mcp list
cadr mcp remove filesystem
cadr mcp login docs
cadr mcp logout docs
```

`add` and `remove` take `-l` / `--local` to write `.pi/mcp.json` instead of the global file. `list` prints status, tools, and config errors, and exits 1 when a server failed. `--json` prints the same report. `cadr mcp --help` lists the remaining add flags (`--env`, `--cwd`, `--header`, OAuth client fields, `--exposure`).

Exposure for a new server defaults to `codemode`. The other values are `deferred`, `direct`, and `hidden`.

Inside a session, `/mcp` inspects connections. `/mcp login`, `/mcp logout`, and `/mcp reconnect` take an optional server name.
