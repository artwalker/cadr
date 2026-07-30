#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PI_CL="$PROJECT_DIRECTORY/pi-cl"

if [ ! -x "$PI_CL" ]; then
  echo "live extension smoke: build ./pi-cl first" >&2
  exit 1
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "live extension smoke: DEEPSEEK_API_KEY is not set" >&2
  exit 2
fi

SMOKE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$SMOKE_ROOT"' EXIT
mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/project"

OUTPUT="$SMOKE_ROOT/output.txt"
(
  cd "$SMOKE_ROOT/project"
  env -u PI_CL_MODEL HOME="$SMOKE_ROOT/home" \
    "$PI_CL" \
    --provider deepseek \
    --model deepseek-v4-flash \
    --system-prompt \
    "This is a deterministic self-extension test. Follow each request exactly. Use tools when explicitly requested; do not access the network." \
    >"$OUTPUT" <<'EOF'
Use the write tool exactly once to create .pi-cl/extensions/live/extension.lisp with exactly this content:
(define-tool "live-echo"
  :description "Return the supplied value with a live prefix."
  :parameters (pi-ai::json-object "type" "object" "properties" (pi-ai::json-object "value" (pi-ai::json-object "type" "string")) "required" (vector "value") "additionalProperties" nil)
  :handler (lambda (call-id arguments context)
             (declare (ignore call-id context))
             (values (list (pi-ai:make-text-content :text (format nil "live:~A" (pi-ai::json-get arguments "value")))) nil)))
After the write succeeds, reply exactly WRITTEN.
/reload
Call the live-echo tool with value phase7. After it succeeds, reply exactly SELF_EXTENSION_OK.
EOF
)

EXTENSION="$SMOKE_ROOT/project/.pi-cl/extensions/live/extension.lisp"
if [ ! -f "$EXTENSION" ]; then
  echo "live extension smoke: agent did not create the extension" >&2
  sed -n '1,200p' "$OUTPUT" >&2
  exit 1
fi

SESSION="$(
  find "$SMOKE_ROOT/home/.pi-cl/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' -print -quit
)"

if [ -z "$SESSION" ] ||
  ! grep -Fq '"tool_name":"live-echo"' "$SESSION" ||
  ! grep -Fq 'live:phase7' "$SESSION" ||
  ! grep -Fq 'SELF_EXTENSION_OK' "$OUTPUT"; then
  echo "live extension smoke: write/reload/invoke loop did not complete" >&2
  sed -n '1,240p' "$OUTPUT" >&2
  exit 1
fi

echo "live extension smoke: DeepSeek write/reload/invoke loop passed"
