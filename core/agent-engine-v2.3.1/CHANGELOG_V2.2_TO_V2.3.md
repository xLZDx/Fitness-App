# v2.2 -> v2.3 integration changelog

No v2.2 clinical/prescription rule was removed or weakened.

Added:
- 1 Skill: `fitness-recommendation-engine-contract`
- 3 machine-readable policies:
  - `fitness-agent-engine-ownership.json`
  - `fitness-recommendation-gates.json`
  - `fitness-engine-real-repo-map.json`
- preloaded the new Skill into 8 governance agents:
  - fitness-recommendation-orchestrator
  - recommendation-engine-architect
  - recommendation-adversary
  - clinical-safety-gate
  - evidence-guideline-reviewer
  - exercise-ontology-curator
  - fitness-data-scientist
  - regulatory-compliance-reviewer
- bound agent work to actual private-repo audit HEAD `5b7c9acc7acdd00db502e1934afd2c75983eaeb9`
- defined agent ownership, vetoes, gate reviews and structured artifacts.

Agent count remains 29.
Skill count becomes 7.

The G0 remote audit remains read-only; no Fitness-App repository file was modified by
building this package.
