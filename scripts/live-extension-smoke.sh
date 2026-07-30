#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"

if [ ! -x "$CADR" ]; then
  echo "live extension smoke: build ./cadr first" >&2
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
  env -u CADR_MODEL HOME="$SMOKE_ROOT/home" \
    "$CADR" \
    --no-tui \
    --provider deepseek \
    --model deepseek-v4-flash \
    --system-prompt \
    "This is a deterministic self-extension test. Follow each request exactly. Use tools when explicitly requested; do not access the network." \
    >"$OUTPUT" <<'EOF'
Use the write tool exactly once to create .cadr/extensions/live/extension.lisp with exactly this one-line content, then reply exactly WRITTEN: (define-tool "live-echo" :description "Return the supplied value with a live prefix." :parameters (cadr-ai::json-object "type" "object" "properties" (cadr-ai::json-object "value" (cadr-ai::json-object "type" "string")) "required" (vector "value") "additionalProperties" nil) :handler (lambda (call-id arguments context) (declare (ignore call-id context)) (values (list (cadr-ai:make-text-content :text (format nil "live:~A" (cadr-ai::json-get arguments "value")))) nil)))
/reload
Call the live-echo tool with value phase7. After it succeeds, reply exactly SELF_EXTENSION_OK.
EOF
)

EXTENSION="$SMOKE_ROOT/project/.cadr/extensions/live/extension.lisp"
if [ ! -f "$EXTENSION" ]; then
  echo "live extension smoke: agent did not create the extension" >&2
  sed -n '1,200p' "$OUTPUT" >&2
  exit 1
fi

SESSION="$(
  find "$SMOKE_ROOT/home/.cadr/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' -print -quit
)"

if [ -z "$SESSION" ] ||
  ! grep -Fq '"toolName":"live-echo"' "$SESSION" ||
  ! grep -Fq 'live:phase7' "$SESSION" ||
  ! grep -Fq 'SELF_EXTENSION_OK' "$OUTPUT"; then
  echo "live extension smoke: write/reload/invoke loop did not complete" >&2
  sed -n '1,240p' "$OUTPUT" >&2
  exit 1
fi

echo "live extension smoke: DeepSeek write/reload/invoke loop passed"
