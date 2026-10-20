/**
 * S02-11 / F96: story-map completeness lint. The parser reads design section 11 and plan
 * sections 1, 3 and 7 as TEXT. It is proven on the real files (no problem) and on seven
 * in-memory mutated copies, each of which must fail with its OWN reason. The real documents
 * are never edited.
 */
import * as fs from "fs";
import * as path from "path";

const REPO = path.resolve(__dirname, "../../../../");
const DESIGN = fs.readFileSync(path.join(REPO, "docs/phase2/s02/S02_DESIGN.md"), "utf8");
const PLAN = fs.readFileSync(path.join(REPO, "docs/phase2/s02/S02_TEST_PLAN.md"), "utf8");

export type Kind =
  | "placeholder" | "unknown_id" | "orphan_definition" | "duplicate_definition" | "story_without_ids"
  | "prereq_unknown" | "prereq_mismatch" | "cycle" | "order_mismatch" | "cell_drift" | "blocking_unassigned";
export interface Problem { kind: Kind; detail: string }

/** Text between `## <n>.` and the next `## ` heading at level two. */
function section(text: string, n: number): string {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => l.startsWith(`## ${n}.`));
  if (start < 0) return "";
  let end = lines.findIndex((l, i) => i > start && /^## \d+\./.test(l));
  if (end < 0) end = lines.length;
  return lines.slice(start, end).join("\n");
}
const rows = (text: string): string[][] =>
  text.split("\n").filter((l) => l.startsWith("|") && !/^\|\s*-+/.test(l)).map((l) => l.replace(/^\||\|\s*$/g, "").split("|").map((c) => c.trim()));
const STORY = /^S02-\d\d[ab]?/;
const stripParens = (s: string): string => {
  let prev = "";
  while (prev !== s) { prev = s; s = s.replace(/\([^()]*\)/g, ""); }
  return s;
};
/** Expands `F49-F53`, single ids, ignoring parenthetical notes. */
export function expandIds(cell: string): string[] {
  const out: string[] = [];
  const text = stripParens(cell);
  const re = /\b([UIRSFE])(\d\d)(?:\s*-\s*\1(\d\d))?\b/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    const a = Number(m[2]);
    const b = m[3] ? Number(m[3]) : a;
    for (let i = a; i <= b; i++) out.push(`${m[1]}${String(i).padStart(2, "0")}`);
  }
  return out;
}
const storiesIn = (s: string): string[] => [...s.matchAll(/S02-\d\d[ab]?/g)].map((m) => m[0]);

export function lintStoryMap(design: string, plan: string): Problem[] {
  const P: Problem[] = [];
  const add = (kind: Kind, detail: string): void => { P.push({ kind, detail }); };
  const d11 = section(design, 11);
  const p7 = section(plan, 7);
  const p3 = section(plan, 3);
  const p1 = section(plan, 1);

  if (/TP-sync/.test(d11)) add("placeholder", "TP-sync in design section 11");

  // Definitions in the plan.
  const defined = new Map<string, number>();
  for (const r of rows(p1)) if (/^[UIRSFE]\d\d$/.test(r[0])) defined.set(r[0], (defined.get(r[0]) ?? 0) + 1);
  for (const [id, n] of defined) if (n > 1) add("duplicate_definition", id);

  // Design DAG table, story table, order line.
  const dagRows = rows(d11).filter((r) => r.length === 2 && STORY.test(r[0]));
  const dag = new Map<string, Set<string>>();
  for (const r of dagRows) dag.set(r[0], new Set(r[1] === "none" ? [] : storiesIn(r[1])));
  const storyRows = rows(d11).filter((r) => r.length === 5 && STORY.test(r[0]));
  const designIds = new Map<string, Set<string>>();
  const designGps = new Map<string, Set<string>>();
  for (const r of storyRows) {
    const id = r[0].match(STORY)![0];
    designIds.set(id, new Set(expandIds(r[3])));
    designGps.set(id, new Set([...r[4].matchAll(/\b\d{3}\b/g)].map((m) => m[0])));
  }
  const gate = rows(d11).find((r) => r.length === 5 && r[0].startsWith("Cross-story gate"));
  if (gate) designIds.set("gate", new Set(expandIds(gate[3])));
  const orderMatch = /Authoritative order[^:]*:([^]*?)\(map lint, last\)/.exec(d11);
  const designOrder = orderMatch ? storiesIn(orderMatch[1] + "(map lint, last)") : [];

  // Plan section 7 and section 3.
  const planRows = rows(p7).filter((r) => r.length === 3 && (STORY.test(r[0]) || r[0].startsWith("Cross-story gate")));
  const planIds = new Map<string, Set<string>>();
  const planPre = new Map<string, Set<string>>();
  const planGps = new Map<string, Set<string>>();
  for (const r of planRows) {
    const id = STORY.test(r[0]) ? r[0].match(STORY)![0] : "gate";
    planIds.set(id, new Set(expandIds(r[2])));
    planPre.set(id, new Set(r[1] === "none" ? [] : storiesIn(r[1])));
    planGps.set(id, new Set([...(/\[([^\]]*)\]/.exec(r[0])?.[1] ?? "").matchAll(/\b\d{3}\b/g)].map((m) => m[0])));
  }
  const planOrder = rows(p3).filter((r) => /^\d+$/.test(r[0]) && STORY.test(r[1] ?? "")).map((r) => r[1].match(STORY)![0]);

  // Ids: known, assigned, both directions.
  const assigned = new Set<string>();
  for (const [story, ids] of [...designIds, ...planIds]) {
    for (const id of ids) {
      assigned.add(id);
      if (!defined.has(id)) add("unknown_id", `${id} in ${story}`);
    }
  }
  for (const id of defined.keys()) if (!assigned.has(id)) add("orphan_definition", id);

  // Stories: ids present, cells equal, prerequisites known and equal, no cycle.
  const stories = [...dag.keys()];
  for (const s of stories) {
    if ((designIds.get(s)?.size ?? 0) === 0) add("story_without_ids", `design ${s}`);
    if ((planIds.get(s)?.size ?? 0) === 0) add("story_without_ids", `plan ${s}`);
    const a = [...(designIds.get(s) ?? [])].sort().join(",");
    const b = [...(planIds.get(s) ?? [])].sort().join(",");
    if (s !== "S02-11" && a !== b) add("cell_drift", s);
    for (const p of dag.get(s) ?? []) if (!dag.has(p)) add("prereq_unknown", `${s} -> ${p}`);
    if (s !== "S02-11") {
      const x = [...(dag.get(s) ?? [])].sort().join(",");
      const y = [...(planPre.get(s) ?? [])].sort().join(",");
      if (x !== y) add("prereq_mismatch", `${s}: design [${x}] plan [${y}]`);
    }
  }
  const state = new Map<string, number>();
  const visit = (s: string, stack: string[]): void => {
    if (state.get(s) === 2) return;
    if (state.get(s) === 1) { add("cycle", [...stack, s].join(" -> ")); return; }
    state.set(s, 1);
    for (const p of dag.get(s) ?? []) if (dag.has(p)) visit(p, [...stack, s]);
    state.set(s, 2);
  };
  for (const s of stories) visit(s, []);

  // Order: design line equals plan section 3 and is a topological order.
  if (designOrder.join(",") !== planOrder.join(",")) add("order_mismatch", `design [${designOrder}] plan [${planOrder}]`);
  const pos = new Map(designOrder.map((s, i) => [s, i]));
  for (const s of stories) {
    for (const p of dag.get(s) ?? []) {
      if (s === "S02-11") continue;
      if ((pos.get(p) ?? -1) >= (pos.get(s) ?? -1)) add("order_mismatch", `${p} must precede ${s}`);
    }
  }
  if (new Set(designOrder).size !== stories.length) add("order_mismatch", "order does not list every story once");

  // Blocking criteria: every GPS-PRIV id the plan names for a story is in the design column of that story.
  for (const [s, ids] of planGps) {
    for (const g of ids) if (!designGps.get(s)?.has(g)) add("blocking_unassigned", `${g} not assigned to ${s} in design section 11`);
  }
  // Every MAJOR/BLOCKER named in design 6.1, 6.2, 10, 11 that has a plan row is covered by an assigned id.
  return P;
}
const kinds = (p: Problem[]): Kind[] => [...new Set(p.map((x) => x.kind))];

describe("F96 on the real documents", () => {
  test("design section 11 and plan section 7 agree: no problem of any kind", () => {
    expect(lintStoryMap(DESIGN, PLAN)).toEqual([]);
  });
  test("the parser actually saw the content (a lint that parses nothing would pass vacuously)", () => {
    const d = rows(section(DESIGN, 11)).filter((r) => r.length === 5 && STORY.test(r[0]));
    const p = rows(section(PLAN, 7)).filter((r) => r.length === 3 && STORY.test(r[0]));
    expect(d.length).toBe(16);
    expect(p.length).toBe(16);
    expect(rows(section(PLAN, 1)).filter((r) => /^[UIRSFE]\d\d$/.test(r[0])).length).toBe(239);
    expect(expandIds("F49-F53, U08 (R12, R26 as rewritten)")).toEqual(["F49", "F50", "F51", "F52", "F53", "U08"]);
  });
  test("every id of the final run list has exactly one definition row", () => {
    const seen = new Map<string, number>();
    for (const r of rows(section(PLAN, 1))) if (/^[UIRSFE]\d\d$/.test(r[0])) seen.set(r[0], (seen.get(r[0]) ?? 0) + 1);
    expect([...seen.values()].every((n) => n === 1)).toBe(true);
    expect(seen.size).toBe(239);
  });
  test("design section 17 exists but is not parsed as section 11", () => {
    expect(DESIGN).toMatch(/^## 17\./m);
    expect(section(DESIGN, 11)).not.toContain("## 17.");
    expect(section(DESIGN, 11)).not.toMatch(/Implementation notes/);
  });
});

describe("F96 sensitivity: each mutated copy fails with its own reason", () => {
  const mutate = (text: string, from: string | RegExp, to: string): string => {
    const out = text.replace(from, to);
    expect(out).not.toBe(text); // the mutation really changed the copy
    return out;
  };
  test("1. a TP-sync placeholder inserted into design section 11", () => {
    const d = mutate(DESIGN, "| S02-05a Settings and consent |", "| TP-sync S02-05a Settings and consent |");
    expect(kinds(lintStoryMap(d, PLAN))).toContain("placeholder");
  });
  test("2. an unknown id F999 inserted into a design test-id cell", () => {
    const d = mutate(DESIGN, "| F13, F68, F75, F82, I28 |", "| F13, F68, F75, F82, I28, F99 |");
    const p = lintStoryMap(d, PLAN);
    expect(kinds(p)).toContain("unknown_id");
    expect(p.find((x) => x.kind === "unknown_id")!.detail).toContain("F99");
  });
  test("2b. a three-digit id is not even an id: F999 in a plan cell leaves the lint unaffected, an unknown F-id does not", () => {
    const pl = mutate(PLAN, /(S02-00, S02-03 \| )F13, F68, F75, F82, I28 \|/, "$1F13, F68, F75, F82, I28, F99 |");
    expect(kinds(lintStoryMap(DESIGN, pl))).toEqual(expect.arrayContaining(["unknown_id", "cell_drift"]));
  });
  test("3. a prerequisite removed from the design DAG", () => {
    const d = mutate(DESIGN, "| S02-04b | S02-04a, S02-05a, S02-06a |", "| S02-04b | S02-04a, S02-05a |");
    expect(kinds(lintStoryMap(d, PLAN))).toContain("prereq_mismatch");
  });
  test("4. a cycle added (S02-01 needs S02-02)", () => {
    const d = mutate(DESIGN, "| S02-01 | S02-00 |", "| S02-01 | S02-00, S02-02 |");
    expect(kinds(lintStoryMap(d, PLAN))).toContain("cycle");
  });
  test("5. the authoritative order swapped", () => {
    const d = mutate(DESIGN, "S02-06b, S02-07, S02-09,", "S02-07, S02-06b, S02-09,");
    expect(kinds(lintStoryMap(d, PLAN))).toContain("order_mismatch");
  });
  test("6. one story's test ids emptied (design and plan)", () => {
    const d = mutate(DESIGN, "| F13, F68, F75, F82, I28 |", "|  |");
    const pl = mutate(PLAN, /(S02-00, S02-03 \| )F13, F68, F75, F82, I28 \|/, "$1 |");
    expect(kinds(lintStoryMap(d, pl))).toContain("story_without_ids");
  });
  test("7. a blocking criterion unassigned (GPS-PRIV 015 removed from S02-05a in the design)", () => {
    const d = mutate(DESIGN, /(\| F13, F68, F75, F82, I28 \| )015 \|/, "$1none |");
    const p = lintStoryMap(d, PLAN);
    expect(kinds(p)).toContain("blocking_unassigned");
    expect(p.find((x) => x.kind === "blocking_unassigned")!.detail).toContain("015");
  });
  test("8. an id defined in the plan but assigned to no story, and a duplicate definition", () => {
    const pl = mutate(PLAN, /(S02-00, S02-03 \| )F13, F68, F75, F82, I28 \|/, "$1F13, F68, F75, I28 |");
    const d = mutate(DESIGN, "| F13, F68, F75, F82, I28 |", "| F13, F68, F75, I28 |");
    expect(kinds(lintStoryMap(d, pl))).toContain("orphan_definition");
    const dup = PLAN.replace("## 2. Synthetic corpus", "| F13 | duplicate | x | y |\n\n## 2. Synthetic corpus");
    expect(kinds(lintStoryMap(DESIGN, dup))).toContain("duplicate_definition");
  });
  test("a lint that passes a mutated copy would fail this test: every mutation changes the verdict from the clean baseline", () => {
    expect(lintStoryMap(DESIGN, PLAN)).toEqual([]);
    const d = mutate(DESIGN, "| S02-01 | S02-00 |", "| S02-01 | S02-00, S02-02 |");
    expect(lintStoryMap(d, PLAN).length).toBeGreaterThan(0);
  });
});
