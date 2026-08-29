/**
 * `aiExerciseGeneration` -- G1's fourth and final callable, replicating the established
 * pattern for `AiExerciseGenerator` (`mobile/lib/features/ai_coach/ai_exercise_generator.dart`):
 * fills a machine's exercise card with AI-generated content when the curated catalog has
 * nothing for it.
 *
 * The one AI surface of the four that had genuine caller-controlled free text in its prompt --
 * the mobile client built the prompt itself and interpolated `machineName`, a string the caller
 * supplied directly. This callable accepts ONLY `equipmentId` + `languageCode`; the canonical
 * machine name is resolved server-side from a ported id->name map, never trusted as raw text
 * from the client. That closes the injection surface entirely, the same direction slice 3 took
 * for `languageCode` (a two-value enum) applied here to the machine name (a lookup key).
 *
 * Response parsing (`AiExerciseGenerator.parseResponse`, muscle-vocabulary filtering) stays
 * entirely client-side, unchanged -- matching the established pattern for all three prior
 * callables: this file does the model call and returns the model's raw JSON text unchanged.
 */
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { AI_METERED } from "./scaling";
import {
  QUOTAS,
  enforceAiGatewayEnabled,
  enforceDailyQuota,
  enforceNonAnonymousForAi,
  noteAppCheck,
  quotaFor,
} from "./abuse_guard";
import { generate } from "./ai_gateway";

/** Matches every other callable's `signInProvider` extraction. */
function signInProvider(request: CallableRequest): string | undefined {
  return request.auth?.token?.firebase?.sign_in_provider;
}

/**
 * id -> English display name, ported from `mobile/assets/data/equipment.json` (69 entries) via
 * a one-off generator script reading the live asset -- not hand-typed, to avoid transcription
 * error (a first draft of this file, written from memory, got several ids wrong, e.g.
 * `leg_extension` vs a guessed `leg_extension_machine`; caught before commit by regenerating
 * from the asset rather than trusting the draft).
 *
 * A real `Map`, not an object literal: `Map.get()` has no prototype chain to walk, closing the
 * class of bypass GPT-PM's slice-3 review found on `languageCode in LANGUAGE_NAMES` (an object
 * literal's `in` check resolves `"constructor"`/`"toString"`/`"__proto__"` to real
 * `Object.prototype` members). Guarded by a parity test
 * (`__tests__/ai_exercise_generation.test.ts`) that reads the live asset at test time and fails
 * the moment this list drifts from it -- CANONICAL_MACHINES in `ai_equipment_recognition.ts`
 * documents exactly this drift as an accepted risk because it has no such guard; this map does.
 */
export const EQUIPMENT_NAMES_EN = new Map<string, string>([
  ["treadmill", "Treadmill"],
  ["rowing_machine", "Rowing machine"],
  ["squat_rack", "Squat rack"],
  ["bench_press", "Weight bench"],
  ["cable_machine", "Cable machine"],
  ["leg_press", "Leg press"],
  ["lat_pulldown", "Lat pulldown"],
  ["barbell", "Barbell"],
  ["dumbbell", "Dumbbells"],
  ["kettlebell", "Kettlebell"],
  ["elliptical", "Elliptical trainer"],
  ["exercise_bike", "Exercise bike"],
  ["recumbent_bike", "Recumbent bike"],
  ["stair_climber", "Stair climber"],
  ["air_bike", "Air bike"],
  ["ski_erg", "Ski erg"],
  ["smith_machine", "Smith machine"],
  ["hack_squat_machine", "Hack squat machine"],
  ["leg_extension", "Leg extension machine"],
  ["leg_curl", "Leg curl machine"],
  ["hip_abductor_adductor", "Hip abductor / adductor machine"],
  ["glute_kickback_machine", "Glute kickback machine"],
  ["calf_raise_machine", "Calf raise machine"],
  ["chest_press_machine", "Chest press machine"],
  ["pec_deck", "Pec deck / fly machine"],
  ["shoulder_press_machine", "Shoulder press machine"],
  ["seated_row_machine", "Seated row machine"],
  ["t_bar_row", "T-bar row"],
  ["assisted_pullup_machine", "Assisted pull-up machine"],
  ["pullup_bar", "Pull-up bar"],
  ["dip_station", "Dip station"],
  ["preacher_curl_bench", "Preacher curl bench"],
  ["bicep_curl_machine", "Biceps curl machine"],
  ["tricep_extension_machine", "Triceps extension machine"],
  ["ab_crunch_machine", "Ab crunch machine"],
  ["rotary_torso_machine", "Rotary torso machine"],
  ["back_extension", "Back extension bench"],
  ["captains_chair", "Captain's chair"],
  ["adjustable_bench", "Bench (flat / adjustable)"],
  ["ez_curl_bar", "EZ curl bar"],
  ["weight_plates", "Weight plates"],
  ["resistance_bands", "Resistance bands"],
  ["trx", "Suspension trainer (TRX)"],
  ["medicine_ball", "Medicine ball"],
  ["battle_ropes", "Battle ropes"],
  ["plyo_box", "Plyo box"],
  ["punching_bag", "Punching bag"],
  ["foam_roller", "Foam roller"],
  ["stability_ball", "Stability ball"],
  ["skipping_rope", "Skipping rope"],
  ["ab_wheel", "Ab wheel"],
  ["parallettes", "Parallettes"],
  ["seated_dip_machine", "Seated dip machine"],
  ["multi_hip_machine", "Multi hip machine"],
  ["lateral_raise_machine", "Lateral raise machine"],
  ["sissy_squat_machine", "Sissy squat machine"],
  ["agility_ladder", "Agility ladder"],
  ["mini_trampoline", "Mini trampoline"],
  ["balance_board", "Balance board"],
  ["yoga_blocks", "Yoga blocks"],
  ["weighted_sled", "Weighted sled"],
  ["ab_mat", "Ab mat"],
  ["bosu_ball", "Bosu ball"],
  ["sliding_disc", "Sliding discs"],
  ["sandbag", "Sandbag"],
  ["gymnastic_rings", "Gymnastic rings"],
  ["tyre", "Tyre"],
  ["vertical_pole", "Vertical pole"],
  ["outdoor_air_walker", "Outdoor air walker"],
]);

/**
 * id -> Russian display name, ported from `mobile/assets/data/equipment.ru.json` (same 69-id
 * set as EN -- guarded by its own parity test) via the same generator script, for the same
 * transcription-safety reason. Genuinely translated text, not a transliteration -- verified
 * against the live asset before this port (e.g. "treadmill" -> "Беговая дорожка", not
 * "Тредмилл"), so resolving RU requests to the EN name would have been a real behavior change
 * for Russian users, not a cosmetic one.
 */
export const EQUIPMENT_NAMES_RU = new Map<string, string>([
  ["treadmill", "Беговая дорожка"],
  ["rowing_machine", "Гребной тренажёр"],
  ["squat_rack", "Силовая рама"],
  ["bench_press", "Жим лёжа (стойка)"],
  ["cable_machine", "Блочный тренажёр (кроссовер)"],
  ["leg_press", "Жим ногами"],
  ["lat_pulldown", "Верхняя тяга"],
  ["barbell", "Штанга"],
  ["dumbbell", "Гантели"],
  ["kettlebell", "Гиря"],
  ["elliptical", "Эллиптический тренажёр"],
  ["exercise_bike", "Велотренажёр"],
  ["recumbent_bike", "Горизонтальный велотренажёр"],
  ["stair_climber", "Степпер / лестница"],
  ["air_bike", "Аэробайк"],
  ["ski_erg", "Лыжный тренажёр"],
  ["smith_machine", "Машина Смита"],
  ["hack_squat_machine", "Гакк-машина"],
  ["leg_extension", "Разгибание ног"],
  ["leg_curl", "Сгибание ног"],
  ["hip_abductor_adductor", "Сведение / разведение ног"],
  ["glute_kickback_machine", "Отведение ноги назад (ягодичные)"],
  ["calf_raise_machine", "Подъёмы на носки (тренажёр)"],
  ["chest_press_machine", "Жим от груди (тренажёр)"],
  ["pec_deck", "Бабочка (пек-дек)"],
  ["shoulder_press_machine", "Жим на плечи (тренажёр)"],
  ["seated_row_machine", "Горизонтальная тяга"],
  ["t_bar_row", "Т-гриф"],
  ["assisted_pullup_machine", "Гравитрон"],
  ["pullup_bar", "Турник"],
  ["dip_station", "Брусья"],
  ["preacher_curl_bench", "Скамья Скотта"],
  ["bicep_curl_machine", "Сгибание рук (тренажёр)"],
  ["tricep_extension_machine", "Разгибание рук (тренажёр)"],
  ["ab_crunch_machine", "Тренажёр для пресса"],
  ["rotary_torso_machine", "Ротация корпуса (тренажёр)"],
  ["back_extension", "Гиперэкстензия"],
  ["captains_chair", "Стойка для подъёма ног"],
  ["adjustable_bench", "Скамья (прямая / регулируемая)"],
  ["ez_curl_bar", "EZ-гриф"],
  ["weight_plates", "Диски"],
  ["resistance_bands", "Резиновые ленты"],
  ["trx", "Петли TRX"],
  ["medicine_ball", "Медбол"],
  ["battle_ropes", "Канаты"],
  ["plyo_box", "Плиобокс"],
  ["punching_bag", "Боксёрская груша"],
  ["foam_roller", "Массажный ролл"],
  ["stability_ball", "Фитбол"],
  ["skipping_rope", "Скакалка"],
  ["ab_wheel", "Ролик для пресса"],
  ["parallettes", "Брусья-паралетки"],
  ["seated_dip_machine", "Тренажёр для отжиманий (сидя)"],
  ["multi_hip_machine", "Мульти-хип машина"],
  ["lateral_raise_machine", "Тренажёр для разведения рук (плечи)"],
  ["sissy_squat_machine", "Тренажёр для сисси-приседа"],
  ["agility_ladder", "Координационная лестница"],
  ["mini_trampoline", "Мини-батут"],
  ["balance_board", "Балансборд"],
  ["yoga_blocks", "Йога-блоки"],
  ["weighted_sled", "Сани с отягощением"],
  ["ab_mat", "Валик для пресса"],
  ["bosu_ball", "Босу (полусфера)"],
  ["sliding_disc", "Слайдеры (диски для скольжения)"],
  ["sandbag", "Сэндбэг"],
  ["gymnastic_rings", "Гимнастические кольца"],
  ["tyre", "Покрышка"],
  ["vertical_pole", "Вертикальный столб"],
  ["outdoor_air_walker", "Уличный аэрошагатель"],
]);

/** Resolves the canonical machine name for an `equipmentId`, in the requested language.
 * `Map.get()` on a real `Map` -- no prototype chain, no coercion, no fallback lookup key.
 * Falls back to the EN name if an id is somehow present in EN but missing from RU (defensive;
 * the parity tests make this unreachable in practice since both maps are asset-verified to
 * share the exact same id set). */
function resolveMachineName(equipmentId: unknown, languageCode: string): string {
  if (typeof equipmentId !== "string") {
    throw new HttpsError("invalid-argument", "equipmentId is required.");
  }
  const table = languageCode === "ru" ? EQUIPMENT_NAMES_RU : EQUIPMENT_NAMES_EN;
  const name = table.get(equipmentId) ?? EQUIPMENT_NAMES_EN.get(equipmentId);
  if (name === undefined) {
    throw new HttpsError("invalid-argument", "equipmentId is not a recognised machine.");
  }
  return name;
}

/** The only two languages the app ships, resolved by direct equality -- same pattern as
 * `aiMachineDescription`'s already-reviewed `resolveLanguageName`. */
function resolveLanguageCode(languageCode: unknown): string {
  if (languageCode === "ru" || languageCode === "en") return languageCode;
  throw new HttpsError("invalid-argument", 'languageCode must be exactly "ru" or "en".');
}

/** Exact copy of Dart's `kMuscleVocab` -- guarded by a cross-tree parity test that reads the
 * real Dart source at test time, not a second hand-typed copy that could drift silently. */
export const MUSCLE_VOCAB: readonly string[] = [
  "adductors", "back", "biceps", "calves", "chest", "core", "forearms",
  "glutes", "hamstrings", "lats", "lower_back", "quads", "shoulders",
  "traps", "triceps",
] as const;

interface ExerciseGenerationInput {
  machineName: string;
  language: string;
}

function parseInput(data: unknown): ExerciseGenerationInput {
  const d = (data ?? {}) as Record<string, unknown>;
  // languageCode validated first (cheap, no lookup) -- same ordering discipline as
  // aiMachineDescription's parseInput, cheap checks before anything that does real work.
  const language = resolveLanguageCode(d.languageCode);
  const machineName = resolveMachineName(d.equipmentId, language);
  return { machineName, language: language === "ru" ? "Russian" : "English" };
}

/** Exact port of `AiExerciseGenerator._buildPrompt`, with `machineName` already resolved
 * server-side from `equipmentId` -- never the caller's raw text. */
function buildPrompt(machineName: string, language: string): string {
  return `Generate 3 to 4 distinct exercises performed on: "${machineName}".
Write all text (title, steps) in ${language}.

Answer with a JSON array only, each item shaped exactly like:
{"title": "...", "steps": ["step 1", "step 2", "step 3"],
 "muscles": ["<from vocabulary>"], "primaryMuscles": ["<from vocabulary>"],
 "difficulty": "beginner|intermediate|advanced", "durationMinutes": <int>}

Muscle vocabulary (use ONLY these, lowercase, exactly as spelled):
${MUSCLE_VOCAB.join(", ")}

Steps must be concrete and safe (setup, execution, breathing where it
matters). Do not invent a feature this machine does not have. 3-5 steps per
exercise. durationMinutes between 5 and 12.`;
}

export const aiExerciseGeneration = onCall(AI_METERED, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to generate exercises.");
  }
  noteAppCheck(request, "aiExerciseGeneration");
  enforceNonAnonymousForAi(signInProvider(request));
  await enforceAiGatewayEnabled("aiExerciseGeneration");
  const input = parseInput(request.data);

  await enforceDailyQuota(
    request.auth.uid,
    "aiExerciseGeneration",
    quotaFor(QUOTAS.aiExerciseGeneration, signInProvider(request)),
  );

  // Matches `AiExerciseGenerator._askCloud`'s own generationConfig exactly: JSON mode,
  // temperature 0.4 (higher than the other three callables' 0 -- exercise generation wants some
  // variety across calls, not a single deterministic answer, matching the mobile source this
  // ports), thinking disabled.
  //
  // `timeoutMs: 25_000` bounds only this call (the model itself), matching
  // `AiExerciseGenerator`'s own existing 25s budget for the network leg -- deliberately NOT the
  // mobile client's end-to-end deadline. The mobile side gains its own larger outer deadline
  // (35s) covering the whole httpsCallable round trip (auth, `parseInput`, quota transaction,
  // network), for the same client/server timeout-race reason documented on the other three
  // callables: a client timer equal to this budget could discard a legitimate, already-paid
  // answer that lands after the model finishes but before the callable's own transport overhead
  // is accounted for.
  const text = await generate({
    operation: "aiExerciseGeneration",
    prompt: buildPrompt(input.machineName, input.language),
    jsonResponse: true,
    temperature: 0.4,
    disableThinking: true,
    timeoutMs: 25_000,
    // Up to 4 exercises, each with a title, 3-5 steps, two muscle arrays, a difficulty enum and
    // a duration -- more fields per item than aiMachineDescription's single-machine summary, and
    // up to 4 items rather than 1. 1024 gives real headroom while staying a provider-enforced
    // ceiling per `ai_gateway.ts`'s `GenerateOptions.maxOutputTokens` doc.
    maxOutputTokens: 1024,
  });

  return { text };
});
