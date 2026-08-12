#!/usr/bin/env bash
set -uo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
VERIFY_ROOT="$(mktemp -d)"
ISOLATED_PROJECT="$VERIFY_ROOT/project"
PI_BASELINE_CACHE="/tmp/cadr-render-diff-pi-$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE" | cut -c1-9)"
OVERALL_FAILURE=0

DETERMINISTIC_NAMES=()
DETERMINISTIC_RESULTS=()
LIVE_NAMES=()
LIVE_RESULTS=()

cleanup() {
  rm -rf -- "$VERIFY_ROOT"
}
trap cleanup EXIT

record_deterministic() {
  DETERMINISTIC_NAMES+=("$1")
  DETERMINISTIC_RESULTS+=("$2")
}

record_live() {
  LIVE_NAMES+=("$1")
  LIVE_RESULTS+=("$2")
}

run_deterministic() {
  local name="$1"
  shift
  printf '\n==> %s\n' "$name"
  if "$@"; then
    record_deterministic "$name" PASS
    return 0
  else
    local status=$?
    record_deterministic "$name" "FAIL ($status)"
    OVERALL_FAILURE=1
    return "$status"
  fi
}

run_live() {
  local name="$1"
  shift
  printf '\n==> %s\n' "$name"
  if "$@"; then
    record_live "$name" PASS
    return 0
  else
    local status=$?
    record_live "$name" "FAIL ($status)"
    OVERALL_FAILURE=1
    return "$status"
  fi
}

# A live SKIP is acceptable for everyday verification (credentials are not
# always present) but never for the release gate: CADR_RELEASE_GATE=1 turns
# any live skip into a failure so a release can never exit 0 with live
# verification unrun.
skip_live() {
  local name="$1" reason="$2"
  if [ "${CADR_RELEASE_GATE:-0}" = "1" ]; then
    record_live \
      "$name" \
      "FAIL ($reason; the release gate requires live verification)"
    OVERALL_FAILURE=1
  else
    record_live "$name" "SKIP ($reason)"
  fi
}

skip_deterministic() {
  record_deterministic "$1" "NOT RUN ($2)"
  OVERALL_FAILURE=1
}

copy_isolated_tree() {
  mkdir -p "$ISOLATED_PROJECT"
  tar -C "$PROJECT_DIRECTORY" \
    --exclude=.git \
    --exclude=./cadr \
    --exclude=./cadr-server \
    --exclude=./.cadr \
    --exclude=./.pi-cl \
    --exclude=./.tmp-home \
    --exclude=./.obsidian \
    --exclude=./docs/.obsidian \
    --exclude=./.env \
    --exclude=./.env.* \
    --exclude='*/__pycache__' \
    --exclude='*.pyc' \
    -cf - . |
    tar -C "$ISOLATED_PROJECT" -xf -
}

build_cadr() {
  (
    cd "$ISOLATED_PROJECT"
    ./build.sh
    test -x ./cadr
  )
}

build_cadr_server() {
  (
    cd "$ISOLATED_PROJECT"
    ./build-server.sh
    test -x ./cadr-server
  )
}

run_isolated_script() {
  local relative_path="$1"
  (
    cd "$ISOLATED_PROJECT"
    "$ISOLATED_PROJECT/$relative_path"
  )
}

run_goal11_gate() {
  (
    cd "$ISOLATED_PROJECT"
    ./scripts/bench.sh \
      --label verify-isolated \
      --output "$VERIFY_ROOT/goal11-performance.json"
    ./scripts/goal11-stability.sh \
      --label verify-isolated \
      --output "$VERIFY_ROOT/goal11-stability.json"
    python3 scripts/goal11-performance-gate.py \
      --bench "$VERIFY_ROOT/goal11-performance.json" \
      --stability "$VERIFY_ROOT/goal11-stability.json"
  )
}

run_source_parity_ledger_gate() {
  local ledger="$PROJECT_DIRECTORY/docs/source-parity.md"
  "$PROJECT_DIRECTORY/scripts/check-source-parity-drift.sh" \
    --ledger-only --dispositions "$ledger"
}

run_code_organization_gate() {
  python3 "$PROJECT_DIRECTORY/test/code-organization-gate-test.py" &&
    python3 "$PROJECT_DIRECTORY/scripts/check-code-organization.py" \
      --root "$PROJECT_DIRECTORY" \
      --manifest "$PROJECT_DIRECTORY/docs/code-organization-exemptions.json"
}

run_mermaid_golden_data_gate() {
  # goal 19: test/cadr-tui/mermaid-golden-data.lisp must be byte-identical
  # to what scripts/gen-mermaid-golden-data.py produces from the checked-in
  # grok-mermaid@0.2.2 reference.json.  The generator is fail-closed (rejects
  # structural drift, count changes, and unrepresentable characters), so this
  # gate prevents a hand-edit of the Lisp data from silently diverging from
  # the golden.
  python3 "$PROJECT_DIRECTORY/scripts/gen-mermaid-golden-data.py" --check &&
    python3 "$PROJECT_DIRECTORY/scripts/gen-mermaid-width-data.py" --check
}

run_product_identity_gate() {
  python3 "$PROJECT_DIRECTORY/test/product-identity-gate-test.py" &&
    python3 "$PROJECT_DIRECTORY/scripts/check-product-identity.py" \
      --root "$PROJECT_DIRECTORY" \
      --manifest "$PROJECT_DIRECTORY/docs/product-identity-allowlist.json"
}

run_render_diff_gate() {
  python3 -u "$PROJECT_DIRECTORY/test/render-diff-gate-test.py" &&
    python3 -u "$PROJECT_DIRECTORY/scripts/render-diff.py" gate \
      --pi-repo "$PROJECT_DIRECTORY" \
      --manifest "$PROJECT_DIRECTORY/test/fixtures/render-diff/scenarios.json" \
      --dispositions "$PROJECT_DIRECTORY/test/fixtures/render-diff/dispositions.json" \
      --tier core \
      --baseline-cache "$PI_BASELINE_CACHE" \
      --timeout 60 \
      --output "$VERIFY_ROOT/render-diff" \
      --analysis-output "$VERIFY_ROOT/render-diff-analysis"
}

run_tool_result_diff_gate() {
  python3 "$PROJECT_DIRECTORY/test/tool-result-diff-gate-test.py" &&
    python3 "$PROJECT_DIRECTORY/scripts/tool-result-diff.py" \
      --baseline "$PI_BASELINE_CACHE" \
      --artifacts "$VERIFY_ROOT/tool-result-diff"
}

run_event_diff_gate() {
  python3 "$PROJECT_DIRECTORY/test/event-diff-gate-test.py" &&
    python3 "$PROJECT_DIRECTORY/scripts/event-diff.py" \
      --baseline-repo "$PI_BASELINE_CACHE" \
      --artifacts "$VERIFY_ROOT/event-diff"
}

print_summary() {
  local index
  printf '\nDeterministic stages\n'
  printf '%-48s %s\n' Stage Result
  for ((index = 0; index < ${#DETERMINISTIC_NAMES[@]}; index++)); do
    printf '%-48s %s\n' \
      "${DETERMINISTIC_NAMES[$index]}" \
      "${DETERMINISTIC_RESULTS[$index]}"
  done

  printf '\nLive stages\n'
  printf '%-48s %s\n' Stage Result
  for ((index = 0; index < ${#LIVE_NAMES[@]}; index++)); do
    printf '%-48s %s\n' \
      "${LIVE_NAMES[$index]}" \
      "${LIVE_RESULTS[$index]}"
  done
}

for command in "$SBCL_COMMAND" git node npm python3 tmux script stty jq tar sha256sum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "verify: required command not found: $command" >&2
    exit 2
  fi
done

# Goal 18 Part G5: the render/tool-result/event differential gates run
# both node and npm inside the baseline checkout; they must come from
# the same WSL-side Node installation.  A Windows npm reached through
# WSL interop happens to probe linux today, but that is luck, not a
# guarantee (a win32 esbuild under node_modules would break the gates
# opaquely).
NODE_EXEC_PATH="$(node -p 'process.execPath')"
NPM_GLOBAL_ROOT="$(npm root -g)"
case "$NODE_EXEC_PATH" in
  /mnt/* | *\\* | *[A-Za-z]:[\\/]*)
    echo "verify: node resolves to a Windows installation ($NODE_EXEC_PATH); use the WSL-side Node toolchain (goal18.md Part G5)." >&2
    exit 2
    ;;
esac
case "$NPM_GLOBAL_ROOT" in
  /mnt/* | *\\* | *[A-Za-z]:[\\/]*)
    echo "verify: npm resolves to a Windows installation ($NPM_GLOBAL_ROOT); use the WSL-side Node toolchain (goal18.md Part G5)." >&2
    exit 2
    ;;
esac
NODE_INSTALL_PREFIX="$(cd "$(dirname "$NODE_EXEC_PATH")/.." && pwd)"
case "$NPM_GLOBAL_ROOT" in
  "$NODE_INSTALL_PREFIX"/*)
    ;;
  *)
    echo "verify: node ($NODE_EXEC_PATH) and npm (global root $NPM_GLOBAL_ROOT) come from different Node installations; use one WSL-side Node installation (goal18.md Part G5)." >&2
    exit 2
    ;;
esac

if [ ! -f "$QUICKLISP_SETUP" ]; then
  echo "verify: Quicklisp setup not found at $QUICKLISP_SETUP" >&2
  exit 2
fi
export QUICKLISP_SETUP

DETERMINISTIC_READY=1
if [ -x "$PROJECT_DIRECTORY/cadr" ]; then
  run_deterministic "root cadr binary freshness" \
    "$PROJECT_DIRECTORY/scripts/check-root-binary.sh" ||
    DETERMINISTIC_READY=0
else
  record_deterministic \
    "root cadr binary freshness" \
    "N/A (root binary absent; isolated build follows)"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "code organization gate" \
    run_code_organization_gate || DETERMINISTIC_READY=0
else
  skip_deterministic "code organization gate" "root binary is stale"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "mermaid golden data consistency" \
    run_mermaid_golden_data_gate || DETERMINISTIC_READY=0
else
  skip_deterministic "mermaid golden data consistency" "code organization gate failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "baseline anchor consistency" \
    python3 scripts/baseline-anchor.py check || DETERMINISTIC_READY=0
else
  skip_deterministic "baseline anchor consistency" "mermaid golden data consistency failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "product identity gate" \
    run_product_identity_gate || DETERMINISTIC_READY=0
else
  skip_deterministic "product identity gate" "code organization gate failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "real source parity ledger" \
    run_source_parity_ledger_gate || DETERMINISTIC_READY=0
else
  skip_deterministic "real source parity ledger" "product identity gate failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "source parity drift self-test" \
    "$PROJECT_DIRECTORY/scripts/test-source-parity-drift.sh" ||
    DETERMINISTIC_READY=0
else
  skip_deterministic "source parity drift self-test" "real source parity ledger failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "summarization choke point adversarial self-test" \
    "$PROJECT_DIRECTORY/scripts/test-summarization-choke-point.sh" ||
    DETERMINISTIC_READY=0
else
  skip_deterministic \
    "summarization choke point adversarial self-test" \
    "source parity ledger prerequisite failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "summarization choke point real source" \
    "$PROJECT_DIRECTORY/scripts/check-summarization-choke-point.sh" ||
    DETERMINISTIC_READY=0
else
  skip_deterministic \
    "summarization choke point real source" \
    "summarization choke point adversarial self-test failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "deterministic FiveAM" \
    "$PROJECT_DIRECTORY/scripts/test-cl.sh" || DETERMINISTIC_READY=0
else
  skip_deterministic \
    "deterministic FiveAM" \
    "summarization choke point real source failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ] && copy_isolated_tree; then
  run_deterministic "isolated cadr build" build_cadr || DETERMINISTIC_READY=0
  if [ "$DETERMINISTIC_READY" -eq 1 ]; then
    run_deterministic "isolated cadr-server build" build_cadr_server ||
      DETERMINISTIC_READY=0
  else
    skip_deterministic "isolated cadr-server build" "cadr build failed"
  fi
else
  if [ "$DETERMINISTIC_READY" -eq 1 ]; then
    record_deterministic "isolated source copy" "FAIL"
    OVERALL_FAILURE=1
  fi
  skip_deterministic "isolated cadr build" "deterministic prerequisite failed"
  skip_deterministic "isolated cadr-server build" "deterministic prerequisite failed"
  DETERMINISTIC_READY=0
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "Goal 11 performance and stability gate" \
    run_goal11_gate || DETERMINISTIC_READY=0
else
  skip_deterministic \
    "Goal 11 performance and stability gate" \
    "isolated build unavailable"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "native acceptance smoke" \
    run_isolated_script scripts/acceptance-smoke.sh || DETERMINISTIC_READY=0
  run_deterministic "native process modes" \
    run_isolated_script scripts/test-wave2-process-modes.sh || DETERMINISTIC_READY=0
  run_deterministic "migration PTY smoke" \
    run_isolated_script scripts/migration-smoke.sh || DETERMINISTIC_READY=0
  run_deterministic "Unix socket server smoke" \
    run_isolated_script scripts/server-smoke.sh || DETERMINISTIC_READY=0
  run_deterministic "terminal lifecycle PTY" \
    run_isolated_script scripts/goal9-a2-pty.sh || DETERMINISTIC_READY=0
  run_deterministic "deterministic TUI harness" \
    run_isolated_script scripts/goal5-manual-tui-smoke.sh || DETERMINISTIC_READY=0
else
  skip_deterministic "native acceptance smoke" "isolated build unavailable"
  skip_deterministic "native process modes" "isolated build unavailable"
  skip_deterministic "migration PTY smoke" "isolated build unavailable"
  skip_deterministic "Unix socket server smoke" "isolated build unavailable"
  skip_deterministic "terminal lifecycle PTY" "isolated build unavailable"
  skip_deterministic "deterministic TUI harness" "isolated build unavailable"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "fixed-baseline render differential" \
    run_render_diff_gate || DETERMINISTIC_READY=0
else
  skip_deterministic \
    "fixed-baseline render differential" \
    "deterministic harness prerequisite failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "fixed-baseline tool-result differential" \
    run_tool_result_diff_gate || DETERMINISTIC_READY=0
else
  skip_deterministic \
    "fixed-baseline tool-result differential" \
    "render differential prerequisite failed"
fi

if [ "$DETERMINISTIC_READY" -eq 1 ]; then
  run_deterministic "fixed-baseline event differential" \
    run_event_diff_gate || DETERMINISTIC_READY=0
else
  skip_deterministic \
    "fixed-baseline event differential" \
    "tool-result differential prerequisite failed"
fi

LIVE_PROJECT="$PROJECT_DIRECTORY"
if [ -d "$ISOLATED_PROJECT" ]; then
  LIVE_PROJECT="$ISOLATED_PROJECT"
fi

run_live "credential-gated FiveAM" \
  "$LIVE_PROJECT/scripts/test-live.sh" || true

if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
  if [ -x "$LIVE_PROJECT/cadr" ]; then
    run_live "DeepSeek live TUI" \
      "$LIVE_PROJECT/scripts/live-tui-smoke.sh" || true
  else
    record_live "DeepSeek live TUI" "FAIL (isolated cadr unavailable)"
    OVERALL_FAILURE=1
  fi
else
  skip_live "DeepSeek live TUI" "DEEPSEEK_API_KEY is not set"
fi

print_summary
exit "$OVERALL_FAILURE"
