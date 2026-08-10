# Environment Variables

## Model and provider

| Variable | Purpose |
|---|---|
| `CADR_PROVIDER` | Default provider (like `--provider`). |
| `CADR_MODEL` | Default model (like `--model`). |
| `CADR_BASE_URL` | Default endpoint override (like `--base-url`). |
| Provider keys (`OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `KIMI_API_KEY`, ...) | Provider credentials, read by the matching built-in provider. |

Legacy `PI_CL_*` names are not read.

## Paths

| Variable | Purpose |
|---|---|
| `CADR_CODING_AGENT_DIR` | Override the agent directory (default `~/.cadr/agent/`); a leading `~` is expanded. |
| `CADR_CODING_AGENT_SESSION_DIR` | Override the session storage directory. |
| `CADR_SHARE_VIEWER_URL` | Override the viewer base URL used by `/share`. |
| `CADR_PACKAGE_DIR` | Override package asset resolution (install/layout tooling). |

## Behavior switches

| Variable | Purpose |
|---|---|
| `CADR_OFFLINE` | `1` disables all network access (model fetches, update checks, tool downloads). |
| `CADR_SKIP_VERSION_CHECK` | Skip the startup version check. |
| `CADR_VERSION_CHECK_URL` | Override the version-check endpoint. |
| `CADR_TELEMETRY` | Telemetry toggle (cadr emits none). |
| `CADR_EXPERIMENTAL` | Enable experimental gates. |

## Diagnostics (development)

| Variable | Purpose |
|---|---|
| `CADR_TIMING` | Print startup timing breakdown. |
| `CADR_STARTUP_BENCHMARK` | Startup benchmark mode (interactive only). |
| `CADR_HARDWARE_CURSOR` / `CADR_CLEAR_ON_SHRINK` | Terminal rendering toggles. |
| `CADR_EVAL_PROVIDER` / `CADR_EVAL_MODEL` / `CADR_EVAL_ARTIFACT_DIR` | Eval harness routing. |
| `CADR_SERVER_DIR` / `CADR_SERVER_CADR_PATH` / `CADR_RADIUS_URL` / `CADR_RADIUS_SERVER_URL` | cadr-server deployment. |
