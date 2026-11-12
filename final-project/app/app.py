import os
import re
import urllib.error
import urllib.request

from flask import Flask

# Final project frontend: the Week 4 Flask app, with one change. "/" calls the backend (Apache on
# the VM) and puts the VM's answer in its own response, so the dependency is visible in a curl.
# If the VM can't be reached, "/" fails with 502 instead of hiding the error. /healthz checks only
# this process, so a backend outage doesn't take every Pod out of the Service.
app = Flask(__name__)
VERSION = os.environ.get("APP_VERSION", "dev")
BACKEND_URL = os.environ.get("BACKEND_URL", "")


def fetch_backend():
    """Call the VM's home page; return (HTTP status, the page's <h1> text). Raises on failure."""
    with urllib.request.urlopen(BACKEND_URL.rstrip("/") + "/", timeout=3) as resp:
        status = resp.status
        body = resp.read(65536).decode("utf-8", "replace")
    match = re.search(r"<h1>(.*?)</h1>", body, re.S)
    return status, (match.group(1).strip() if match else "(no <h1> in the page)")


@app.get("/")
def index():
    head = "ACS730 final project frontend (Flask on Kubernetes) -- version " + VERSION + "\n"
    if not BACKEND_URL:
        return head + "backend: BACKEND_URL is not set\n", 500
    try:
        status, title = fetch_backend()
    except (urllib.error.URLError, OSError) as err:
        return head + "backend: the call to the VM FAILED: " + str(err) + "\n", 502
    return head + "backend: HTTP " + str(status) + " from the VM: " + title + "\n", 200


@app.get("/healthz")
def healthz():
    return {"status": "ok", "version": VERSION}, 200
