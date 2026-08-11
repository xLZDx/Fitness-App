"""Record what is actually deployed to production, by asking production.

WHY A GENERATOR AND NOT A DOCUMENT: a hand-written snapshot of deployed state is
wrong the moment anything is deployed, and nothing tells you it went wrong. The
2026-08-12 doc-refresh gate found 22 of 31 CODEMAP rows drifted, a feature
documented that was never built, and two live docs contradicting each other --
all of them hand-maintained numbers. `scripts/dev/build_release.ps1` learned the
same lesson earlier and derives its SHA rather than accepting one.

So this file is the source of truth and `core/PRODUCTION_MANIFEST.md` is its
output. Re-run it, do not edit it.

WHAT IT REFUSES TO DO: invent. Every field is either a value read from a live API
or the literal string `unavailable: <reason>` carrying the error. A blank cell in
a manifest reads as "nothing deployed", which is a different and much more
comforting claim than "I could not look".

Usage:
    python scripts/dev/production_manifest.py            # writes the .md + .csv
    python scripts/dev/production_manifest.py --print    # stdout only

Auth: `firebase login` for the Functions list, and `gcloud auth
print-access-token` for the three REST reads. Both are read-only here.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_PROJECT = "fitness-app-korostelev"
REPO = Path(__file__).resolve().parents[2]
MD_OUT = REPO / "core" / "PRODUCTION_MANIFEST.md"
CSV_OUT = REPO / "core" / "PRODUCTION_MANIFEST.csv"

UNAVAILABLE = "unavailable"


def unavailable(reason: str) -> str:
    """The one way this file is allowed to not know something."""
    return f"{UNAVAILABLE}: {reason}"


def run(cmd: list[str], timeout: int = 180) -> tuple[bool, str]:
    try:
        p = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, cwd=REPO,
            shell=(sys.platform == "win32"),
        )
    except FileNotFoundError:
        return False, f"{cmd[0]} not on PATH"
    except subprocess.TimeoutExpired:
        return False, f"{cmd[0]} timed out after {timeout}s"
    if p.returncode != 0:
        # `firebase --json` reports its real failure as JSON on STDOUT and leaves
        # stderr to node's warnings, so the reason has to be read from there first
        # or the manifest records "exit 1" for a permission problem it was told
        # about in words.
        raw = (p.stdout or "").strip()
        if raw.startswith("{"):
            try:
                j = json.loads(raw)
                if isinstance(j, dict) and j.get("error"):
                    return False, str(j["error"])[:200].replace("\n", " ")
            except json.JSONDecodeError:
                pass
        # The LAST line is not the reason. The firebase CLI ends every run with a
        # node DeprecationWarning, so a naive tail reported "Use --trace-deprecation"
        # as the cause of a permission failure -- an error message that lies about
        # why, which is the exact failure this file exists to prevent.
        noise = ("DeprecationWarning", "--trace-deprecation", "(node:")
        err = [
            l.strip()
            for l in (p.stderr or p.stdout or "").strip().splitlines()
            if l.strip() and not any(n in l for n in noise)
        ]
        return False, (err[-1] if err else f"exit {p.returncode}")
    return True, p.stdout


def git_state() -> dict[str, str]:
    out: dict[str, str] = {}
    for key, cmd in (
        ("sha", ["git", "rev-parse", "HEAD"]),
        ("short", ["git", "rev-parse", "--short", "HEAD"]),
        ("branch", ["git", "rev-parse", "--abbrev-ref", "HEAD"]),
    ):
        ok, res = run(cmd, timeout=30)
        out[key] = res.strip() if ok else unavailable(res)
    ok, res = run(["git", "status", "--porcelain"], timeout=60)
    if not ok:
        out["tree"] = unavailable(res)
    else:
        n = len([l for l in res.splitlines() if l.strip()])
        # Named, not hidden: a manifest generated from a dirty tree does not
        # describe any commit, and the reader has to be able to see that.
        out["tree"] = "clean" if n == 0 else f"DIRTY -- {n} uncommitted path(s)"
    return out


def access_token() -> tuple[str | None, str]:
    ok, res = run(["gcloud", "auth", "print-access-token"], timeout=90)
    if not ok:
        return None, res
    tok = res.strip()
    return (tok, "") if tok else (None, "empty token")


def get_json(url: str, token: str) -> tuple[dict | None, str]:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode()), ""
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:200].replace("\n", " ")
        return None, f"HTTP {e.code} -- {body}"
    except Exception as e:  # noqa: BLE001 - reported verbatim, never swallowed
        return None, f"{type(e).__name__}: {e}"


def functions(project: str) -> tuple[list[dict], str]:
    ok, res = run(
        ["firebase", "functions:list", "--project", project, "--json"], timeout=240
    )
    if not ok:
        return [], unavailable(res)
    try:
        data = json.loads(res)
    except json.JSONDecodeError as e:
        return [], unavailable(f"unparseable JSON from firebase CLI: {e}")
    items = data.get("result", data) if isinstance(data, dict) else data
    rows = []
    for f in items:
        src = (f.get("source") or {}).get("storageSource") or {}
        rows.append(
            {
                "id": f.get("id", "?"),
                "platform": f.get("platform", "?"),
                "region": f.get("region", "?"),
                "runtime": f.get("runtime", "?"),
                # The identity that actually changes on every deploy. A function
                # name tells you nothing about WHICH build is answering calls.
                "source_generation": str(src.get("generation", "?")),
            }
        )
    rows.sort(key=lambda r: r["id"])
    return rows, ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--print", action="store_true", dest="to_stdout")
    # Overridable so the `unavailable:` path can be EXERCISED rather than assumed:
    # point it at a project that does not exist, with --print so nothing is written,
    # and every section must report its own failure instead of a blank or a crash.
    ap.add_argument("--project", default=None)
    args = ap.parse_args()
    project = args.project or DEFAULT_PROJECT

    now = datetime.now().astimezone()
    # Both zones carry their own DATE. After midnight local the two disagree on the
    # day -- 02:46 local is 23:46 UTC YESTERDAY -- and a bare "23:46 UTC" next to a
    # local date reads as the same day to everyone who is not converting carefully.
    utc = now.astimezone(timezone.utc)
    stamp = (
        f"{now.strftime('%Y-%m-%d %H:%M')} local ({now.tzname()}) / "
        f"{utc.strftime('%Y-%m-%d %H:%M')} UTC"
    )

    git = git_state()
    fns, fns_err = functions(project)

    token, tok_err = access_token()
    rules = appcheck = hosting = None
    rules_err = appcheck_err = hosting_err = ""
    if token is None:
        rules_err = appcheck_err = hosting_err = unavailable(
            f"no access token -- {tok_err}"
        )
    else:
        rules, e = get_json(
            f"https://firebaserules.googleapis.com/v1/projects/{project}/releases", token
        )
        rules_err = unavailable(e) if e else ""
        appcheck, e = get_json(
            f"https://firebaseappcheck.googleapis.com/v1/projects/{project}/services",
            token,
        )
        appcheck_err = unavailable(e) if e else ""
        hosting, e = get_json(
            f"https://firebasehosting.googleapis.com/v1beta1/sites/{project}"
            "/releases?pageSize=1",
            token,
        )
        hosting_err = unavailable(e) if e else ""

    lines: list[str] = []
    add = lines.append
    add("# Production manifest")
    add("")
    add(f"**Generated {stamp}** by `scripts/dev/production_manifest.py`.")
    add("")
    add(
        "Do not hand-edit: re-run the script. Every value below was read from a live "
        "API at that moment, or says `unavailable:` with the reason it could not be."
    )
    add("")
    add("## Source tree this manifest was generated from")
    add("")
    add("| Field | Value |")
    add("|---|---|")
    add(f"| Commit | `{git['sha']}` (`{git['short']}`) |")
    add(f"| Branch | `{git['branch']}` |")
    add(f"| Working tree | {git['tree']} |")
    add("")
    add(
        "This is the LOCAL tree, not proof of what was deployed. Compare it against the "
        "function source generations below, which change on every deploy."
    )
    add("")

    add("## Cloud Functions")
    add("")
    if fns_err:
        add(fns_err)
    else:
        add(f"{len(fns)} deployed.")
        add("")
        add("| Function | Platform | Region | Runtime | Source generation |")
        add("|---|---|---|---|---|")
        for f in fns:
            add(
                f"| `{f['id']}` | {f['platform']} | {f['region']} | {f['runtime']} "
                f"| `{f['source_generation']}` |"
            )
    add("")

    add("## Firestore ruleset")
    add("")
    if rules_err:
        add(rules_err)
    else:
        rel = (rules or {}).get("releases") or []
        if not rel:
            add("No releases returned -- no ruleset is published.")
        add("")
        add("| Release | Ruleset | Updated |")
        add("|---|---|---|")
        for r in rel:
            add(
                f"| `{r.get('name','?').split('/')[-1]}` "
                f"| `{r.get('rulesetName','?').split('/')[-1]}` "
                f"| {r.get('updateTime','?')} |"
            )
    add("")

    add("## App Check enforcement")
    add("")
    if appcheck_err:
        add(appcheck_err)
    else:
        svcs = (appcheck or {}).get("services") or []
        if not svcs:
            add(
                "No services returned. App Check reports nothing here, which means no "
                "service has a non-default enforcement mode set."
            )
        add("")
        add("| Service | Enforcement | Updated |")
        add("|---|---|---|")
        for s in svcs:
            add(
                f"| `{s.get('name','?').split('/')[-1]}` "
                f"| **{s.get('enforcementMode','?')}** | {s.get('updateTime','?')} |"
            )
    add("")

    add("## Hosting")
    add("")
    if hosting_err:
        add(hosting_err)
    else:
        rel = (hosting or {}).get("releases") or []
        if not rel:
            add("No releases returned.")
        for r in rel:
            v = r.get("version") or {}
            add("| Field | Value |")
            add("|---|---|")
            add(f"| Release | `{r.get('name','?').split('/')[-1]}` |")
            add(f"| Version | `{v.get('name','?').split('/')[-1]}` |")
            add(f"| Status | {v.get('status','?')} |")
            add(f"| Created | {v.get('createTime','?')} |")
    add("")

    md = "\n".join(lines) + "\n"

    rows: list[dict[str, str]] = []
    rows.append({"section": "git", "key": "commit", "value": git["sha"], "detail": git["branch"]})
    rows.append({"section": "git", "key": "tree", "value": git["tree"], "detail": ""})
    if fns_err:
        rows.append({"section": "functions", "key": "*", "value": fns_err, "detail": ""})
    for f in fns:
        rows.append(
            {
                "section": "functions",
                "key": f["id"],
                "value": f["source_generation"],
                "detail": f"{f['platform']} {f['region']} {f['runtime']}",
            }
        )
    if rules_err:
        rows.append({"section": "firestore_rules", "key": "*", "value": rules_err, "detail": ""})
    for r in ((rules or {}).get("releases") or []):
        rows.append(
            {
                "section": "firestore_rules",
                "key": r.get("name", "?").split("/")[-1],
                "value": r.get("rulesetName", "?").split("/")[-1],
                "detail": r.get("updateTime", "?"),
            }
        )
    if appcheck_err:
        rows.append({"section": "app_check", "key": "*", "value": appcheck_err, "detail": ""})
    for s in ((appcheck or {}).get("services") or []):
        rows.append(
            {
                "section": "app_check",
                "key": s.get("name", "?").split("/")[-1],
                "value": s.get("enforcementMode", "?"),
                "detail": s.get("updateTime", "?"),
            }
        )
    if hosting_err:
        rows.append({"section": "hosting", "key": "*", "value": hosting_err, "detail": ""})
    for r in ((hosting or {}).get("releases") or []):
        v = r.get("version") or {}
        rows.append(
            {
                "section": "hosting",
                "key": r.get("name", "?").split("/")[-1],
                "value": v.get("name", "?").split("/")[-1],
                "detail": f"{v.get('status','?')} {v.get('createTime','?')}",
            }
        )

    if args.to_stdout:
        sys.stdout.write(md)
        return 0

    MD_OUT.write_text(md, encoding="utf-8", newline="\n")
    # CSV twin, per the standing rule for any table-shaped report.
    with io.open(CSV_OUT, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["section", "key", "value", "detail"])
        w.writeheader()
        w.writerows(rows)

    missing = [r for r in rows if str(r["value"]).startswith(UNAVAILABLE)]
    print(f"wrote {MD_OUT.relative_to(REPO)} and {CSV_OUT.relative_to(REPO)}")
    print(f"{len(rows)} rows, {len(missing)} unavailable")
    for m in missing:
        print(f"  {m['section']}/{m['key']}: {m['value']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
