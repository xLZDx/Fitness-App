import { readFileSync } from "fs";
import { join } from "path";

const SOURCES = [
  "index.ts",
  "video_urls.ts",
  "account_export.ts",
  "ai_coach_advice.ts",
  "ai_equipment_recognition.ts",
  "ai_machine_description.ts",
  "ai_exercise_generation.ts",
];

export interface DiscoveredCallable {
  fn: string;
  file: string;
  text: string;
}

/**
 * Scans the real source files -- not a maintained list -- for every
 * `export const X = onCall` callable across the surfaces `noteAppCheck` is
 * expected to cover. Single source of truth for "what callables actually
 * exist": originally inline in `scaling.test.ts`'s "every callable reports
 * its attestation" test, extracted here (GPT-PM's review of
 * `functions/src/monitoring/alert_definitions.ts`'s App Check metric,
 * 2026-08-27) so a second test -- checking the metric's own bounding list
 * against this same inventory -- reuses one discovery mechanism instead of
 * maintaining a third independent copy of the file list/regex.
 */
export function discoverOnCallExports(): DiscoveredCallable[] {
  const sources = SOURCES.map((name) => ({
    name,
    text: readFileSync(join(__dirname, "..", name), "utf8"),
  }));
  return sources.flatMap(({ name, text }) =>
    [...text.matchAll(/export const (\w+) = onCall/g)].map((m) => ({
      fn: m[1],
      file: name,
      text,
    })),
  );
}
