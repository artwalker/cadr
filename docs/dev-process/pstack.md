# pstack on cadr

Measured 2026-08-28. Command: `git -C .cursor/pstack/../.. rev-parse` is not
the pin; the plugin pin is `.cursor/pstack/PIN`.

Lauren Tan's pstack is Cursor's engineering method for developing
this repository (Cloud Agents, desktop Composer, Grok Bot driving
Cursor). Original post:
https://x.com/poteto/status/2058975157503570132

It is not a cadr product feature. Do not load it with `./cadr --skills`,
do not copy it into `.cadr/skills/`, and do not document it in user-facing
cadr docs.

What moved (Cursor-only paths under `.cursor/`):

- Full plugin tree (skills, playbooks, principles, agents, automations,
  docs) vendored at `.cursor/pstack/` (MIT).
- Cursor discovery: `.cursor/skills/<name>` → symlink into that tree.
- cadr overlay: `.cursor/skills/cadr-mode/SKILL.md` (always-on rule
  `.cursor/rules/cadr-mode.mdc`).

cadr constraints that stay above pstack: five ledgers, `test-cl.sh` +
`verify.sh`, no agent merges, `CADR_*` only, baseline-locked
assertions, disjoint writers (`docs/development-policy.md` §7).
