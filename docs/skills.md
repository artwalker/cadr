# Skills

A skill is a directory containing a `SKILL.md` file with YAML frontmatter:

```markdown
---
name: my-skill
description: What this skill teaches the agent
---
Instructions the agent follows when the skill is active.
```

`name` and `description` are required; the body is free-form markdown.

## Locations

- Global: `~/.cadr/agent/skills/<name>/SKILL.md`
- Project: `.cadr/skills/<name>/SKILL.md` (requires a trusted project)
- Extra paths can be passed with `--skills <path>`.

## How they run

Available skills are listed in the system prompt with their descriptions.
The model activates a skill when its description matches the task, reads
the body, and follows it.

## Conflicts and errors

Two skills with the same name collide: the project skill wins and the
skipped one is listed in the startup `[Skill conflicts]` block. A skill
whose frontmatter is missing `name` or `description` is broken and is
reported in the same block (for example `description is required`) —
fix the frontmatter to silence it.
