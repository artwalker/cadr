#!/usr/bin/env bash
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

"$project_root/scripts/verify.sh"
"$project_root/scripts/test-render-diff-full.sh"
