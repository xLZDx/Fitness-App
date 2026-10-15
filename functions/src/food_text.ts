/**
 * Text hygiene for the food callables (design s7.9, D-66).
 *
 * Two different jobs:
 *
 *  - `findForbiddenPromptChar` guards what a CALLER may put into the fixed,
 *    server-owned prompt (`note`, describe `text`, a search `query`): control
 *    characters, quotes and backticks are refused outright, the same idea as
 *    `ai_coach_advice.ts`'s `FORBIDDEN_SUBJECT_NAME_CHARS`. The residual
 *    prompt-injection risk is stated in the callables, not claimed away.
 *  - `sanitiseDisplayText` cleans what comes BACK from an untrusted source (a
 *    model-authored meal name or item name, OCR label text, an upstream product
 *    name) before it can be shown or stored: URL, e-mail, phone and markup
 *    patterns removed, a restricted character set, whitespace collapsed, a hard
 *    length cap. It never throws and never returns markup.
 */

/** Control characters, double quotes (straight and typographic) and backticks. A bare apostrophe
 * stays legal ("chef's salad"): the prompt wraps caller text in double quotes only. */
// eslint-disable-next-line no-control-regex
const FORBIDDEN_PROMPT_CHARS = /[\u0000-\u001f\u007f-\u009f"`“”«»]/u;

/** The first forbidden character in `text`, or `null` when the text is clean. */
export function findForbiddenPromptChar(text: string): string | null {
  const m = FORBIDDEN_PROMPT_CHARS.exec(text);
  return m ? m[0] : null;
}

export const DISPLAY_TEXT_MAX = 80;

const MARKUP = /<[^>]*>?/g;
const URL_LIKE = /\b(?:[a-z][a-z0-9+.-]*:\/\/|www\.)\S*/gi;
const EMAIL = /\S+@\S+\.\S+/g;
// A bare host/path such as `example.com/free` (a dot-separated domain followed by a slash or a TLD).
const BARE_DOMAIN = /\b[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)*\.(?:com|net|org|ru|io|info|biz|xyz|me|co|app|dev|ly|to|tk|top)\b\S*/giu;
// Seven or more digits possibly separated by spaces, dots, dashes or brackets: a phone number.
const PHONE = /\+?\d[\d\s().-]{5,}\d/g;
// Anything outside letters of any script, digits, space and `-.,()'%/` is dropped.
const DISALLOWED = /[^\p{L}\p{N} \-.,()'%/]/gu;

/**
 * Cleans untrusted display text. Order matters: markup and URL-like patterns
 * go first (they contain characters the charset filter would otherwise leave
 * as a harmless-looking stub), then the charset filter, then whitespace and the
 * cap. The cap counts code points and never splits a surrogate pair.
 */
export function sanitiseDisplayText(value: unknown, max: number = DISPLAY_TEXT_MAX): string {
  if (typeof value !== "string") return "";
  let s = value.normalize("NFKC");
  s = s.replace(MARKUP, " ");
  s = s.replace(URL_LIKE, " ");
  s = s.replace(EMAIL, " ");
  s = s.replace(BARE_DOMAIN, " ");
  s = s.replace(PHONE, " ");
  s = s.replace(DISALLOWED, " ");
  s = s.replace(/\s+/g, " ").trim();
  // Leading punctuation left over from a removed pattern is noise, not a name.
  s = s.replace(/^[\s.,/%()-]+/, "").trim();
  const points = Array.from(s);
  if (points.length > max) s = points.slice(0, max).join("").trim();
  return s;
}
