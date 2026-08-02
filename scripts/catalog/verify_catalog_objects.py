# -*- coding: utf-8 -*-
"""Every licensed clip the catalog promises must actually be in the bucket.

A catalog entry pointing at an object that was never uploaded does not fail
loudly. `clipUrl` signs happily -- signing does not check existence -- and the
phone gets a URL that 404s, so the exercise shows its poster forever and looks
like a slow network. That is indistinguishable from working, which is exactly
why it needs its own check.

Both directions are worth knowing:

  missing    the catalog promises a clip the bucket does not have -- broken
  orphaned   the bucket holds a clip nothing points at -- paid-for storage
             doing nothing, and the pool the next matching pass draws from

    python scripts/catalog/verify_catalog_objects.py
"""
from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "ops"))
from firebase_api import access_token  # noqa: E402
from upload_video_library import LICENSED_BUCKET, existing  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "mobile" / "assets" / "data" / "exercises.json"


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))

    promised: dict[str, list[str]] = {}
    public = 0
    for entry in catalog:
        for body, ref in (entry.get("video") or {}).items():
            if ref.startswith("http"):
                public += 1
                continue
            promised.setdefault(ref, []).append(f"{entry['id']}/{body}")

    print(f"catalog promises {len(promised)} licensed objects "
          f"and {public} public urls")

    have = set(existing(access_token(), LICENSED_BUCKET))
    print(f"bucket holds {len(have)} objects")

    missing = sorted(set(promised) - have)
    orphaned = sorted(have - set(promised))

    print(f"\nmissing  {len(missing)}  (catalog points at nothing)")
    for ref in missing[:15]:
        print(f"   {ref}  <- {', '.join(promised[ref])}")
    if len(missing) > 15:
        print(f"   ... and {len(missing) - 15} more")

    print(f"\norphaned {len(orphaned)}  (uploaded, nothing points at it)")
    print("   these are the pool a later matching pass draws from, not waste")

    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
