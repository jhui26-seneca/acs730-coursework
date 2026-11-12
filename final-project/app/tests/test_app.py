import urllib.error

import app as appmod


class FakeResponse:
    """Stands in for urllib's response, so the tests never touch the network."""
    status = 200

    def __init__(self, body):
        self._body = body

    def read(self, _size=-1):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def client():
    return appmod.app.test_client()


def test_healthz_checks_only_this_process(monkeypatch):
    monkeypatch.setattr(appmod, "BACKEND_URL", "")
    r = client().get("/healthz")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_index_shows_the_backend_answer(monkeypatch):
    monkeypatch.setattr(appmod, "BACKEND_URL", "http://backend.test")
    page = b"<html><h1>ACS730 final project - backend</h1></html>"
    monkeypatch.setattr(appmod.urllib.request, "urlopen", lambda url, timeout: FakeResponse(page))
    r = client().get("/")
    assert r.status_code == 200
    assert b"HTTP 200 from the VM: ACS730 final project - backend" in r.data


def test_index_fails_loudly_when_the_backend_is_down(monkeypatch):
    monkeypatch.setattr(appmod, "BACKEND_URL", "http://backend.test")

    def refuse(url, timeout):
        raise urllib.error.URLError("Connection refused")

    monkeypatch.setattr(appmod.urllib.request, "urlopen", refuse)
    r = client().get("/")
    assert r.status_code == 502
    assert b"FAILED" in r.data


def test_index_without_backend_url_is_an_error(monkeypatch):
    monkeypatch.setattr(appmod, "BACKEND_URL", "")
    assert client().get("/").status_code == 500
