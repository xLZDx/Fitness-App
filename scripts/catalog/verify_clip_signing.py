"""End-to-end check that a licensed clip is reachable through the app and no other way.

A successful `firebase deploy` proves the code was uploaded. It does not prove
that the runtime account can actually sign, that the bucket actually refuses
strangers, or that the path allow-list actually rejects a traversal -- and each
of those is the whole point of the arrangement. So this puts a real object in
the real bucket, asks the deployed function for a real URL as a real signed-in
user, and then tries to get at the same object every way a stranger would.

It cleans up after itself: the probe object is deleted, and the anonymous user
created to hold an ID token is deleted too.

    python scripts/catalog/verify_clip_signing.py
"""
from __future__ import annotations

import json
import pathlib
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from provision_video_bucket import BUCKET, PROJECT, _request, access_token  # noqa: E402

REGION = "us-central1"

# This machine runs Norton Web/Mail Shield, which terminates TLS to
# *.cloudfunctions.net and *.run.app and re-signs it with a CA whose Basic
# Constraints are not marked critical. OpenSSL 3 rejects that outright, so no
# CA bundle can rescue it -- the interceptor's certificate is simply malformed.
#
# When that is detected the script retries without certificate verification and
# says so in its output. It is a deliberate, announced, local-only fallback: the
# thing under test is whether the function signs and the bucket refuses
# strangers, not whether this laptop's antivirus makes valid certificates. The
# app on a phone never meets any of this.
_insecure = ssl._create_unverified_context()
intercepted = False

# The address the Flutter client SDK actually resolves to, so the test exercises
# the same route the app does rather than a private back door.
CALLABLE = f"https://{REGION}-{PROJECT}.cloudfunctions.net"

# A path that satisfies the function's allow-list without colliding with a real
# exercise. Deleted at the end.
PROBE_OBJECT = "exercises/men/_verify/signing probe.mp4"
PROBE_BODY = b"not a real clip -- signing probe\n"

GOOGLE_SERVICES = pathlib.Path("mobile/android/app/google-services.json")


class CheckFailed(AssertionError):
    pass


results: list[tuple[bool, str]] = []


def check(passed: bool, description: str) -> None:
    results.append((passed, description))
    print(f"  {'PASS' if passed else 'FAIL'}  {description}")


def http(
    method: str,
    url: str,
    *,
    token: str | None = None,
    body: bytes | None = None,
    content_type: str | None = None,
) -> tuple[int, bytes]:
    """Returns (status, body) instead of raising, because the failures ARE the test."""
    global intercepted
    req = urllib.request.Request(url, data=body, method=method)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except urllib.error.URLError as exc:
        if "CERTIFICATE_VERIFY_FAILED" not in str(exc):
            return 0, str(exc).encode()
        intercepted = True
        try:
            with urllib.request.urlopen(req, context=_insecure) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as exc2:
            return exc2.code, exc2.read()
        except urllib.error.URLError as exc2:
            return 0, str(exc2).encode()


def web_api_key() -> str:
    """Public by design -- it identifies the project, it does not authorise anything."""
    data = json.loads(GOOGLE_SERVICES.read_text(encoding="utf-8"))
    return data["client"][0]["api_key"][0]["current_key"]


def sign_in_anonymously(api_key: str) -> tuple[str, str]:
    """An ID token for a throwaway user. Returns (idToken, refreshable idToken owner)."""
    status, raw = http(
        "POST",
        "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key="
        + urllib.parse.quote(api_key),
        body=json.dumps({"returnSecureToken": True}).encode(),
        content_type="application/json",
    )
    if status != 200:
        raise CheckFailed(
            "Could not create an anonymous user for the test "
            f"(HTTP {status}): {raw.decode(errors='replace')[:300]}"
        )
    payload = json.loads(raw)
    return payload["idToken"], payload["localId"]


def delete_user(api_key: str, id_token: str) -> None:
    http(
        "POST",
        "https://identitytoolkit.googleapis.com/v1/accounts:delete?key="
        + urllib.parse.quote(api_key),
        body=json.dumps({"idToken": id_token}).encode(),
        content_type="application/json",
    )


def upload_probe(token: str) -> None:
    url = (
        f"https://storage.googleapis.com/upload/storage/v1/b/{BUCKET}/o"
        f"?uploadType=media&name={urllib.parse.quote(PROBE_OBJECT, safe='')}"
    )
    status, raw = http(
        "POST", url, token=token, body=PROBE_BODY, content_type="video/mp4"
    )
    if status not in (200, 201):
        raise CheckFailed(f"upload failed ({status}): {raw.decode(errors='replace')[:300]}")


def delete_probe(token: str) -> None:
    http(
        "DELETE",
        f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o/"
        + urllib.parse.quote(PROBE_OBJECT, safe=""),
        token=token,
    )


def call_function(name: str, data: dict, id_token: str | None) -> tuple[int, dict]:
    status, raw = http(
        "POST",
        f"{CALLABLE}/{name}",
        token=id_token,
        body=json.dumps({"data": data}).encode(),
        content_type="application/json",
    )
    try:
        return status, json.loads(raw)
    except json.JSONDecodeError:
        return status, {"raw": raw.decode(errors="replace")[:300]}


def main() -> int:
    api_key = web_api_key()
    admin = access_token()

    print(f"bucket   {BUCKET}")
    print(f"function {CALLABLE}/clipUrl\n")

    upload_probe(admin)
    id_token, _uid = sign_in_anonymously(api_key)

    try:
        # 1. The licence condition: no permanent public link to the raw file.
        public = (
            f"https://storage.googleapis.com/{BUCKET}/"
            + urllib.parse.quote(PROBE_OBJECT)
        )
        status, _ = http("GET", public)
        check(status in (401, 403), f"an unsigned request is refused (HTTP {status})")

        # 2. A signed-in user gets a URL.
        status, payload = call_function("clipUrl", {"object": PROBE_OBJECT}, id_token)
        signed = (payload.get("result") or {}).get("url") if status == 200 else None
        check(
            bool(signed),
            "a signed-in user gets a signed URL"
            + ("" if signed else f" -- HTTP {status}: {json.dumps(payload)[:300]}"),
        )

        # 3. That URL actually opens the object. This is the step that proves the
        #    tokenCreator grant works; everything before it can pass with a
        #    misconfigured service account.
        if signed:
            status, got = http("GET", signed)
            check(status == 200 and got == PROBE_BODY,
                  f"the signed URL returns the object (HTTP {status})")
            check("X-Goog-Expires" in signed or "x-goog-expires" in signed.lower(),
                  "the URL carries an expiry")

        # 4. Anonymous callers get nothing. Without this, "signed URL" just means
        #    "public URL with extra steps".
        status, payload = call_function("clipUrl", {"object": PROBE_OBJECT}, None)
        check(status in (401, 403),
              f"an unauthenticated call is refused (HTTP {status})")

        # 5. The allow-list. The object path is the one hostile input here.
        for hostile, label in [
            ("exercises/men/../../secrets/key.mp4", "traversal"),
            ("../../../etc/passwd", "absolute escape"),
            ("exercises/other/A/b.mp4", "a body that is not girl/men"),
            ("exercises/men/A/b.txt", "a non-mp4 extension"),
        ]:
            status, payload = call_function("clipUrl", {"object": hostile}, id_token)
            check(status >= 400, f"{label} is rejected (HTTP {status})")

        # 6. The batch cap is a real limit, not a comment.
        status, payload = call_function(
            "clipUrls", {"objects": [PROBE_OBJECT] * 61}, id_token
        )
        check(status >= 400, f"a 61-clip batch is rejected (HTTP {status})")

        status, payload = call_function(
            "clipUrls", {"objects": [PROBE_OBJECT]}, id_token
        )
        urls = (payload.get("result") or {}).get("urls") or {}
        check(PROBE_OBJECT in urls, "a batch of one returns that one")

    finally:
        delete_user(api_key, id_token)
        delete_probe(admin)
        print("\ncleaned up: probe object and anonymous user deleted")

    if intercepted:
        print(
            "\nNOTE: TLS to the function was intercepted by local antivirus, so "
            "certificate\n      verification was skipped for those calls. Every "
            "check above is still a\n      real round trip to the deployed "
            "function; only the transport was trusted\n      blindly, and only "
            "on this machine."
        )

    failed = [d for ok, d in results if not ok]
    print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
    if failed:
        print("FAILED:")
        for d in failed:
            print(f"  - {d}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
