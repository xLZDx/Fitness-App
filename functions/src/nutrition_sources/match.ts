/**
 * Match quality between an item and a database candidate (design s17.3):
 * token overlap between the item's query terms and the candidate's description.
 * Pure.
 */
import type { MatchQuality } from "../food_types";

/** Lower-case letter/digit tokens; a trailing plural `s` is dropped from words longer than 3 letters. */
export function tokens(text: string): string[] {
  const out: string[] = [];
  for (const raw of text.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? []) {
    if (raw.length < 2) continue;
    const t = raw.length > 3 && raw.endsWith("s") ? raw.slice(0, -1) : raw;
    if (!out.includes(t)) out.push(t);
  }
  return out;
}

const RANK: Record<MatchQuality, number> = { exact: 3, close: 2, weak: 1, none: 0 };
export const matchRank = (q: MatchQuality): number => RANK[q];

/**
 * `exact`: every query token is in the candidate and the candidate is not
 * mostly unrelated words (at least half its tokens matched); `close`: at least
 * two thirds of the query tokens matched; `weak`: at least a third; else `none`.
 * The best of the supplied query phrases wins.
 */
export function scoreMatch(queryPhrases: readonly string[], candidateName: string): MatchQuality {
  const cand = tokens(candidateName);
  if (cand.length === 0) return "none";
  let best: MatchQuality = "none";
  for (const phrase of queryPhrases) {
    const q = tokens(phrase);
    if (q.length === 0) continue;
    const matched = q.filter((t) => cand.includes(t)).length;
    const qCov = matched / q.length;
    const cCov = matched / cand.length;
    let quality: MatchQuality = "none";
    if (qCov === 1 && cCov >= 0.5) quality = "exact";
    else if (qCov >= 2 / 3) quality = "close";
    else if (qCov >= 1 / 3) quality = "weak";
    if (matchRank(quality) > matchRank(best)) best = quality;
  }
  return best;
}
