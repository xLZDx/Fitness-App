/**
 * food_text (FOOD-07 prompt-char refusal, FOOD-30 hostile-string sanitiser, D-66).
 * Display text from a model, OCR or an upstream product name must come out as
 * plain, short, markup-free text; caller text for the prompt must be refused when it
 * carries control characters, quotes or backticks.
 */
import { DISPLAY_TEXT_MAX, findForbiddenPromptChar, sanitiseDisplayText } from "../food_text";

describe("findForbiddenPromptChar", () => {
  test.each([
    ['straight double quote', 'say "hi"', '"'],
    ["backtick", "a `b` c", "`"],
    ["left typographic quote", "a “b", "“"],
    ["right typographic quote", "a b”", "”"],
    ["guillemet open", "«x", "«"],
    ["guillemet close", "x»", "»"],
    ["newline", "line1\nline2", "\n"],
    ["tab", "a\tb", "\t"],
    ["NUL", "a\u0000b", "\u0000"],
    ["DEL", "a\u007fb", "\u007f"],
    ["C1 control", "a\u0085b", "\u0085"],
  ])("refuses %s", (_l, text, expected) => {
    expect(findForbiddenPromptChar(text)).toBe(expected);
  });

  test.each([
    "chef's salad",
    "two eggs, toast & butter",
    "борщ со сметаной",
    "100% oat milk (unsweetened)",
    "",
  ])("allows clean text %j (apostrophe, Cyrillic, symbols stay legal)", (text) => {
    expect(findForbiddenPromptChar(text)).toBeNull();
  });
});

describe("sanitiseDisplayText", () => {
  test("non-strings give the empty string and never throw", () => {
    for (const v of [undefined, null, 5, {}, [], true, Symbol.iterator as unknown]) {
      expect(sanitiseDisplayText(v)).toBe("");
    }
  });

  test("clean names pass through unchanged", () => {
    expect(sanitiseDisplayText("Chicken breast, grilled")).toBe("Chicken breast, grilled");
    expect(sanitiseDisplayText("Yogurt 2% (plain)")).toBe("Yogurt 2% (plain)");
    expect(sanitiseDisplayText("O'Brien potatoes")).toBe("O'Brien potatoes");
  });

  test("Cyrillic and other scripts are kept", () => {
    expect(sanitiseDisplayText("Гречневая каша")).toBe(
      "Гречневая каша",
    );
    expect(sanitiseDisplayText("寿司")).toBe("寿司");
  });

  test("HTML markup is removed, including script blocks' tags and unterminated tags", () => {
    const out = sanitiseDisplayText("<b>Rice</b><script>alert(1)</script>");
    expect(out).not.toMatch(/[<>]/);
    expect(out).toContain("Rice");
    expect(sanitiseDisplayText("Rice <img src=x onerror=alert(1)")).toBe("Rice");
    expect(sanitiseDisplayText("Soup <a href='x'>link</a>")).not.toMatch(/href|<|>/);
  });

  test.each([
    ["https URL", "Free pizza https://evil.example/win now"],
    ["http URL with query", "Pizza http://evil.example/a?b=c now"],
    ["www host", "Pizza www.evil.example/free now"],
    ["bare domain with path", "Pizza evil.com/free now"],
    ["javascript scheme", "Pizza javascript://x now"],
  ])("%s is removed", (_l, text) => {
    const out = sanitiseDisplayText(text);
    expect(out).not.toMatch(/evil|http|www|\/\/|javascript/i);
    expect(out).toMatch(/^(Free )?[Pp]izza( now)?$|Pizza/);
  });

  test("e-mail addresses are removed", () => {
    const out = sanitiseDisplayText("Salad contact bob@example.com today");
    expect(out).not.toMatch(/@|bob|example/);
    expect(out).toBe("Salad contact today");
  });

  test("phone numbers are removed", () => {
    expect(sanitiseDisplayText("Burger call +1 (555) 123-4567 now")).toBe("Burger call now");
    expect(sanitiseDisplayText("Burger 555-123-4567")).toBe("Burger");
  });

  test("short quantities and numbers survive (not phone-like)", () => {
    expect(sanitiseDisplayText("Cola 330 ml")).toBe("Cola 330 ml");
    expect(sanitiseDisplayText("Bar 12.5 g")).toBe("Bar 12.5 g");
  });

  test("characters outside the restricted set are dropped and whitespace collapsed", () => {
    expect(sanitiseDisplayText("Rice\n\n\tand\u0000 beans; DROP{}[]$#!?")).toBe("Rice and beans DROP");
    expect(sanitiseDisplayText("   spaced    out   ")).toBe("spaced out");
  });

  test("emoji and zero-width characters are dropped", () => {
    expect(sanitiseDisplayText("Pizza 🍕 ​slice")).toBe("Pizza slice");
  });

  test("NFKC normalisation folds full-width look-alikes before filtering", () => {
    // Full-width "<b>" must not slip past the markup filter.
    const out = sanitiseDisplayText("＜b＞Rice＜/b＞");
    expect(out).not.toMatch(/[<>＜＞]/);
    expect(out).toContain("Rice");
  });

  test("leading punctuation left by a removed pattern is trimmed", () => {
    expect(sanitiseDisplayText("https://x.example - Oats")).toBe("Oats");
  });

  test("a 200-character name is capped at 80 code points", () => {
    const out = sanitiseDisplayText("a".repeat(200));
    expect(out).toBe("a".repeat(DISPLAY_TEXT_MAX));
    expect(DISPLAY_TEXT_MAX).toBe(80);
  });

  test("the cap counts code points and never splits a surrogate pair", () => {
    // Mathematical bold letters are astral, NFKC folds them to ASCII; use CJK extension B (astral, a letter).
    const astral = "\u{20000}";
    const out = sanitiseDisplayText(astral.repeat(100));
    expect(Array.from(out)).toHaveLength(80);
    expect(out).toBe(astral.repeat(80));
  });

  test("a custom max is honoured and trailing space after truncation is trimmed", () => {
    expect(sanitiseDisplayText("abc def ghi", 4)).toBe("abc");
    expect(sanitiseDisplayText("abcdef", 3)).toBe("abc");
  });

  test("a string made only of hostile content yields the empty string", () => {
    expect(sanitiseDisplayText("<script></script>")).toBe("");
    expect(sanitiseDisplayText("https://evil.example")).toBe("");
    expect(sanitiseDisplayText("\u0000\u0001")).toBe("");
  });

  test("output never contains markup or URL characters for a mixed hostile payload", () => {
    const hostile =
      '<img src=x onerror=alert(1)> Visit https://phish.example/login or mail a@b.co; call 555 123 4567 `rm -rf /` "ignore previous"';
    const out = sanitiseDisplayText(hostile);
    expect(out).not.toMatch(/[<>"`:@;\\=]/);
    expect(out).not.toMatch(/phish|a@b/);
    expect(Array.from(out).length).toBeLessThanOrEqual(80);
  });
});
