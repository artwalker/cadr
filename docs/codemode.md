# Codemode

The `codemode` tool runs a JavaScript script that calls cadr's other tools and non-LLM models (classifiers and image models). It is a built-in extension and stays inactive until `--tools +codemode` or `defaultTools` names it. The QuickJS sandbox loads on the first script.

## Scripts

The tool input is raw JavaScript, not JSON and not a markdown code fence. It runs as the body of an async function, so top-level `await` and `return` work. The sandbox has no Node APIs, file system, network, or timers. Scripts reach the outside world through tools and `models`.

An options line must be the first line. Anywhere else, the call fails before the script runs:

```js
// @options: {"max_output_tokens": 10000, "timeout_ms": 60000}
```

`max_output_tokens` defaults to 10000. `timeout_ms` is unset unless the script sets it.

## Globals

| Global | Purpose |
|---|---|
| `tools.<name>(args)` | Call a tool. `await tools.<name>({ ...args })` resolves to a string, or to an object when the tool's declaration says so, and rejects with an Error on failure. |
| `text(value)` | Add a text item. Several text items each start with a `==> text N/M <==` line. |
| `image(value)` | Add an image. The result also names the temp file the image was saved to. |
| `console.log(...)` | Lines follow the other output in one `<console_output>` block. |
| `return value` | A top-level `return` adds the value like `text()`. |
| `exit()` | End the script. |
| `store(key, value)` / `load(key)` | Keep JSON values across `codemode` calls. |
| `ALL_TOOLS`, `searchTools`, `describeTool`, `describeNamespace` | Find tools that are not listed inline, including MCP tools. |

Calls still running when the script ends are cancelled.

## Models

`models.classify` takes:

```text
{ state: { ... }, images?: [{ type: "image", data: <base64>, mimeType }], questions: { <id>: { type: "choice" | "score" | "bool", ... } } }
```

`models.generateImages` takes:

```text
{ input: [{ type: "text", text: <prompt> }, ...optional { type: "image", data: <base64>, mimeType } references] }
```

## Settings

`codemode.mode` is `on` unless it is the string `only`. `only` hides direct tools from the model and leaves them reachable from scripts. `codemode.inlineBudget` defaults to 3000. Tools that do not fit that budget stay out of the inline description.

`CADR_CODEMODE_MAX_WORKERS` sets how many scripts run at once. The default is 2. An empty or non-positive value keeps 2.
