# Lab 4 - Docker Fundamentals and GitHub Actions Deep Dive

A small Flask app (`app.py`) containerised twice - once badly on purpose (`Dockerfile.naive`) and once the way I would ship it (`Dockerfile`) - measured side by side, and built in GitHub Actions with no cloud credentials.

## Build and run

```bash
cd lab4
docker build -t acs730-lab4:slim .
docker run -d --name lab4 -p 8000:8000 acs730-lab4:slim
curl -s http://localhost:8000/healthz      # {"status":"ok","version":"dev"}
docker rm -f lab4
```

## Image size: naive vs slim

| Image | Base image | Size | Rebuild after a one-line code change |
|---|---|---|---|
| `acs730-lab4:naive` | `python:latest` (Python 3.14.8 on full Debian) | 1.14 GB | 4.3 s - `pip install` ran again |
| `acs730-lab4:slim` | `python:3.12-slim-bookworm` | 137 MB | 0.6 s - `pip install` CACHED |

- **Base image:** about 1.12 GB of the naive image's 1.14 GB is `python:latest` itself - a full Debian with a compiler toolchain - against about 131 MB for the slim base, so nearly all of the 1 GB difference comes from line 1, not from my code; my own layers are small in both (the dependency layer is 17.3 MB naive, 6.38 MB slim, because `--no-cache-dir` leaves pip's download cache out of the image).
- **Dependency layer:** on a code-only rebuild the slim image reports `RUN pip install ... CACHED` and rebuilds in 0.6 s, while the naive image reinstalls everything in 4.3 s, because `COPY . .` comes before `pip install` there - any code change invalidates the copy layer and every layer after it.
- **.dockerignore:** it shrank the build context from 88 kB to 473 bytes and kept the evidence screenshots, scripts, tests, README and Dockerfiles out of the build entirely; the naive image's `/app` contains all of them, the slim image's only `app.py` and `requirements.txt`.

Two more faults of the naive image: it runs as `root` (the slim one runs as `appuser`), and `python:latest` is a moving target - today it is Python 3.14, not the version the app is tested on.

Records: `evidence/build-naive.txt`, `evidence/build-slim.txt`, `evidence/image-sizes.png`.

## Files

| File | Creates / changes | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `app.py` | The Flask app: `/` and `/healthz` | - | - | Inside the container (gunicorn) |
| `requirements.txt` | Pinned runtime dependencies: flask 3.0.3, gunicorn 22.0.0 | - | - | `pip install -r` |
| `Dockerfile` | Image `acs730-lab4` from `python:3.12-slim-bookworm`: dependencies before source, non-root `appuser`, gunicorn on port 8000 | - | - | `docker build` (workstation, CI) |
| `Dockerfile.naive` | The deliberately bad image, kept so the comparison can be re-run | - | - | `docker build -f Dockerfile.naive` |
| `.dockerignore` | Keeps `.git`, `.github`, caches, `evidence/`, `scripts/`, images, docs and Dockerfiles out of the build context | - | - | Read by `docker build` |
| `scripts/measure-image.sh` | Builds an image, rebuilds after a one-line edit, and writes `evidence/build-<tag>.txt` (times, size, user, `/app` listing, layer history) | Nothing (restores `app.py` afterwards) | `<Dockerfile> <tag>` | Workstation |
| `../.github/workflows/lab4-ci.yml` | Builds the image and smoke-tests `/healthz`; no secrets and no cloud credentials | - | - | GitHub Actions: pull requests and pushes to `main` |


