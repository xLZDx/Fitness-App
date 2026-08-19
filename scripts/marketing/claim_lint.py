# -*- coding: utf-8 -*-
"""Fail-closed structural validator for the SPTR marketing site's claim system.

Two independent axes ride on every classified sentence in `public/index.html`:

  * `data-claim-state`  -- is it TRUE of the product (exists/committed/hypothesis/never)?
  * `data-public-gate`  -- may THIS WORDING be said publicly (allowed/qualify/blocked/internal-only)?

`exists` does not imply `allowed` -- a true statement can still need qualification,
legal review, or simply not exist as a build yet outside this internal prototype.

The prior scheme let an unclassified claim vanish silently from a hand-regenerated
register. That is not a failure signal a reviewer will ever see. This script makes
the failure signal executable: a marketing-copy node without classification, an
invalid enum value, a state/gate combination the rules forbid, a claim absent from
`core/marketing/claim_register.json`, or a classified claim missing its Russian
translation are all exit-1 conditions.

Usage:
    python scripts/marketing/claim_lint.py                 # lint public/index.html
    python scripts/marketing/claim_lint.py --self-test      # prove the lint can fail
    python scripts/marketing/claim_lint.py --write-register # regenerate the .md register
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HTML_PATH = ROOT / "public" / "index.html"
JS_PATH = ROOT / "public" / "assets" / "sptr" / "site.js"
REGISTER_JSON = ROOT / "core" / "marketing" / "claim_register.json"
REGISTER_MD = ROOT / "core" / "marketing" / "SPTR_MARKETING_SITE_CLAIM_REGISTER_2026-08-19.md"

STATES = {"exists", "committed", "hypothesis", "never"}
GATES = {"allowed", "qualify", "blocked", "internal-only"}

# state -> the gates that state is allowed to carry. This is the rule that
# stops "committed" or "hypothesis" copy from quietly being marked publishable.
STATE_GATE_RULES = {
    "exists": {"allowed", "qualify", "blocked"},
    "committed": {"internal-only", "blocked"},
    "hypothesis": {"internal-only", "blocked"},
    "never": set(),  # a `never` claim must not render as marketing content at all
}

# Deliberately NOT gated on data-i18n. A security review of the first version
# of this lint found the exact blind spot that gating would create: it only
# ever looked at tags already carrying data-i18n, so any marketing copy
# outside the i18n system -- concretely, <title> and <meta name="description">,
# both static and both restating claims made in the body -- rendered live and
# unclassified with zero lint errors. This regex instead matches ANY tag
# carrying at least one of the four claim-system attributes, i18n or not.
CLAIM_ATTR_NAMES = ("data-i18n", "data-claim-id", "data-claim-state", "data-public-gate", "data-nonclaim")
TAG_RE = re.compile(
    r"<([a-zA-Z0-9]+)\s+([^>]*(?:" + "|".join(re.escape(a) + r'="[^"]*"' for a in CLAIM_ATTR_NAMES) + r")[^>]*)>"
)
ATTR_RE = re.compile(r'(data-[a-z0-9-]+)="([^"]*)"')

# Known static marketing surfaces that live outside the data-i18n system.
# Hardcoded rather than relying only on the general scan above: a future
# <meta property="og:description"> or similar added without a data-* claim
# attribute at all would otherwise be invisible to TAG_RE the same way the
# original <meta name="description"> was. Extend this list before adding any
# new head-level marketing surface.
REQUIRED_STATIC_SURFACES = [
    ("title", None),
    ("meta", "description"),
]


class LintError(str):
    """A single failure line, kept as a plain string so results are diffable."""


def parse_claim_nodes(html: str) -> list[dict]:
    nodes = []
    for tag, attr_blob in TAG_RE.findall(html):
        attrs = dict(ATTR_RE.findall(attr_blob))
        nodes.append({"tag": tag, **attrs})
    return nodes


def check_required_static_surfaces(html: str) -> list[str]:
    errors = []
    for tag, name_filter in REQUIRED_STATIC_SURFACES:
        pattern = re.compile(rf"<{tag}\b([^>]*)>", re.I)
        matches = pattern.findall(html)
        if name_filter:
            matches = [m for m in matches if f'name="{name_filter}"' in m]
        if not matches:
            errors.append(f"REQUIRED SURFACE MISSING: no <{tag} name={name_filter!r}> found at all")
            continue
        for attrs in matches:
            if not any(a in attrs for a in ("data-claim-id=", "data-nonclaim=")):
                label = f"<{tag}>" if not name_filter else f'<{tag} name="{name_filter}">'
                errors.append(f"UNCLASSIFIED STATIC SURFACE: {label} carries neither data-claim-id nor data-nonclaim")
    return errors


def parse_ru_keys(js: str) -> set[str]:
    start = js.index("var RU = {")
    end = js.index("/* ---- language")
    block = js[start:end]
    return set(re.findall(r"^\s{4}([A-Za-z0-9]+)\s*:", block, re.M))


def lint(html: str, js: str, register: dict) -> list[str]:
    errors: list[str] = check_required_static_surfaces(html)
    nodes = parse_claim_nodes(html)
    ru_keys = parse_ru_keys(js)
    register_by_id = {c["id"]: c for c in register["claims"]}
    seen_ids: dict[str, int] = {}
    seen_in_html: set[str] = set()

    for n in nodes:
        has_i18n = "data-i18n" in n
        key = n.get("data-i18n", "<no i18n key -- static surface>")
        has_claim = "data-claim-id" in n
        has_nonclaim = "data-nonclaim" in n

        # Rule 1: every marketing-copy node needs a classification or an exemption.
        # (Nodes matched only because they carry data-i18n and nothing else fall
        # here too, same as before -- the broadened TAG_RE only adds coverage,
        # it never removes this check for the i18n-bearing majority of nodes.)
        if not has_claim and not has_nonclaim:
            errors.append(f"UNCLASSIFIED: '{key}' has neither data-claim-id nor data-nonclaim")
            continue

        if has_claim and has_nonclaim:
            errors.append(f"AMBIGUOUS: '{key}' carries both data-claim-id and data-nonclaim")
            continue

        if has_nonclaim:
            if not n["data-nonclaim"].strip():
                errors.append(f"EMPTY EXEMPTION: '{key}' has an empty data-nonclaim")
            continue

        # From here, has_claim is True.
        cid = n.get("data-claim-id", "")
        state = n.get("data-claim-state", "")
        gate = n.get("data-public-gate", "")

        if not cid:
            errors.append(f"MISSING ID: '{key}' has claim metadata but no data-claim-id")
            continue

        seen_ids[cid] = seen_ids.get(cid, 0) + 1
        seen_in_html.add(cid)

        # Rule 2: enum validity.
        if state not in STATES:
            errors.append(f"BAD STATE: claim '{cid}' has data-claim-state='{state}' (allowed: {sorted(STATES)})")
        if gate not in GATES:
            errors.append(f"BAD GATE: claim '{cid}' has data-public-gate='{gate}' (allowed: {sorted(GATES)})")

        # Rule 4: a `never` claim must not render as marketing content at all.
        if state == "never":
            errors.append(f"PROHIBITED CONTENT: claim '{cid}' has data-claim-state='never' and is rendered")

        # Rule 5: state/gate combination must be one the rules allow.
        elif state in STATE_GATE_RULES and gate in GATES:
            if gate not in STATE_GATE_RULES[state]:
                errors.append(
                    f"FORBIDDEN COMBINATION: claim '{cid}' is state='{state}' but public-gate='{gate}' "
                    f"(state '{state}' may only carry: {sorted(STATE_GATE_RULES[state]) or '(nothing -- never render it)'})"
                )

        # A `qualify` gate must name its qualification condition.
        if gate == "qualify" and not n.get("data-claim-qualify", "").strip():
            errors.append(f"MISSING QUALIFICATION: claim '{cid}' has public-gate='qualify' but no data-claim-qualify text")

        # Rule 7: a claim tied to a data-i18n key must have a reviewed RU
        # counterpart. A claim with no i18n key at all (a static surface like
        # <title>) has nothing to check here -- it is English-only by design,
        # which is a separate, already-documented product decision, not a
        # translation gap this rule is meant to catch.
        if has_i18n and key not in ru_keys:
            errors.append(f"MISSING LOCALE: claim '{cid}' (key '{key}') has no Russian translation in site.js")

        # Rule 6/8: markup and register must agree, in both directions --
        # including the qualification text itself, not just state/gate/key.
        # A security review found state+gate could match while the actual
        # qualify condition silently diverged between the register and the
        # on-page tooltip, which defeats the point of having one for a
        # `qualify`-gated claim.
        if cid not in register_by_id:
            errors.append(f"NOT IN REGISTER: claim '{cid}' renders in HTML but is absent from claim_register.json")
        else:
            reg = register_by_id[cid]
            if reg["state"] != state:
                errors.append(f"REGISTER DRIFT: claim '{cid}' state is '{state}' in HTML but '{reg['state']}' in register")
            if reg["gate"] != gate:
                errors.append(f"REGISTER DRIFT: claim '{cid}' gate is '{gate}' in HTML but '{reg['gate']}' in register")
            if has_i18n and reg["copy_key"] != key:
                errors.append(f"REGISTER DRIFT: claim '{cid}' key is '{key}' in HTML but '{reg['copy_key']}' in register")
            if gate == "qualify":
                html_q = n.get("data-claim-qualify", "").strip()
                reg_q = (reg.get("qualify") or "").strip()
                if html_q != reg_q:
                    errors.append(
                        f"QUALIFY TEXT DRIFT: claim '{cid}' data-claim-qualify in HTML does not match "
                        f"claim_register.json's qualify field word-for-word"
                    )

    # Rule 3: duplicate claim IDs.
    for cid, count in seen_ids.items():
        if count > 1:
            errors.append(f"DUPLICATE ID: claim '{cid}' appears {count} times")

    # Rule 8, other direction: a claim in the register that silently stopped rendering.
    for cid in register_by_id:
        if cid not in seen_in_html:
            errors.append(f"ORPHAN IN REGISTER: claim '{cid}' is in claim_register.json but does not render in HTML")

    return errors


def run_lint() -> list[str]:
    html = HTML_PATH.read_text(encoding="utf-8")
    js = JS_PATH.read_text(encoding="utf-8")
    register = json.loads(REGISTER_JSON.read_text(encoding="utf-8"))
    return lint(html, js, register)


def self_test() -> bool:
    """Mutation test: prove the validator actually fails when metadata is removed.

    Strips data-claim-id/-state/-public-gate from one real claim node (in memory
    only -- nothing on disk changes) and asserts the lint now reports it, then
    re-confirms the real file still passes clean.
    """
    html = HTML_PATH.read_text(encoding="utf-8")
    js = JS_PATH.read_text(encoding="utf-8")
    register = json.loads(REGISTER_JSON.read_text(encoding="utf-8"))

    baseline = lint(html, js, register)
    ok = True
    if baseline:
        print("SELF-TEST SETUP FAILED: the real file does not pass clean before mutation:")
        for e in baseline:
            print(" -", e)
        ok = False

    mutations = [
        ("strip claim-id",
         lambda s: s.replace('data-claim-id="hero-a-mechanic" ', "", 1)),
        ("strip claim-state",
         lambda s: s.replace('data-claim-state="exists" data-public-gate="allowed" data-i18n="subA"',
                              'data-public-gate="allowed" data-i18n="subA"', 1)),
        ("invalid enum",
         lambda s: s.replace('data-claim-state="exists" data-public-gate="allowed" data-i18n="subA"',
                              'data-claim-state="probably" data-public-gate="allowed" data-i18n="subA"', 1)),
        ("committed marked allowed",
         lambda s: s.replace('data-claim-state="committed" data-public-gate="internal-only" data-i18n="subC"',
                              'data-claim-state="committed" data-public-gate="allowed" data-i18n="subC"', 1)),
        ("duplicate id",
         lambda s: s.replace('data-claim-id="hero-b-evidence"', 'data-claim-id="hero-a-mechanic"', 1)),
        ("orphan register entry",
         lambda s: s.replace('data-claim-id="cta-no-company"', 'data-claim-id="cta-no-company-renamed"', 1)),
        # Regression case for the security review's BLOCKER finding: the first
        # version of this lint only ever looked at tags carrying data-i18n, so
        # <title> and <meta name="description"> -- live, unclassified marketing
        # copy -- rendered with zero lint errors. This proves that specific gap
        # stays closed.
        ("unclassified <title>",
         lambda s: s.replace(' data-nonclaim="seo-title"', "", 1)),
        ("unclassified <meta description>",
         lambda s: s.replace(' data-nonclaim="seo-description"', "", 1)),
        ("qualify text silently diverges from register",
         lambda s: s.replace(
             "Derived from self-logged history, not personalised coaching or a medical recommendation; the app must say the user makes the final call",
             "Derived from self-logged history -- this text no longer matches the register", 1)),
    ]

    for name, mutate in mutations:
        mutated_html = mutate(html)
        if mutated_html == html:
            print(f"SELF-TEST BROKEN: mutation '{name}' matched nothing -- fixture text drifted")
            ok = False
            continue
        errs = lint(mutated_html, js, register)
        if not errs:
            print(f"SELF-TEST FAILED: mutation '{name}' produced no lint error (validator did not catch it)")
            ok = False
        else:
            print(f"self-test '{name}': caught ({len(errs)} error(s)) -- OK")

    return ok


def write_register_md(register: dict) -> str:
    def row(c: dict) -> str:
        q = c["qualify"] or "--"
        dep = c["blocking_dependency"] or "--"
        return f"| `{c['id']}` | `{c['state']}` | `{c['gate']}` | {c['evidence']} | {q} | {dep} |"

    by_gate = {}
    for c in register["claims"]:
        by_gate.setdefault(c["gate"], []).append(c)

    order = ["allowed", "qualify", "internal-only", "blocked"]
    titles = {
        "allowed": "ALLOWED -- publishable today as worded",
        "qualify": "QUALIFY -- publishable only with the named condition attached",
        "internal-only": "INTERNAL-ONLY -- Marketing R&D language, never public",
        "blocked": "BLOCKED -- must not be public until the named blocker is closed",
    }

    lines = [
        "# SPTR Marketing Site -- Claim Register",
        "",
        f"**Generated from:** `core/marketing/claim_register.json` -- do not hand-edit this file, edit the JSON and run",
        "`python scripts/marketing/claim_lint.py --write-register`.",
        f"**Verified against:** `{register['generated_from_commit']}` -- last reviewed {register['last_reviewed']}",
        "",
        "Two independent axes. `exists` does **not** imply `allowed` -- a true statement can still need",
        "qualification, or simply belong to an internal build. Re-derive both axes for every claim; never",
        "auto-map one from the other.",
        "",
        "| Axis | Values |",
        "|---|---|",
        f"| `state` (is it true?) | {', '.join('`' + s + '`' for s in register['states'])} |",
        f"| `gate` (may it be said publicly?) | {', '.join('`' + g + '`' for g in register['gates'])} |",
        "",
    ]

    for gate in order:
        claims = by_gate.get(gate, [])
        if not claims:
            continue
        lines.append(f"## {titles[gate]}")
        lines.append("")
        lines.append("| Claim ID | State | Gate | Evidence | Qualification | Blocking dependency |")
        lines.append("|---|---|---|---|---|---|")
        for c in claims:
            lines.append(row(c))
        lines.append("")

    lines += [
        "---",
        "",
        "## Enforcement",
        "",
        "`scripts/marketing/claim_lint.py` fails closed: any marketing-copy node in `public/index.html` without",
        "either `data-claim-id`/`data-claim-state`/`data-public-gate` or an explicit `data-nonclaim` exemption is a",
        "lint failure, not a silent gap. It also fails on invalid enum values, forbidden state/gate combinations",
        "(a `committed` or `hypothesis` claim marked `allowed`), duplicate claim IDs, drift between the markup and",
        "this register, and a classified claim missing its Russian translation.",
        "",
        "```",
        "python scripts/marketing/claim_lint.py              # lint the live site",
        "python scripts/marketing/claim_lint.py --self-test   # prove the lint actually catches mutations",
        "```",
        "",
        "## Never claims",
        "",
        "None currently render, by rule -- `data-claim-state=\"never\"` is rejected by the lint unconditionally, so",
        "this is enforced structurally rather than by review discipline alone. The six phrases that must never",
        "appear are documented in the implementation report rather than the register, since a `never` claim by",
        "definition has no claim ID to register.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--self-test", action="store_true", help="run the mutation self-test instead of linting")
    ap.add_argument("--write-register", action="store_true", help="regenerate the Markdown register from the JSON manifest")
    args = ap.parse_args()

    if args.self_test:
        ok = self_test()
        print()
        print("SELF-TEST: PASS -- the validator demonstrably fails on every tested mutation" if ok
              else "SELF-TEST: FAIL -- see above")
        return 0 if ok else 1

    if args.write_register:
        register = json.loads(REGISTER_JSON.read_text(encoding="utf-8"))
        REGISTER_MD.write_text(write_register_md(register), encoding="utf-8")
        print(f"wrote {REGISTER_MD.relative_to(ROOT)}")
        return 0

    errors = run_lint()
    if errors:
        print(f"CLAIM LINT: FAIL -- {len(errors)} issue(s)\n")
        for e in errors:
            print(" -", e)
        return 1

    register = json.loads(REGISTER_JSON.read_text(encoding="utf-8"))
    n = len(register["claims"])
    print(f"CLAIM LINT: PASS -- {n} claims classified and reconciled with the register, 0 issues")
    return 0


if __name__ == "__main__":
    sys.exit(main())
