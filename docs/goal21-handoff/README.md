# Goal 21 lane handoff notes

Each impl lane (`a`, `b`, `c`, `parity`) keeps a handoff file updated at the end of every
resumed `cursor-agent` session (`GOAL21_HANDOFF` block in dispatch log).

Session chat IDs live in `docs/benchmarks/cadr-team-agent-sessions.json` (key: `goal21-lane-<lane>`).

Gate fix agents stay stateless (`CADR_AGENT_RESUME=0`).
