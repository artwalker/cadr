#!/usr/bin/env bash
# Goal 20 P0 follow-up (advisor ruling, 2026-08-14): the runtime extension
# directory that `cadr` actually loads diverged from examples/extensions/
# for three days with nothing watching, so the user's manual acceptance runs
# were exercising old code while the render-diff gate exercised the
# repository copies.  This check answers exactly one question: "is the code
# the user runs by hand the same code the gates verified?"
#
# It is deliberately NOT a verify.sh stage and never fail-closes a gate: it
# probes local-machine state, not a product property.  A missing runtime
# directory (clean machine, CI) is a skip, not a failure.
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RUNTIME_DIRECTORY="${CADR_RUNTIME_EXTENSIONS:-${HOME}/.cadr/agent/extensions}"

if [ ! -d "$RUNTIME_DIRECTORY" ]; then
  echo "runtime extension drift: skip ($RUNTIME_DIRECTORY does not exist;" \
    "nothing loads local copies on this machine)"
  exit 0
fi

DRIFTED=0
CHECKED=0
while IFS= read -r -d '' REPOSITORY_FILE; do
  NAME="${REPOSITORY_FILE#"$PROJECT_DIRECTORY/examples/extensions/"}"
  RUNTIME_FILE="$RUNTIME_DIRECTORY/$NAME"
  [ -f "$RUNTIME_FILE" ] || continue
  CHECKED=$((CHECKED + 1))
  REPOSITORY_HASH="$(sha256sum "$REPOSITORY_FILE" | cut -d' ' -f1)"
  RUNTIME_HASH="$(sha256sum "$RUNTIME_FILE" | cut -d' ' -f1)"
  if [ "$REPOSITORY_HASH" != "$RUNTIME_HASH" ]; then
    DRIFTED=$((DRIFTED + 1))
    echo "runtime extension drift: $NAME differs from examples/extensions/$NAME" >&2
    echo "  repository: $REPOSITORY_HASH" >&2
    echo "  runtime:    $RUNTIME_HASH" >&2
  fi
done < <(find "$PROJECT_DIRECTORY/examples/extensions" -name '*.lisp' -type f -print0)

if [ "$DRIFTED" -gt 0 ]; then
  echo "runtime extension drift: $DRIFTED of $CHECKED shared files differ;" \
    "manual acceptance would exercise code the gates never saw." \
    "Sync with: cp examples/extensions/<file> $RUNTIME_DIRECTORY/" >&2
  exit 1
fi

echo "runtime extension drift: $CHECKED shared files identical" \
  "($RUNTIME_DIRECTORY matches the repository)"
