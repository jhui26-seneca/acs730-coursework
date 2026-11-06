"""ACS730 midterm practice application.

A deliberately small JSON API: a version endpoint and a health endpoint.
The application itself is correct. Do not change it.
"""
import os

from flask import Flask, jsonify

app = Flask(__name__)

APP_VERSION = os.environ.get("APP_VERSION", "0.1.0")
APP_PORT = int(os.environ.get("PORT", "8000"))


@app.get("/")
def index():
    return jsonify(service="acs730-midterm", version=APP_VERSION)


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=APP_PORT)
