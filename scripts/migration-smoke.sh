#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"

if [ ! -x "$CADR" ]; then
  echo "migration smoke: build ./cadr first" >&2
  exit 1
fi

if ! command -v script >/dev/null 2>&1; then
  echo "migration smoke: util-linux script is required" >&2
  exit 1
fi

SMOKE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$SMOKE_ROOT"' EXIT

LEGACY_NAME="$(printf '%s%s-cl' p i)"
HOME_DIRECTORY="$SMOKE_ROOT/home"
PROJECT="$SMOKE_ROOT/project"
OLD_DIRECTORY="$HOME_DIRECTORY/.$LEGACY_NAME"
NEW_DIRECTORY="$HOME_DIRECTORY/.cadr"
mkdir -p "$HOME_DIRECTORY" "$PROJECT"

(
  cd "$PROJECT"
  HOME="$HOME_DIRECTORY" ANTHROPIC_API_KEY="offline-smoke" \
    "$CADR" --provider anthropic --no-tui </dev/null >/dev/null
)
mv -- "$NEW_DIRECTORY" "$OLD_DIRECTORY"
mkdir -p "$OLD_DIRECTORY/extensions/example"
printf '%s\n' \
  '(define-command "legacy" (lambda (context) (declare (ignore context)) "ok"))' \
  >"$OLD_DIRECTORY/extensions/example/extension.lisp"
printf '%s\n' '{}' >"$OLD_DIRECTORY/auth.json"
chmod 644 "$OLD_DIRECTORY/auth.json"

set +e
NONINTERACTIVE_OUTPUT="$(
  HOME="$HOME_DIRECTORY" "$CADR" --version </dev/null 2>&1
)"
NONINTERACTIVE_STATUS=$?
set -e

if [ "$NONINTERACTIVE_STATUS" -eq 0 ]; then
  echo "migration smoke: noninteractive migration did not fail closed" >&2
  exit 1
fi

if ! printf '%s' "$NONINTERACTIVE_OUTPUT" | grep -q "Run manually: mv --"; then
  echo "migration smoke: refusal omitted the manual move command" >&2
  exit 1
fi

if [ ! -d "$OLD_DIRECTORY" ] || [ -e "$NEW_DIRECTORY" ]; then
  echo "migration smoke: refusal changed user data" >&2
  exit 1
fi

COMMAND="cd '$PROJECT' && HOME='$HOME_DIRECTORY' ANTHROPIC_API_KEY='offline-smoke' '$CADR' --provider anthropic --continue --no-tui"
printf 'yes\n' | script -qefc "$COMMAND" /dev/null >/dev/null

if [ -e "$OLD_DIRECTORY" ] || [ ! -d "$NEW_DIRECTORY" ]; then
  echo "migration smoke: interactive migration did not move the tree" >&2
  exit 1
fi

if [ ! -f "$NEW_DIRECTORY/extensions/example/extension.lisp" ]; then
  echo "migration smoke: extension was not migrated" >&2
  exit 1
fi

if [ "$(stat -c '%a' "$NEW_DIRECTORY/auth.json")" != "600" ]; then
  echo "migration smoke: migrated auth.json is not mode 0600" >&2
  exit 1
fi

SESSION_COUNT="$(
  find "$NEW_DIRECTORY/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' | wc -l
)"

if [ "$SESSION_COUNT" -ne 1 ]; then
  echo "migration smoke: --continue did not resume the migrated session" >&2
  exit 1
fi

echo "migration smoke: refusal, full move, auth mode, and --continue passed"
