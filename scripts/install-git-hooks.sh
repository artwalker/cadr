#!/usr/bin/env bash
# Point this repo at .githooks/ (pre-commit compile check for src/).
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
chmod +x "$PROJECT_DIRECTORY/.githooks/pre-commit"
git -C "$PROJECT_DIRECTORY" config core.hooksPath .githooks
echo "install-git-hooks: core.hooksPath=.githooks"
