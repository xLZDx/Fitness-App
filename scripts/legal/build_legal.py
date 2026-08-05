# -*- coding: utf-8 -*-
"""Generate every rendering of the legal documents from `legal_text.py`.

Two outputs, one source:

  1. `mobile/lib/l10n/app_{en,ru}.arb` -- keys `legalPrivacyBody`,
     `legalTermsBody`, `legalLastUpdated`, consumed by the in-app pages.
  2. `public/{privacy,terms}.html` -- the public URLs Google Play requires as
     store-listing fields, deployed by `firebase deploy --only hosting`.

Run after ANY edit to `legal_text.py`:

    python scripts/legal/build_legal.py

then regenerate l10n (`flutter gen-l10n`, or just build -- it runs
automatically) and redeploy hosting. `--check` exits 1 if anything on disk is
stale, which is what CI would call.

Deliberately hand-rolled rather than pulled from a Markdown library: the markup
is four constructs (see `legal_text.py`), both renderers are ~30 lines, and a
dependency added to two static documents is a dependency to keep alive forever.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from legal_text import DOCS, STAMP, TITLES  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ARB_DIR = ROOT / "mobile" / "lib" / "l10n"
PUBLIC_DIR = ROOT / "public"

#: Written into the .arb files. The in-app pages read these.
ARB_KEYS = {
    "privacy": "legalPrivacyBody",
    "terms": "legalTermsBody",
}

_BOLD = re.compile(r"\*\*(.+?)\*\*", re.DOTALL)


def _inline(text: str) -> str:
    """Escape, then re-introduce the one inline construct: `**bold**`."""
    return _BOLD.sub(r"<strong>\1</strong>", html.escape(text))


def _html_of(body: str) -> str:
    """The Dart `_LegalBody` renderer's twin. Keep the two in step."""
    out: list[str] = []
    for block in body.strip().split("\n\n"):
        block = block.strip()
        if not block:
            continue
        if block.startswith("## "):
            out.append(f"<h2>{_inline(block[3:].strip())}</h2>")
        elif block.startswith("- "):
            items = "".join(
                f"<li>{_inline(line[2:].strip())}</li>"
                for line in block.split("\n")
                if line.strip().startswith("- ")
            )
            out.append(f"<ul>{items}</ul>")
        else:
            out.append(f"<p>{_inline(block)}</p>")
    return "\n      ".join(out)


_PAGE = """\
<!doctype html>
<html lang="{default_lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title_en} — Fitness App</title>
<style>
  :root {{ color-scheme: dark; }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 32px 20px 72px;
    font: 16px/1.65 -apple-system, "Segoe UI", Roboto, system-ui, sans-serif;
    color: #F1ECFF;
    background: linear-gradient(160deg, #16072E 0%, #050214 55%, #0B1233 100%);
    background-attachment: fixed;
  }}
  main {{ max-width: 720px; margin: 0 auto; }}
  .head {{
    display: flex; flex-wrap: wrap; gap: 12px;
    align-items: baseline; justify-content: space-between;
    padding-bottom: 18px; margin-bottom: 26px;
    border-bottom: 1px solid rgba(255,255,255,.12);
  }}
  h1 {{ margin: 0; font-size: 27px; letter-spacing: -.02em; }}
  h2 {{
    margin: 34px 0 10px; font-size: 18px; letter-spacing: -.01em;
    color: #C2F562;
  }}
  p, li {{ color: rgba(241,236,255,.78); }}
  p {{ margin: 0 0 14px; }}
  ul {{ margin: 0 0 14px; padding-left: 22px; }}
  li {{ margin-bottom: 8px; }}
  strong {{ color: #F1ECFF; }}
  .stamp {{ font-size: 13px; color: rgba(241,236,255,.42); }}
  .switch {{ display: flex; gap: 6px; }}
  .switch button {{
    font: inherit; font-size: 13px; cursor: pointer;
    padding: 5px 12px; border-radius: 999px;
    color: rgba(241,236,255,.62);
    background: rgba(255,255,255,.06);
    border: 1px solid rgba(255,255,255,.10);
  }}
  .switch button[aria-pressed="true"] {{
    color: #050214; background: #C2F562; border-color: transparent;
  }}
  [hidden] {{ display: none !important; }}
</style>
</head>
<body>
  <main>
    <div class="head">
      <h1 data-t data-en="{title_en}" data-ru="{title_ru}">{title_en}</h1>
      <div class="switch" role="group" aria-label="Language">
        <button type="button" data-lang="en" aria-pressed="true">English</button>
        <button type="button" data-lang="ru" aria-pressed="false">Русский</button>
      </div>
    </div>
    <p class="stamp" data-t
       data-en="{stamp_en}" data-ru="{stamp_ru}">{stamp_en}</p>

    <section data-body="en">
      {body_en}
    </section>
    <section data-body="ru" hidden>
      {body_ru}
    </section>
  </main>
<script>
  // No framework, no fetch: both languages ship in the document, so switching
  // is a `hidden` toggle that also works with JS disabled for whichever
  // language rendered server-side (English).
  (function () {{
    var buttons = document.querySelectorAll('.switch button');
    function apply(lang) {{
      document.documentElement.lang = lang;
      document.querySelectorAll('[data-body]').forEach(function (s) {{
        s.hidden = s.getAttribute('data-body') !== lang;
      }});
      document.querySelectorAll('[data-t]').forEach(function (el) {{
        el.textContent = el.getAttribute('data-' + lang);
      }});
      buttons.forEach(function (b) {{
        b.setAttribute('aria-pressed', String(b.dataset.lang === lang));
      }});
      try {{ localStorage.setItem('legal-lang', lang); }} catch (e) {{}}
    }}
    buttons.forEach(function (b) {{
      b.addEventListener('click', function () {{ apply(b.dataset.lang); }});
    }});
    var saved = null;
    try {{ saved = localStorage.getItem('legal-lang'); }} catch (e) {{}}
    apply(saved || ((navigator.language || 'en').slice(0, 2) === 'ru' ? 'ru' : 'en'));
  }})();
</script>
</body>
</html>
"""


def render_html(doc: str) -> str:
    return _PAGE.format(
        default_lang="en",
        title_en=TITLES[doc]["en"],
        title_ru=TITLES[doc]["ru"],
        stamp_en=html.escape(STAMP["en"]),
        stamp_ru=html.escape(STAMP["ru"]),
        body_en=_html_of(DOCS[doc]["en"]),
        body_ru=_html_of(DOCS[doc]["ru"]),
    )


def arb_updates(lang: str) -> dict[str, str]:
    out = {ARB_KEYS[doc]: DOCS[doc][lang].strip() for doc in DOCS}
    out["legalLastUpdated"] = STAMP[lang]
    return out


def apply_arb(lang: str, check: bool) -> bool:
    """Set the legal keys in one .arb, preserving key order and formatting.

    `legalPlaceholderNotice` is dropped in the same pass: it is the red warning
    the pages rendered while the text was fake, and leaving a dangling key
    behind would leave `flutter gen-l10n` generating an accessor for a notice
    nothing may show again.
    """
    path = ARB_DIR / f"app_{lang}.arb"
    data = json.loads(path.read_text(encoding="utf-8"))
    before = json.dumps(data, ensure_ascii=False, sort_keys=True)

    data.pop("legalPlaceholderNotice", None)
    data.pop("@legalPlaceholderNotice", None)
    data.update(arb_updates(lang))

    after = json.dumps(data, ensure_ascii=False, sort_keys=True)
    if before == after:
        return False
    if not check:
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--check",
        action="store_true",
        help="report staleness without writing; exit 1 if anything differs",
    )
    args = ap.parse_args()

    stale: list[str] = []

    for lang in ("en", "ru"):
        if apply_arb(lang, args.check):
            stale.append(f"mobile/lib/l10n/app_{lang}.arb")

    PUBLIC_DIR.mkdir(parents=True, exist_ok=True)
    for doc in DOCS:
        target = PUBLIC_DIR / f"{doc}.html"
        rendered = render_html(doc)
        current = target.read_text(encoding="utf-8") if target.exists() else None
        if current != rendered:
            stale.append(f"public/{doc}.html")
            if not args.check:
                target.write_text(rendered, encoding="utf-8", newline="\n")

    if args.check:
        if stale:
            print("stale, re-run scripts/legal/build_legal.py:")
            for s in stale:
                print(f"  {s}")
            return 1
        print("legal surfaces are in sync with legal_text.py")
        return 0

    if stale:
        print("rewrote:")
        for s in stale:
            print(f"  {s}")
    else:
        print("already up to date")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
