#!/usr/bin/env python3
from __future__ import annotations
import json, re, sys, subprocess
from pathlib import Path
try:
    import yaml
except Exception as exc:
    print(f"PyYAML required: {exc}", file=sys.stderr); raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[1]
AGENTS = ROOT / ".claude" / "agents"
SKILLS = ROOT / ".claude" / "skills"


def frontmatter(path: Path):
    text = path.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        raise ValueError("missing YAML frontmatter")
    return yaml.safe_load(m.group(1)), text

errors=[]
agent_defs={}
for p in sorted(AGENTS.glob("*.md")):
    try:
        fm, text=frontmatter(p)
        name=fm.get("name")
        if not name: errors.append(f"{p}: missing name"); continue
        if name in agent_defs: errors.append(f"duplicate agent name: {name}")
        agent_defs[name]=(p,fm,text)
    except Exception as e: errors.append(f"{p}: {e}")

skill_names=set()
for p in sorted(SKILLS.glob("*/SKILL.md")):
    try:
        fm,_=frontmatter(p)
        skill_names.add(fm.get("name") or p.parent.name)
    except Exception as e: errors.append(f"{p}: {e}")

# Canonical nested-child policy. Claude Code applies Agent(type, ...) as a true
# allowlist in main-thread --agent mode, but ignores the parenthesized type list
# when the definition itself runs as a subagent. The orchestrator hook below
# enforces this policy in nested mode.
child_policy_path = ROOT / ".claude" / "policies" / "fitness-child-agents.json"
try:
    child_policy = json.loads(child_policy_path.read_text(encoding="utf-8"))
    child_allowed = set(child_policy.get("allowed_subagent_types") or [])
except Exception as e:
    errors.append(f"fitness child policy invalid: {e}")
    child_allowed = set()

for name,(p,fm,text) in agent_defs.items():
    for s in fm.get("skills",[]) or []:
        if s not in skill_names: errors.append(f"{name}: missing referenced skill {s}")
    tools=fm.get("tools",[]) or []
    agent_tools=[str(t) for t in tools if str(t).startswith("Agent")]
    if name == "fitness-recommendation-orchestrator":
        if len(agent_tools)!=1: errors.append("orchestrator must have exactly one Agent(...) tool")
        elif agent_tools[0].strip()=="Agent": errors.append("orchestrator main-thread mode must use Agent(type, ...) rather than bare Agent")
        else:
            m=re.match(r"Agent\((.*)\)$",agent_tools[0], re.S)
            if not m: errors.append("orchestrator Agent tool syntax malformed")
            else:
                declared={x.strip() for x in m.group(1).split(',') if x.strip()}
                unknown=declared-set(agent_defs)
                if unknown: errors.append(f"orchestrator Agent list has unknown agents: {sorted(unknown)}")
                if name in declared: errors.append("orchestrator must not spawn itself")
                if declared != child_allowed:
                    errors.append(f"orchestrator Agent list differs from nested hook policy: declared_only={sorted(declared-child_allowed)}, policy_only={sorted(child_allowed-declared)}")
        hooks=fm.get("hooks") or {}
        pre=hooks.get("PreToolUse") or []
        hook_ok=False
        for group in pre:
            if str(group.get("matcher")) != "Agent": continue
            for h in group.get("hooks") or []:
                hook_text = str(h.get("command", "")) + " " + " ".join(map(str, h.get("args") or []))
                if h.get("type")=="command" and "validate_fitness_child_agent.py" in hook_text:
                    hook_ok=True
                    command = str(h.get("command", "")).strip()
                    if command == "python":
                        errors.append("orchestrator hook must not use bare `python`; source default is python3 and installer pins an absolute interpreter")
                    args = [str(x) for x in (h.get("args") or [])]
                    expected = "${CLAUDE_PROJECT_DIR}/.claude/hooks/validate_fitness_child_agent.py"
                    if expected not in args:
                        errors.append("orchestrator hook must resolve from project-root .claude via ${CLAUDE_PROJECT_DIR}")
        if not hook_ok:
            errors.append("orchestrator must have scoped PreToolUse Agent child-policy hook")
    elif agent_tools:
        errors.append(f"{name}: specialists must not include Agent tool")

# Hook policy must be fail-closed in nested subagent mode.
hook_script = ROOT / ".claude" / "hooks" / "validate_fitness_child_agent.py"
if not hook_script.exists():
    errors.append("missing nested child-agent validation hook")
elif child_allowed:
    sample = sorted(child_allowed)[0]
    def run_hook(child):
        event={"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":child}}
        return subprocess.run([sys.executable, str(hook_script)], input=json.dumps(event), text=True, capture_output=True)
    ok=run_hook(sample)
    bad=run_hook("definitely-not-a-fitness-agent")
    missing=subprocess.run([sys.executable, str(hook_script)], input=json.dumps({"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{}}), text=True, capture_output=True)
    if ok.returncode != 0: errors.append(f"nested child hook rejected allowed agent {sample}: {ok.stderr.strip()}")
    if bad.returncode == 0: errors.append("nested child hook failed open for unknown agent")
    if missing.returncode == 0: errors.append("nested child hook failed open for missing subagent_type")

# Structured runtime files must parse.
for rel in ["runtime/medication_effects.v1.json","runtime/safety_rules.v1.json","runtime/recommendation_contract.schema.json"]:
    try: json.loads((ROOT/rel).read_text())
    except Exception as e: errors.append(f"{rel}: invalid JSON: {e}")

# Regression guard against v2.1 overclaims deliberately removed.
# We scan local paragraphs and ignore explicit negation/removal language so the checker
# does not fail merely because a policy documents a forbidden rule in order to reject it.
forbidden = {
    "ACWR prescriptive safe-zone": r"ACWR.*0\.8\s*[–-]\s*1\.3|0\.8\s*[–-]\s*1\.3.*ACWR",
    "fixed novice RIR +2 correction": r"novice.*RIR.*\+2|RIR.*\+2.*novice",
    "universal sex calorie floors": r"1200\s*kcal.*women|1500\s*kcal.*men",
    "beta blocker HR universally invalid": r"beta[- ]?blockers?.*HR.*invalid",
}
NEGATION = re.compile(r"\b(do not|don't|not universal|not a universal|removed|reject|must not|no mandatory|not enforce|does not|do not mean)\b", re.I)
scan_files=list(SKILLS.glob("*/SKILL.md"))+[ROOT/"RUNTIME_SAFETY_PROMPT.md"]
for p in scan_files:
    text=p.read_text(errors="ignore")
    paragraphs=re.split(r"\n\s*\n", text)
    for label,pat in forbidden.items():
        for paragraph in paragraphs:
            plain=paragraph.replace("*", "")
            if re.search(pat, plain, re.I|re.S) and not NEGATION.search(plain):
                errors.append(f"{p.relative_to(ROOT)}: forbidden regression: {label}")
                break

manifest=json.loads((ROOT/"manifest.json").read_text()) if (ROOT/"manifest.json").exists() else {}
if manifest.get("agent_count") != len(agent_defs): errors.append(f"manifest agent_count={manifest.get('agent_count')} actual={len(agent_defs)}")
if manifest.get("skill_count") != len(skill_names): errors.append(f"manifest skill_count={manifest.get('skill_count')} actual={len(skill_names)}")

if errors:
    print("STATIC GATES: FAIL")
    for e in errors: print(" -",e)
    raise SystemExit(1)
print(f"STATIC GATES: PASS — {len(agent_defs)} agents, {len(skill_names)} skills, runtime JSON valid, tool topology valid")
