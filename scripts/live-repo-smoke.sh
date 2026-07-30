#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"

if [ ! -x "$CADR" ]; then
  echo "live repo smoke: build ./cadr first" >&2
  exit 1
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "live repo smoke: DEEPSEEK_API_KEY is not set" >&2
  exit 2
fi

if [ "${CADR_ALLOW_LIVE_TOOL_SMOKE:-}" != "1" ]; then
  echo "live repo smoke: set CADR_ALLOW_LIVE_TOOL_SMOKE=1 to authorize the isolated live tool test" >&2
  exit 2
fi

SMOKE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$SMOKE_ROOT"' EXIT
mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/project"

cat >"$SMOKE_ROOT/project/calc.sh" <<'EOF'
#!/usr/bin/env bash
add() {
  printf '%s\n' "$(($1 - $2))"
}
EOF

cat >"$SMOKE_ROOT/project/test.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
. ./calc.sh
actual="$(add 2 3)"
if [ "$actual" != "5" ]; then
  echo "expected 5, got $actual" >&2
  exit 1
fi
echo "test passed"
EOF
chmod +x "$SMOKE_ROOT/project/test.sh"

OUTPUT="$SMOKE_ROOT/output.txt"
(
  cd "$SMOKE_ROOT/project"
  env -u CADR_MODEL HOME="$SMOKE_ROOT/home" \
    "$CADR" \
    --provider deepseek \
    --model deepseek-v4-flash \
    --system-prompt \
    "You are running an acceptance test. Work only inside the current directory, do not access the network, inspect before editing, and verify the final result." \
    >"$OUTPUT" <<'EOF'
First run ./test.sh and observe its failure. Then inspect the files, fix the add function, rerun ./test.sh, and do not stop until it passes.
EOF
)

if ! (cd "$SMOKE_ROOT/project" && ./test.sh >/dev/null); then
  echo "live repo smoke: repository test still fails" >&2
  sed -n '1,160p' "$OUTPUT" >&2
  exit 1
fi

SESSION_FILE="$(
  find "$SMOKE_ROOT/home/.cadr/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' -print -quit
)"

if [ -z "$SESSION_FILE" ] ||
  ! grep -Fq "Process exited with code 1" "$SESSION_FILE" ||
  ! grep -Fq "Process exited with code 0" "$SESSION_FILE"; then
  echo "live repo smoke: session did not record the required fail/fix/pass loop" >&2
  sed -n '1,160p' "$OUTPUT" >&2
  exit 1
fi

echo "live repo smoke: DeepSeek read/edit/fail/fix/pass loop passed"
