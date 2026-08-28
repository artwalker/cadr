# pstack on cadr

Measured 2026-08-28. Command: `git -C .cursor/pstack/../.. rev-parse` is not
the pin; the plugin pin is `.cursor/pstack/PIN`.

Lauren Tan's pstack is the agent engineering method for this
repository. Original post:
https://x.com/poteto/status/2058975157503570132

What moved:

- Full plugin tree (skills, playbooks, principles, agents, automations,
  docs) vendored at `.cursor/pstack/` (MIT).
- Cursor discovery: `.cursor/skills/<name>` → symlink into that tree.
- cadr overlay: `.cursor/skills/cadr-mode/SKILL.md` (always-on rule
  `.cursor/rules/cadr-mode.mdc`).

What did not move into the **product**:

- pstack is not a default cadr user skill pack. Shipping it as
  built-in cadr behavior would be an addition relative to the pinned
  pi baseline. Dogfood with `./cadr --skills .cursor/pstack/skills`.

cadr constraints that stay above pstack: five ledgers, `test-cl.sh` +
`verify.sh`, no agent merges, `CADR_*` only, baseline-locked
assertions, disjoint writers (`docs/development-policy.md` §7).
