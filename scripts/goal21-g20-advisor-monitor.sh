#!/usr/bin/env bash
# Goal 21 + Goal 20 advisor monitor: progress wakes + team health checks.
#
# Emits AGENT_LOOP_WAKE_g21g20 lines for the advisor loop (/loop or shell watcher).
#
# usage:
#   scripts/goal21-g20-advisor-monitor.sh once          # one tick (status + health)
#   scripts/goal21-g20-advisor-monitor.sh loop [poll_sec]
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY"
POLL_SEC="${GOAL21_G20_MONITOR_POLL_SEC:-45}"
HEALTH_EVERY_TICKS="${GOAL21_G20_HEALTH_EVERY_TICKS:-4}" # ~3 min at 45s poll
TMUX_SESSION="${GOAL21_TEAM_SESSION:-goal21-team}"
STALE_SCRIPT="$PROJECT_DIRECTORY/scripts/cadr-team-stale-agents.sh"
SYNC_SCRIPT="$PROJECT_DIRECTORY/scripts/goal21-gate-queue-sync.sh"

PROMPT='持续监督 Goal21/Goal20 开发团队：读 health + queue + gate 进度；发现卡死/僵尸/queue 不同步/heal 空转则立即修复（stale-agents、queue-sync、operator once、gate-dispatch-fix、重启 monitor）；确保 gate/impl lane 不中断；简短汇报；G21 task7=done 且 G20 全 done 时报告完成并请停止 loop。'
OPERATOR_SCRIPT="$PROJECT_DIRECTORY/scripts/goal21-team-operator.sh"
TMUX_SCRIPT="$PROJECT_DIRECTORY/scripts/goal21-team-tmux.sh"
HEAL_LOG="${GOAL21_G20_MONITOR_HEAL_LOG:-/tmp/goal21-g20-monitor-heal.log}"

emit() {
	local event="$1"
	local detail="$2"
	printf 'AGENT_LOOP_WAKE_g21g20 {"event":"%s","detail":%s,"prompt":%s}\n' \
		"$event" "$detail" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PROMPT")"
}

status_json() {
	python3 - "$CADR" <<'PY'
import json, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1])
out: dict = {}
g21 = json.loads((root / "docs/benchmarks/goal21-queue.json").read_text())
out["g21_task7"] = next(t["status"] for t in g21["tasks"] if t["id"] == 7)
out["g21_goal20_paused"] = g21.get("goal20Paused", True)
g20_path = root / "docs/benchmarks/goal20-queue.json"
if g20_path.is_file():
    g20 = json.loads(g20_path.read_text())
    tasks = g20.get("tasks", [])
    out["g20_paused"] = g20.get("paused", True)
    out["g20_done"] = sum(1 for t in tasks if t.get("status") == "done")
    out["g20_total"] = len(tasks)
    out["g20_pending"] = sum(1 for t in tasks if t.get("status") != "done")
else:
    out["g20_paused"] = True
    out["g20_pending"] = -1
out["head"] = subprocess.check_output(
    ["git", "-C", str(root), "rev-parse", "--short", "HEAD"], text=True
).strip()
print(json.dumps(out, separators=(",", ":")))
PY
}

g21_g20_complete() {
	python3 - "$CADR" <<'PY'
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
g21 = json.loads((root / "docs/benchmarks/goal21-queue.json").read_text())
if g21.get("goal20Paused", True):
    sys.exit(1)
t7 = next(t for t in g21["tasks"] if t["id"] == 7)
if t7.get("status") != "done":
    sys.exit(1)
g20_path = root / "docs/benchmarks/goal20-queue.json"
if not g20_path.is_file():
    sys.exit(1)
g20 = json.loads(g20_path.read_text())
if g20.get("paused", True):
    sys.exit(1)
if any(t.get("status") != "done" for t in g20.get("tasks", [])):
    sys.exit(1)
sys.exit(0)
PY
}

health_json() {
	python3 - "$CADR" "$TMUX_SESSION" <<'PY'
import json, os, subprocess, time
from pathlib import Path

root = Path(__import__("sys").argv[1])
tmux_session = __import__("sys").argv[2]
now = int(time.time())
gate_stale_sec = int(os.environ.get("GOAL21_GATE_ACTIVITY_STALE_SEC", "900"))
operator_loop_sec = int(os.environ.get("GOAL21_OPERATOR_LOOP_SEC", "180"))
operator_stale_sec = max(operator_loop_sec * 4, 600)

progress = Path(os.environ.get("GOAL21_GATE_PROGRESS", "/tmp/goal21-gate-progress"))
run_log = Path(os.environ.get("GOAL21_GATE_RUN_LOG", "/tmp/goal21-gate-run.log"))
dispatch_gate = Path("/tmp/goal21-dispatch-gate.log")
queue_path = root / "docs/benchmarks/goal21-queue.json"

def pgrep_count(pattern: str) -> int:
    p = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True)
    if p.returncode != 0:
        return 0
    return len([ln for ln in p.stdout.splitlines() if ln.strip()])

def file_age(path: Path):
    if not path.is_file():
        return None
    return now - int(path.stat().st_mtime)

def tmux_alive(name: str) -> bool:
    p = subprocess.run(["tmux", "has-session", "-t", name], capture_output=True)
    return p.returncode == 0

issues: list[dict] = []
info: dict = {}

gate_runs = pgrep_count(r"goal21-gate-run\.sh")

def ppid_of(pid: int) -> int:
    p = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True)
    try:
        return int(p.stdout.strip())
    except ValueError:
        return 0

def is_verify_pid(pid: int) -> bool:
    p = subprocess.run(["ps", "-o", "cmd=", "-p", str(pid)], capture_output=True, text=True)
    return "verify.sh" in p.stdout

def pgrep_pids(pattern: str) -> list[int]:
    p = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True)
    if p.returncode != 0:
        return []
    return [int(x) for x in p.stdout.split() if x.strip().isdigit()]

def gate_root_pids() -> list[int]:
    pids = pgrep_pids(r"goal21-gate-run\.sh")
    gate_set = set(pids)
    return [pid for pid in pids if ppid_of(pid) not in gate_set]

def verify_root_pids() -> list[int]:
    pids = pgrep_pids(r"scripts/verify\.sh")
    return [pid for pid in pids if not is_verify_pid(ppid_of(pid))]

def gate_ancestor(pid: int, gate_roots: set[int]) -> bool:
    cur = pid
    for _ in range(64):
        if cur in gate_roots:
            return True
        parent = ppid_of(cur)
        if parent <= 1 or parent == cur:
            return False
        cur = parent
    return False

root_gate_runs = len(gate_root_pids())
gate_roots = set(gate_root_pids())
info["gate_root_runs"] = root_gate_runs
verify_pids = pgrep_pids(r"scripts/verify\.sh")
verify_roots = verify_root_pids()
verify_runs = len(verify_pids)
verify_root_runs = len(verify_roots)
info["verify_runs"] = verify_runs
info["verify_root_runs"] = verify_root_runs
if verify_runs > verify_root_runs:
    info["verify_nested_runs"] = verify_runs - verify_root_runs
test_cl_runs = pgrep_count(r"scripts/test-cl\.sh")
operator_runs = pgrep_count(r"goal21-team-operator\.sh loop")
sbcl_runs = pgrep_count(r"sbcl.*asdf:test-system")

info.update(
    gate_runs=gate_runs,
    verify_runs=verify_runs,
    test_cl_runs=test_cl_runs,
    operator_runs=operator_runs,
    sbcl_runs=sbcl_runs,
    tmux_operator=tmux_alive(tmux_session),
)

ages = [a for a in (file_age(progress), file_age(run_log)) if a is not None]
gate_activity_age = min(ages) if ages else None
info["gate_activity_age_sec"] = gate_activity_age
info["gate_progress"] = progress.read_text(encoding="utf-8", errors="replace").strip().splitlines()[-1:] if progress.is_file() else []

if root_gate_runs > 1:
    issues.append({"kind": "duplicate_gate", "severity": "high", "gate_runs": gate_runs, "gate_root_runs": root_gate_runs})
elif gate_runs > 1 and root_gate_runs == 1:
    info["gate_nested_runs"] = gate_runs - root_gate_runs

orphan_verify = [v for v in verify_roots if not gate_roots or not gate_ancestor(v, gate_roots)]
if orphan_verify:
    issues.append({"kind": "orphan_verify", "severity": "high", "pids": orphan_verify})
elif verify_root_runs > 1 and root_gate_runs == 1:
    issues.append({"kind": "duplicate_verify", "severity": "medium", "verify_root_runs": verify_root_runs})

gate_work = gate_runs > 0 or verify_runs > 0 or test_cl_runs > 0
if gate_work and gate_activity_age is not None and gate_activity_age >= gate_stale_sec:
    issues.append(
        {
            "kind": "gate_stale",
            "severity": "high",
            "idle_sec": gate_activity_age,
            "threshold_sec": gate_stale_sec,
        }
    )

if not tmux_alive(tmux_session):
    issues.append({"kind": "operator_tmux_missing", "severity": "high", "session": tmux_session})
elif operator_runs == 0:
    issues.append({"kind": "operator_process_missing", "severity": "high", "session": tmux_session})

dispatch_age = file_age(dispatch_gate)
info["dispatch_gate_age_sec"] = dispatch_age
if dispatch_age is not None and dispatch_age >= operator_stale_sec and gate_runs == 0:
    g21 = json.loads(queue_path.read_text())
    gate_pending = any(t.get("lane") == "gate" and t.get("status") == "pending" for t in g21.get("tasks", []))
    gate_inprog = any(t.get("lane") == "gate" and t.get("status") == "in_progress" for t in g21.get("tasks", []))
    if gate_pending or gate_inprog:
        issues.append(
            {
                "kind": "operator_idle",
                "severity": "medium",
                "dispatch_idle_sec": dispatch_age,
                "gate_pending": gate_pending,
                "gate_in_progress": gate_inprog,
            }
        )

g21 = json.loads(queue_path.read_text())
blob = subprocess.run(
    ["pgrep", "-af", "cursor-agent|goal21-gate-run|cadr-team-dispatch.*gate|goal21-orchestrator.sh dispatch gate"],
    capture_output=True,
    text=True,
).stdout
for task in g21.get("tasks", []):
    if task.get("id") == 7 and task.get("lane") == "gate":
        info["gate_task_status"] = task.get("status")
        if gate_runs > 0 and task.get("status") == "pending":
            issues.append({"kind": "gate_queue_desync", "severity": "medium", "task_status": "pending", "gate_runs": gate_runs})
        break

run_log = Path(os.environ.get("GOAL21_GATE_RUN_LOG", "/tmp/goal21-gate-run.log"))
if run_log.is_file():
    lines = run_log.read_text(encoding="utf-8", errors="replace").splitlines()
    info["run_log_tail"] = lines[-1] if lines else ""
    info["run_log_age_sec"] = file_age(run_log)
else:
    info["run_log_tail"] = ""
    info["run_log_age_sec"] = None

for task in g21.get("tasks", []):
    if task.get("lane") != "gate" or task.get("status") != "in_progress":
        continue
    if "Gate" not in blob and "gate-7" not in blob and "goal21-gate-run" not in blob:
        issues.append({"kind": "gate_queue_zombie", "severity": "high", "task_id": task.get("id")})
        break

fail_type = Path(os.environ.get("GOAL21_GATE_FAILURE_TYPE_FILE", "/tmp/goal21-gate-failure-type"))
fail_log = Path("/tmp/goal21-gate-fail.txt")
classify = root / "scripts/goal21-gate-classify-failure.sh"
if fail_log.is_file() and classify.is_file():
    classified = subprocess.run(
        [str(classify), str(fail_log)], capture_output=True, text=True, check=False
    ).stdout.strip()
    if classified and classified != "unknown":
        info["last_failure_type"] = classified
elif fail_type.is_file():
    info["last_failure_type"] = fail_type.read_text(encoding="utf-8", errors="replace").strip()
else:
    info["last_failure_type"] = ""

if info.get("last_failure_type") and dispatch_gate.is_file():
    ft = info["last_failure_type"]
    lines = [ln for ln in dispatch_gate.read_text(encoding="utf-8", errors="replace").splitlines() if ln.strip()]
    info["dispatch_gate_lines"] = len(lines)
    if ft and len(lines) >= 6:
        recent = "\n".join(lines[-12:])
        if recent.count(ft) >= 3 and gate_runs == 0:
            issues.append({"kind": "heal_loop_stuck", "severity": "medium", "failure_type": ft, "recent_hits": recent.count(ft)})

fail_log = Path("/tmp/goal21-gate-fail.txt")
needs_agent = root / "scripts/goal21-gate-failure-needs-agent.sh"
if (
    fail_log.is_file()
    and gate_runs == 0
    and needs_agent.is_file()
    and subprocess.run([str(needs_agent), str(fail_log)], check=False).returncode == 0
    and not any(i.get("kind") == "gate_failure_needs_agent" for i in issues)
):
    fix_busy = subprocess.run(
        ["pgrep", "-af", "cursor-agent.*(Goal 21 Gate SPECIALIST|gate-specialist-|gate-fix-)"],
        capture_output=True,
        text=True,
    ).returncode == 0
    if not fix_busy:
        issues.append(
            {
                "kind": "gate_failure_needs_agent",
                "severity": "high",
                "failure_type": info.get("last_failure_type") or "unknown",
            }
        )

out = {"ok": len(issues) == 0, "issues": issues, "info": info, "checked_at": now}
print(json.dumps(out, separators=(",", ":")))
PY
}

heal_log() {
	printf '%s\t%s\n' "$(date -Iseconds)" "$*" >>"$HEAL_LOG"
}

auto_heal_team() {
	local health="$1"
	local kinds
	kinds="$(python3 -c 'import json,sys; print(" ".join(i["kind"] for i in json.loads(sys.argv[1]).get("issues",[])))' "$health")"
	[ -n "$kinds" ] || return 1

	heal_log "auto_heal start kinds=$kinds"

	case " $kinds " in
	*" gate_queue_desync "*)
		if [ -x "$SYNC_SCRIPT" ]; then
			heal_log "running goal21-gate-queue-sync.sh"
			"$SYNC_SCRIPT" >>"$HEAL_LOG" 2>&1 || true
		fi
		;;
	esac

	case " $kinds " in
	*" duplicate_gate "* | *" orphan_verify "* | *" duplicate_verify "*)
		if [ -x "$STALE_SCRIPT" ]; then
			heal_log "running cadr-team-stale-agents dedupe"
			"$STALE_SCRIPT" once >>"$HEAL_LOG" 2>&1 || true
		fi
		;;
	esac

	case " $kinds " in
	*" gate_stale "* | *" gate_queue_zombie "* | *" operator_process_missing "*)
		if [ -x "$STALE_SCRIPT" ]; then
			heal_log "running cadr-team-stale-agents.sh"
			"$STALE_SCRIPT" once >>"$HEAL_LOG" 2>&1 || true
		fi
		;;
	esac

	case " $kinds " in
	*" operator_tmux_missing "*)
		if [ -x "$TMUX_SCRIPT" ]; then
			heal_log "starting operator tmux session $TMUX_SESSION"
			"$TMUX_SCRIPT" "$TMUX_SESSION" >>"$HEAL_LOG" 2>&1 || true
		fi
		;;
	esac

	case " $kinds " in
	*" operator_idle "* | *" operator_process_missing "*)
		if [ -x "$OPERATOR_SCRIPT" ]; then
			heal_log "nudging goal21-team-operator once"
			"$OPERATOR_SCRIPT" once >>"$HEAL_LOG" 2>&1 || true
		fi
		;;
	esac

	case " $kinds " in
	*" heal_loop_stuck "* | *" gate_failure_needs_agent "*)
		local ft
		ft="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(next((i.get("failure_type","") for i in d.get("issues",[]) if i.get("kind") in ("heal_loop_stuck","gate_failure_needs_agent")),""))' "$health")"
		if [ "$ft" = "render-diff" ] || [ -z "$ft" ]; then
			if pgrep -af 'goal21-orchestrator\.sh dispatch gate|goal21-gate-proactive-render-diff\.sh|goal21-gate-postfix-check\.sh|render-diff\.py analyze' >/dev/null 2>&1; then
				heal_log "skip proactive render-diff (orchestrator/postfix/analyze already active)"
			elif [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-proactive-render-diff.sh" ]; then
				heal_log "running goal21-gate-proactive-render-diff.sh"
				"$PROJECT_DIRECTORY/scripts/goal21-gate-proactive-render-diff.sh" >>"$HEAL_LOG" 2>&1 || true
			fi
			if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-auto-fix-render-diff.sh" ]; then
				heal_log "running goal21-gate-auto-fix-render-diff.sh"
				"$PROJECT_DIRECTORY/scripts/goal21-gate-auto-fix-render-diff.sh" >>"$HEAL_LOG" 2>&1 || true
			fi
		fi
		if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-dispatch-fix.sh" ]; then
			if ! pgrep -af 'goal21-gate-run\.sh|scripts/verify\.sh' >/dev/null 2>&1 \
				&& ! pgrep -af 'cursor-agent.*(Goal 21 Gate SPECIALIST|gate-specialist-|gate-fix-)' >/dev/null 2>&1; then
				heal_log "dispatching gate fix specialist (background)"
				"$PROJECT_DIRECTORY/scripts/goal21-gate-dispatch-fix.sh" >>"$HEAL_LOG" 2>&1 &
			fi
		elif [ -x "$OPERATOR_SCRIPT" ] && ! pgrep -af 'goal21-gate-run\.sh' >/dev/null 2>&1; then
			heal_log "nudging operator for gate fix dispatch"
			"$OPERATOR_SCRIPT" once >>"$HEAL_LOG" 2>&1 || true
		fi
		;;
	esac

	heal_log "auto_heal done"
	return 0
}

monitor_tick() {
	local emit_progress="${1:-yes}"

	if g21_g20_complete; then
		emit "complete" "$(status_json)"
		return 2
	fi

	local health
	health="$(health_json)"

	if [ "$emit_progress" = "yes" ]; then
		local head gate progress run_tail
		head="$(git -C "$CADR" rev-parse HEAD 2>/dev/null || echo none)"
		gate="$(tail -n 1 /tmp/goal21-dispatch-gate.log 2>/dev/null || echo none)"
		progress="$(cat /tmp/goal21-gate-progress 2>/dev/null || echo none)"
		run_tail="$(tail -n 1 /tmp/goal21-gate-run.log 2>/dev/null || echo none)"

		if [ "${LAST_HEAD:-}" != "$head" ]; then
			emit "commit" "$(python3 -c 'import json,sys; print(json.dumps({**json.loads(sys.argv[1]),"health":json.loads(sys.argv[2])}))' "$(status_json)" "$health")"
			LAST_HEAD="$head"
		elif [ "${LAST_GATE:-}" != "$gate" ]; then
			emit "gate" "$(python3 -c 'import json,sys; print(json.dumps({**json.loads(sys.argv[1]),"health":json.loads(sys.argv[2])}))' "$(status_json)" "$health")"
			LAST_GATE="$gate"
		elif [ "${LAST_PROGRESS:-}" != "$progress" ]; then
			emit "progress" "$(python3 -c 'import json,sys; print(json.dumps({**json.loads(sys.argv[1]),"health":json.loads(sys.argv[2])}))' "$(status_json)" "$health")"
			LAST_PROGRESS="$progress"
		elif [ "${LAST_RUN_LOG_TAIL:-}" != "$run_tail" ] && [ "$run_tail" != "none" ] && [ -n "$run_tail" ]; then
			emit "run_log" "$(python3 -c 'import json,sys; print(json.dumps({**json.loads(sys.argv[1]),"run_log_tail":sys.argv[2],"health":json.loads(sys.argv[3])}))' "$(status_json)" "$run_tail" "$health")"
			LAST_RUN_LOG_TAIL="$run_tail"
		fi
	fi

	local issue_sig
	issue_sig="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(json.dumps(d.get("issues",[]),sort_keys=True))' "$health")"
	if [ "$issue_sig" != "[]" ] && [ "$issue_sig" != "${LAST_HEALTH_ISSUES:-[]}" ]; then
		auto_heal_team "$health" || true
		emit "health" "$(python3 -c 'import json,sys; print(json.dumps({"status":json.loads(sys.argv[1]),"health":json.loads(sys.argv[2])}))' "$(status_json)" "$health")"
		LAST_HEALTH_ISSUES="$issue_sig"
	elif [ "$issue_sig" = "[]" ]; then
		LAST_HEALTH_ISSUES="[]"
	fi

	return 0
}

case "${1:-loop}" in
once)
	monitor_tick yes
	;;
loop)
	INTERVAL="${2:-$POLL_SEC}"
	tick=0
	LAST_HEAD="$(git -C "$CADR" rev-parse HEAD 2>/dev/null || echo none)"
	LAST_GATE="$(tail -n 1 /tmp/goal21-dispatch-gate.log 2>/dev/null || echo none)"
	LAST_PROGRESS="$(cat /tmp/goal21-gate-progress 2>/dev/null || echo none)"
	LAST_RUN_LOG_TAIL="$(tail -n 1 /tmp/goal21-gate-run.log 2>/dev/null || echo none)"
	LAST_HEALTH_ISSUES="[]"
	echo "AGENT_G21G20_MONITOR_START poll=${INTERVAL}s health_every=${HEALTH_EVERY_TICKS} pid=$$ head=${LAST_HEAD}"
	while true; do
		if monitor_tick yes; then
			:
		else
			exit 0
		fi
		tick=$((tick + 1))
		if [ $((tick % HEALTH_EVERY_TICKS)) -eq 0 ]; then
			if [ -x "$SYNC_SCRIPT" ]; then
				"$SYNC_SCRIPT" >/dev/null 2>&1 || true
			fi
			health="$(health_json)"
			issue_sig="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(json.dumps(d.get("issues",[]),sort_keys=True))' "$health")"
			if [ "$issue_sig" != "[]" ]; then
				if [ "$issue_sig" != "${LAST_HEALTH_ISSUES:-[]}" ]; then
					auto_heal_team "$health" || true
					emit "health" "$(python3 -c 'import json,sys; print(json.dumps({"status":json.loads(sys.argv[1]),"health":json.loads(sys.argv[2])}))' "$(status_json)" "$health")"
					LAST_HEALTH_ISSUES="$issue_sig"
				else
					auto_heal_team "$health" || true
					emit "health_repeat" "$(python3 -c 'import json,sys; print(json.dumps({"status":json.loads(sys.argv[1]),"health":json.loads(sys.argv[2])}))' "$(status_json)" "$health")"
				fi
			else
				emit "pulse" "$(python3 -c 'import json,sys; print(json.dumps({**json.loads(sys.argv[1]),"health":json.loads(sys.argv[2])}))' "$(status_json)" "$health")"
				LAST_HEALTH_ISSUES="[]"
			fi
		fi
		sleep "$INTERVAL"
	done
	;;
health)
	health_json
	;;
status)
	status_json
	;;
*)
	echo "usage: $0 once|loop [poll_sec]|health|status" >&2
	exit 2
	;;
esac
