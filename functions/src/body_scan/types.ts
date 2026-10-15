/**
 * Shared vocabulary of the Body Scan server path (design s5.1, s7, s8, s12.7).
 *
 * Pure types and closed lists only: no I/O, no Firebase imports, so every other
 * module in this folder (and the tests) can import it without side effects.
 */

/** The three capture poses; also the object names under a scan's prefix. */
export const POSES = ["front", "side", "back"] as const;
export type Pose = (typeof POSES)[number];

export const SEXES_AT_BIRTH = ["female", "male", "unspecified"] as const;
export type SexAtBirth = (typeof SEXES_AT_BIRTH)[number];

export const CONFIDENCES = ["low", "medium", "high"] as const;
export type Confidence = (typeof CONFIDENCES)[number];

/**
 * The closed check-item list (design s12.7). It mirrors the client `CheckCode`
 * enum: free text from a provider is never stored or shown, only members of
 * this list, which keeps every code translatable and removes a prompt-injection
 * surface. `validateEstimate` rejects anything outside it.
 */
export const CHECK_CODES = [
  "provisionalEstimator",
  "manualCapture",
  "poorLighting",
  "partialBody",
  "looseClothing",
  "poseMismatch",
  "weightMissing",
  "weightStale",
  "weightJump",
  "wideRange",
  "estimateFarFromProfile",
  "largeJumpVsTrend",
  "blurUnavailable",
] as const;
export type CheckCode = (typeof CHECK_CODES)[number];

/** Lifecycle of `users/{uid}/body_scans/{scanId}.status` (design s5.1). */
export type ScanStatus = "pending" | "done" | "failed" | "cancelled";

/** `photosState` (design s5.1). */
export type PhotosState = "none" | "awaiting_upload" | "stored" | "deleted";

/** The server-validated subject snapshot an estimate is computed from. */
export interface Subject {
  sexAtBirth: SexAtBirth;
  /** DERIVED server-side from `profile.personal.birthYear` (D-58). */
  ageYears: number;
  heightCm: number;
  weightKg: number;
}

export interface EstimatorInput {
  scanId: string;
  subject: Subject;
  /** Present exactly when the provider `requiresPhotos` (always on this path). */
  photos?: Record<Pose, Buffer>;
  capture: { manualOverride: Record<Pose, boolean> };
}

export interface EstimatorOutput {
  bodyFatPct: number;
  rangeLowPct: number;
  rangeHighPct: number;
  confidence: Confidence;
  checkCodes: CheckCode[];
}

/**
 * A body-composition estimator provider (design s8). The stored `provider` map
 * and `estimate.modelId/modelVersion` make every historical number traceable to
 * the exact estimator that produced it.
 */
export interface BodyCompositionEstimator {
  /** Stable id, 1..64 characters (becomes `estimate.modelId`). */
  readonly id: string;
  /** Version string, 1..64 characters (becomes `estimate.modelVersion`). */
  readonly version: string;
  /** True => the UI shows the PROVISIONAL banner. */
  readonly provisional: boolean;
  readonly requiresPhotos: boolean;
  estimate(input: EstimatorInput): Promise<EstimatorOutput>;
}

/** The validated estimate block that is stored (immutable after `done`). */
export interface StoredEstimate extends EstimatorOutput {
  modelId: string;
  modelVersion: string;
}
