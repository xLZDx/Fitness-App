# Claude Code compatibility

Verified against current official Claude Code documentation on 2026-08-15.

## Required/recommended versions

- Nested custom subagents are supported in current Claude Code.
- Current default nesting depth is 3 subagent layers below main.
- v2.1.219 raised the default depth to 3.
- For this pack, use **Claude Code >= 2.1.219** if you want the documented default nested orchestrator behavior.

Recommended project setting:

```json
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2"
  }
}
```

Depth 2 is enough for `main -> fitness-recommendation-orchestrator -> specialist` and deliberately prevents unnecessary third-layer delegation. Specialists in this package also omit `Agent` from their tool list.

Claude Code has an important split behavior for `Agent(type, ...)`:

- when an agent file runs as the **main thread** via `claude --agent`, the type list is a real allowlist;
- when the same file runs as a **subagent**, current Claude Code allows nested spawning but ignores the type list inside `Agent(...)`.

For that reason v2.2 keeps `Agent(type, ...)` for strict main-thread mode **and** adds a scoped `PreToolUse` command hook to the orchestrator. The hook validates `tool_input.subagent_type` against `.claude/policies/fitness-child-agents.json` and blocks an unknown child with exit code 2. Command hooks can deny a call even under `bypassPermissions`.

## Context loading

Custom subagents receive their own system prompt, task message, CLAUDE.md hierarchy, git status (except built-in Explore/Plan), and full contents of skills named in their `skills:` frontmatter.

Official references:
- https://code.claude.com/docs/en/sub-agents
- https://code.claude.com/docs/en/slash-commands

## Child-agent policy hook

The nested-mode guard uses a component-scoped `PreToolUse` hook on the `Agent` tool. Claude Code supplies `tool_input.subagent_type`; the command hook compares it with `.claude/policies/fitness-child-agents.json` and exits `2` on unknown or missing types. The hook is invoked using `${CLAUDE_PROJECT_DIR}` so it is not dependent on launching Claude from the repository root.
