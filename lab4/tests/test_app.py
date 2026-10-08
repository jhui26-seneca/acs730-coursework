from app import app


def test_index_returns_200():
    r = app.test_client().get("/")
    assert r.status_code == 200
    assert b"ACS730 Lab 4" in r.data


def test_healthz_reports_ok():
    r = app.test_client().get("/healthz")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_unknown_path_is_404():
    assert app.test_client().get("/nope").status_code == 200
