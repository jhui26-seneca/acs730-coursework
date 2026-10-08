import os

from flask import Flask

app = Flask(__name__)
VERSION = os.environ.get("APP_VERSION", "dev")


@app.get("/")
def index():
    return "ACS730 Lab 4 -- version " + VERSION + "\n", 200


@app.get("/healthz")
def healthz():
    return {"status": "ok", "version": VERSION}, 200
