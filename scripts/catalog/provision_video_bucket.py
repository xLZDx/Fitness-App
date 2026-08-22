"""Create the private bucket for the licensed clips, and let the functions sign for it.

WHY THIS IS A SCRIPT AND NOT TWO COMMANDS IN A CHAT LOG

Both steps are preconditions for uploading a single licensed file, and both
have to be true again every time the project is rebuilt or a second
environment appears. A script can be read, re-run, and told to check itself;
a command pasted once into a terminal cannot.

WHY IT TALKS TO THE REST API INSTEAD OF gcloud

gcloud is not installed on this machine, and installing a 200 MB SDK to make
two API calls is a poor trade. The Firebase CLI is already signed in with
`cloud-platform` scope, so this borrows that grant through
`scripts/ops/firebase_api.py`, which the library upload already uses: the CLI's
refresh token is exchanged for a short-lived access token in memory, never
written to disk and never printed. No service-account key is ever downloaded --
the same reason the signing itself goes through IAM (see
`functions/src/video_urls.ts`).

WHAT IT DOES

  1. Creates `<project>-videos-private` with uniform bucket-level access and
     public access prevention ENFORCED. The vendor's licence forbids "public
     storage folders"; enforcement makes that a property of the bucket rather
     than a promise about how we will configure it.
  2. Finds the service account the deployed functions actually run as -- asked,
     not assumed, because Cloud Functions v2 has defaulted to two different
     accounts across versions.
  3. Grants that account `roles/iam.serviceAccountTokenCreator` on ITSELF,
     which is what lets `getSignedUrl` sign without a private key.

Usage:
    python scripts/catalog/provision_video_bucket.py inspect   # read-only
    python scripts/catalog/provision_video_bucket.py apply
"""
from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "ops"))
from firebase_api import PROJECT, access_token  # noqa: E402

BUCKET = f"{PROJECT}-videos-private"

# Matches the existing public library so the licensed clips are served from the
# same continent as the ones already shipping.
LOCATION = "EU"

TOKEN_CREATOR = "roles/iam.serviceAccountTokenCreator"


class ProvisionError(RuntimeError):
    pass


def _request(method: str, url: str, token: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        # Re-raised with the body: Google's errors say WHY (billing, permission,
        # name taken) and a bare "409" would send the reader guessing.
        raise ProvisionError(f"{method} {url} -> {exc.code}\n{detail}") from None


# --------------------------------------------------------------------------
# bucket
# --------------------------------------------------------------------------

def get_bucket(token: str) -> dict | None:
    try:
        return _request(
            "GET", f"https://storage.googleapis.com/storage/v1/b/{BUCKET}", token
        )
    except ProvisionError as exc:
        if "-> 404" in str(exc):
            return None
        raise


def create_bucket(token: str) -> dict:
    return _request(
        "POST",
        "https://storage.googleapis.com/storage/v1/b?project="
        + urllib.parse.quote(PROJECT),
        token,
        {
            "name": BUCKET,
            "location": LOCATION,
            "storageClass": "STANDARD",
            "iamConfiguration": {
                # Object ACLs are how a single file quietly becomes world-readable
                # years after anyone remembers setting it. Uniform access removes
                # the mechanism rather than relying on nobody using it.
                "uniformBucketLevelAccess": {"enabled": True},
                "publicAccessPrevention": "enforced",
            },
        },
    )


def bucket_is_public(token: str) -> bool:
    policy = _request(
        "GET", f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/iam", token
    )
    for binding in policy.get("bindings", []):
        members = binding.get("members", [])
        if "allUsers" in members or "allAuthenticatedUsers" in members:
            return True
    return False


# --------------------------------------------------------------------------
# service account
# --------------------------------------------------------------------------

def function_service_accounts(token: str) -> list[str]:
    """Which account the deployed functions actually run as.

    Asked rather than assumed: Cloud Functions v2 has defaulted to the App
    Engine account on some versions and the Compute Engine one on others, and
    granting the wrong account produces a bucket that answers nobody with an
    error that reads like a missing file.
    """
    accounts: set[str] = set()
    for region in ("us-central1", "europe-west1"):
        url = (
            f"https://cloudfunctions.googleapis.com/v2/projects/{PROJECT}"
            f"/locations/{region}/functions"
        )
        try:
            listing = _request("GET", url, token)
        except ProvisionError:
            continue
        for fn in listing.get("functions", []):
            sa = (fn.get("serviceConfig") or {}).get("serviceAccountEmail")
            if sa:
                accounts.add(sa)
    return sorted(accounts)


def default_service_account() -> str:
    return f"{PROJECT}@appspot.gserviceaccount.com"


def grant_token_creator(token: str, account: str) -> bool:
    """Let `account` sign as itself. Returns True if the policy changed."""
    base = (
        f"https://iam.googleapis.com/v1/projects/{PROJECT}"
        f"/serviceAccounts/{urllib.parse.quote(account)}"
    )
    policy = _request("POST", f"{base}:getIamPolicy", token, {})
    member = f"serviceAccount:{account}"
    bindings = policy.get("bindings", [])
    for binding in bindings:
        if binding.get("role") == TOKEN_CREATOR:
            if member in binding.get("members", []):
                return False
            binding.setdefault("members", []).append(member)
            break
    else:
        bindings.append({"role": TOKEN_CREATOR, "members": [member]})
    policy["bindings"] = bindings
    # The etag is carried through from the read: two people editing the same
    # policy should collide loudly rather than one silently overwriting the
    # other's grant.
    _request("POST", f"{base}:setIamPolicy", token, {"policy": policy})
    return True


def has_token_creator(token: str, account: str) -> bool:
    base = (
        f"https://iam.googleapis.com/v1/projects/{PROJECT}"
        f"/serviceAccounts/{urllib.parse.quote(account)}"
    )
    policy = _request("POST", f"{base}:getIamPolicy", token, {})
    member = f"serviceAccount:{account}"
    return any(
        b.get("role") == TOKEN_CREATOR and member in b.get("members", [])
        for b in policy.get("bindings", [])
    )


# --------------------------------------------------------------------------

def inspect() -> int:
    token = access_token()
    print(f"project      {PROJECT}")
    bucket = get_bucket(token)
    if bucket is None:
        print(f"bucket       {BUCKET}  MISSING")
    else:
        iam_cfg = bucket.get("iamConfiguration", {})
        print(f"bucket       {BUCKET}  exists in {bucket.get('location')}")
        print(
            "  uniform    "
            + str((iam_cfg.get("uniformBucketLevelAccess") or {}).get("enabled"))
        )
        print(f"  public-ap  {iam_cfg.get('publicAccessPrevention')}")
        print(f"  world-read {bucket_is_public(token)}")

    accounts = function_service_accounts(token)
    if not accounts:
        print("functions    none deployed yet; default would be:")
        accounts = [default_service_account()]
    for sa in accounts:
        try:
            ok = has_token_creator(token, sa)
        except ProvisionError as exc:
            print(f"runtime SA   {sa}  (could not read policy)\n{exc}")
            continue
        print(f"runtime SA   {sa}  tokenCreator={ok}")
    return 0


def apply() -> int:
    token = access_token()

    if get_bucket(token) is None:
        create_bucket(token)
        print(f"created bucket {BUCKET} in {LOCATION}")
    else:
        print(f"bucket {BUCKET} already exists")

    if bucket_is_public(token):
        raise ProvisionError(
            f"{BUCKET} has a world-readable binding. The licence forbids public "
            "storage folders -- remove it before uploading anything."
        )

    accounts = function_service_accounts(token) or [default_service_account()]
    for sa in accounts:
        changed = grant_token_creator(token, sa)
        print(f"{'granted' if changed else 'already had'} {TOKEN_CREATOR}: {sa}")

    print("\nNext: firebase deploy --only functions:default")
    return 0


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else "inspect"
    try:
        if command == "inspect":
            return inspect()
        if command == "apply":
            return apply()
    except ProvisionError as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
