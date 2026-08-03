# -*- coding: utf-8 -*-
"""Turn public read on `traidingbot-b4061-videos-eu` off -- or back on.

WHAT IS IN THAT BUCKET

677 clips pulled from a public Drive folder before the animation pack was
bought. They carry no licence (commit e233eb0: *"these clips came from a public
Drive folder and carry none"*), and the bucket granted
`roles/storage.objectViewer` to `allUsers` -- world-readable, permanent URLs.

WHY OFF AND NOT DELETED

Operator: *"отключаем а не удаляем"*. Removing the IAM binding stops the
distribution, which is the part that matters, and it is one command to undo.
Deleting 677 objects is not.

WHAT IT BREAKS

Nothing in the current catalog: every clip reference is now a signed object key
in the private bucket. But a build already installed on a phone (1.0.0+14 and
earlier) still holds the old catalog, and its clips stop loading the moment
this runs. `--on` puts them back if that matters before the next build ships.

Usage:
    python scripts/catalog/set_scaffold_bucket_public.py            # show state
    python scripts/catalog/set_scaffold_bucket_public.py --off
    python scripts/catalog/set_scaffold_bucket_public.py --on
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ops"))
from firebase_api import access_token, api  # noqa: E402

BUCKET = "traidingbot-b4061-videos-eu"
PUBLIC = {"allUsers", "allAuthenticatedUsers"}
IAM = f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/iam"


def public_bindings(policy: dict) -> list[dict]:
    return [b for b in policy.get("bindings", [])
            if PUBLIC & set(b.get("members", []))]


def main() -> None:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--off", action="store_true", help="remove public read")
    g.add_argument("--on", action="store_true", help="restore public read")
    args = ap.parse_args()

    token = access_token()
    policy = api(IAM, token, "GET")
    if "_httpError" in policy:
        sys.exit(f"could not read the policy: {policy['_httpError']}")

    found = public_bindings(policy)
    print(f"{BUCKET}: " + (
        "PUBLIC — " + ", ".join(f"{b['role']} to {sorted(PUBLIC & set(b['members']))}"
                                for b in found)
        if found else "not public"))

    if not (args.off or args.on):
        print("\nnothing changed -- pass --off or --on")
        return

    bindings = policy.get("bindings", [])
    if args.off:
        if not found:
            print("already off")
            return
        # The whole binding goes only if `allUsers` was its only member;
        # otherwise just that member is dropped, so a role granted to a real
        # principal in the same binding survives.
        next_bindings = []
        for b in bindings:
            members = [m for m in b.get("members", []) if m not in PUBLIC]
            if members:
                next_bindings.append({**b, "members": members})
    else:
        if found:
            print("already on")
            return
        next_bindings = bindings + [
            {"role": "roles/storage.objectViewer", "members": ["allUsers"]}
        ]

    # etag is sent back so a policy changed by someone else since the read is
    # rejected rather than silently overwritten.
    body = {"bindings": next_bindings, "etag": policy.get("etag")}
    result = api(IAM, token, "PUT", body)
    if "_httpError" in result:
        sys.exit(f"could not write the policy: {result['_httpError']}: "
                 f"{result.get('_body', '')[:200]}")

    after = public_bindings(api(IAM, token, "GET"))
    print("now: " + ("PUBLIC" if after else "not public"))
    if args.off and not after:
        print("677 unlicensed clips are no longer served to anonymous callers.")
        print("Objects are untouched; --on restores it in one command.")


if __name__ == "__main__":
    main()
