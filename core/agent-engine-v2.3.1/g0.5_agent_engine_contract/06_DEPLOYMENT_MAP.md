# Deployment / installation map

This ZIP is a **source bundle**, not an instruction to overwrite the project blindly.

## Agents

The real repo's `AGENTS.md` says the machine-wide agent/skill roster is sourced from:

`D:\Repo\agents-skills-repo`

and installed into the user's Claude agent/skill locations. Therefore the preferred
deployment is:

```text
agents_v2.3_integrated/.claude/agents/*
agents_v2.3_integrated/.claude/skills/*
agents_v2.3_integrated/.claude/hooks/*
agents_v2.3_integrated/.claude/policies/*
        ↓
the central agents-skills repo / its installation workflow
```

Do not silently duplicate them into `Fitness-App/.claude` if that conflicts with the
repo's current convention.

## Recommendation Engine design

`recommendation_engine_v1.1_real_repo/` is the implementation specification/audit
bundle. It is not production Dart code.

## G0.5 contract

`g0.5_agent_engine_contract/` is the ownership/review contract connecting the two.

## Next write gate

Use:

`recommendation_engine_v1.1_real_repo/06_G1_CLAUDE_CODE_PROMPT.md`

only after the operator explicitly authorizes G1.


## v2.3.1 hard requirement

Do not run the source tree in-place and assume `${CLAUDE_PROJECT_DIR}` points to it. The hook and
policy runtime must be copied to the **actual Fitness-App repo root** `.claude/`. Use `INSTALL/install.py`;
it also pins an absolute Python interpreter into the installed orchestrator definition.
