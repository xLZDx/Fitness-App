"""Hardening tests for firebase_api.main exit code and upload_video_library."""
from __future__ import annotations

import sys
import urllib.error
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
import firebase_api  # noqa: E402
import upload_video_library as uvl  # noqa: E402


def test_main_exits_nonzero_when_a_call_returns_http_error(monkeypatch):
    monkeypatch.setattr(firebase_api, "access_token", lambda: "t")
    monkeypatch.setattr(firebase_api, "api",
                        lambda *a, **k: {"_httpError": 403, "_body": "no"})
    assert firebase_api.main() == 1


def test_main_exits_zero_when_all_calls_succeed(monkeypatch):
    monkeypatch.setattr(firebase_api, "access_token", lambda: "t")
    monkeypatch.setattr(firebase_api, "api", lambda *a, **k: {})
    assert firebase_api.main() == 0


def test_bucket_names_follow_the_current_project():
    assert uvl.BUCKET == f"{firebase_api.PROJECT}-videos-eu"
    assert uvl.LICENSED_BUCKET == f"{firebase_api.PROJECT}-videos-private"
    assert "traidingbot" not in uvl.BUCKET


def test_foreign_bucket_is_refused():
    with pytest.raises(SystemExit):
        uvl.check_bucket("traidingbot-b4061-videos-eu")
    assert uvl.check_bucket(uvl.BUCKET) == uvl.BUCKET


def test_upload_streams_a_file_object_with_content_length(tmp_path, monkeypatch):
    clip = tmp_path / "c.mp4"
    clip.write_bytes(b"x" * 10)
    captured = {}

    class R:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def read(self):
            return b""

    def fake_open(req, timeout=None):
        captured["data"] = req.data
        captured["len"] = req.get_header("Content-length")
        return R()

    monkeypatch.setattr(uvl.urllib.request, "urlopen", fake_open)
    assert uvl.upload(clip, "exercises/a.mp4", "t", uvl.BUCKET) == ("exercises/a.mp4", "")
    assert not isinstance(captured["data"], (bytes, bytearray))
    assert captured["len"] == "10"


def test_verify_clip_signing_never_retries_insecurely_with_a_token(monkeypatch):
    import verify_clip_signing as v

    calls = []

    def boom(req, context=None, timeout=None):
        calls.append(context)
        raise urllib.error.URLError("CERTIFICATE_VERIFY_FAILED")

    monkeypatch.setattr(v.urllib.request, "urlopen", boom)
    monkeypatch.setattr(v, "allow_insecure", True)
    with pytest.raises(v.CheckFailed):
        v.http("GET", "https://x.example/a", token="secret")
    assert calls == [None]  # one verified attempt, no insecure retry

    # Without a token and without opt-in: loud failure too.
    monkeypatch.setattr(v, "allow_insecure", False)
    with pytest.raises(v.CheckFailed):
        v.http("GET", "https://x.example/a")
    # Token-less + opt-in: the retry happens, with a timeout.
    monkeypatch.setattr(v, "allow_insecure", True)
    calls.clear()
    assert v.http("GET", "https://x.example/a")[0] == 0
    assert len(calls) == 2 and calls[1] is not None
