# Lab 4 - Docker Fundamentals and GitHub Actions Deep Dive

A small Flask app (`app.py`) containerised twice - once badly on purpose (`Dockerfile.naive`) and once the way I would ship it (`Dockerfile`) - then built, tested, cached and published to GHCR by a GitHub Actions pipeline (`lab4-ci.yml`) that uses no cloud credentials, only the run's own `GITHUB_TOKEN`.

## Build, run and test

```bash
cd lab4
docker build -t acs730-lab4:slim .
docker run -d --name lab4 -p 8000:8000 acs730-lab4:slim
curl -s http://localhost:8000/healthz      # {"status":"ok","version":"dev"}
docker rm -f lab4
python3 -m pytest                          # 3 passed
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

## The pipeline

`test` (a matrix on Python 3.11 and 3.12, using the `python-deps` composite action) gates everything. `build` builds the image with the Docker layer cache, saves it and uploads it as an artifact, and publishes its tag as a job output; `smoke` downloads that exact artifact, runs it and probes `/healthz`. In parallel, `image` calls the reusable `docker-build.yml` workflow, which builds the image and - on `main` only - pushes it to GHCR; `report` prints the reference it returns. `summary` runs with `always()`, writes the result of every job, and re-raises any upstream failure, so it is the single check required before merging into `main`.

## CI timings

| Step | Baseline (no cache) | Cache miss | Second run* | Cache hit | Worth it? |
|---|---|---|---|---|---|
| pip install (3.11 / 3.12) | 2 s / 2 s | 4 s / 3 s | 3 s / 2 s | 2 s / 4 s | No, at this size |
| docker build step | 8 s | 16 s | 8 s | 7 s | No, at this size |
| build job incl. buildx setup | 20 s | 40 s | 46 s | 29 s | - |
| whole workflow (wall clock) | 59 s | 74 s | 91 s | 63 s | - |

\* The second run was a Docker layer-cache hit (`CACHED` in the build log) but a pip miss: the runner's Python had moved from 3.11.16 / 3.12.14 to 3.11.17 / 3.12.15, and the exact Python version is part of setup-python's cache key. The third run restored the pip cache ("Cache restored from key") for both versions.

- **pip cache - not worth it here:** the install takes about 2 s with or without the cache, because three small pinned packages download from PyPI as fast as the cache restores, and the cache silently missed whenever GitHub updated the runner's Python patch version.
- **Docker layer cache - not worth it here:** the cached build step (7 s) is no faster than a plain build on a fresh runner (8 s), while setting up buildx and exporting the cache added 10-20 s to the build job; with heavy or compiled dependencies both caches would pay for themselves, but this image is too small to benefit.

Wall-clock totals also vary with queue time (59 s to 91 s without any code change), which is why the per-step times are the real evidence. Records: `evidence/ci-timings-baseline.txt`, `ci-timings-miss.txt`, `ci-timings-miss2.txt`, `ci-timings-hit.txt`.

## Why GHCR, tagged by commit SHA

The image goes to GHCR because it sits next to the code and the pipeline logs in with the run's own short-lived `GITHUB_TOKEN`, so there is no registry password to store or rotate. It is tagged `sha-` plus the first 12 characters of the commit instead of `latest`, because a SHA tag points at one commit forever: anyone can tell exactly which code is in a running container and roll back to a known tag, while `latest` silently moves every time something is pushed. Only the `image` job can push (`packages: write`); every other job keeps the read-only default, and pull requests build the image without pushing it.

## Composite action vs reusable workflow

Installing the Python dependencies is two steps that must run on the same runner as the tests, so it is a composite action (`python-deps`) that the test job calls in place. Building and pushing the image is a whole job that needs `packages: write`, which the test job must never have, so it is a reusable workflow (`docker-build.yml`) with its own runner and its own permissions.

## GitHub Actions vs AWS-native

For a team that is all-in on AWS, I would recommend the AWS-native tools (CodeBuild and CodePipeline). Their builds run under IAM roles directly, with no OIDC bridge or stored keys, and every build and deployment lands in CloudTrail and CloudWatch alongside the rest of the team's AWS estate. GitHub Actions would win if the team valued its large marketplace of ready-made actions or expected to use another cloud later; for a team committed to AWS, tighter IAM integration and a single audit trail matter more than portability.

## Files

| File | Creates / changes | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `app.py` | The Flask app: `/` and `/healthz` | - | - | Inside the container (gunicorn) |
| `requirements.txt` | Pinned runtime dependencies: flask 3.0.3, gunicorn 22.0.0 | - | - | `pip install -r` |
| `requirements-dev.txt` | Pinned test dependency: pytest 8.3.3 (never in the image) | - | - | `pip install -r` |
| `pytest.ini`, `tests/test_app.py` | Three tests using Flask's test client (`/`, `/healthz`, a 404) | - | - | `python -m pytest` in `lab4/` |
| `Dockerfile` | Image `acs730-lab4` from `python:3.12-slim-bookworm`: dependencies before source, non-root `appuser`, gunicorn on port 8000 | - | - | `docker build` (workstation, CI) |
| `Dockerfile.naive` | The deliberately bad image, kept so the comparison can be re-run | - | - | `docker build -f Dockerfile.naive` |
| `.dockerignore` | Keeps `.git`, `.github`, caches, `evidence/`, `scripts/`, images, docs and Dockerfiles out of the build context | - | - | Read by `docker build` |
| `scripts/measure-image.sh` | Builds an image, rebuilds after a one-line edit, and writes `evidence/build-<tag>.txt` (times, size, user, `/app` listing, layer history) | Nothing (restores `app.py` afterwards) | `<Dockerfile> <tag>` | Workstation |
| `scripts/ci-timings.sh` | Writes `evidence/ci-timings-<label>.txt`: job and step durations and the cache lines from one run's log | Nothing | `<run-id> <label>` | Workstation (needs `gh`) |
| `../.github/workflows/lab4-ci.yml` | The pipeline: matrix tests, build with layer cache, artifact, smoke test, image built (and pushed to GHCR on `main`) through the reusable workflow, `always()` summary that re-raises failures | Artifacts expire after 1 day | - | GitHub Actions: pull requests and pushes to `main` |
| `../.github/workflows/docker-build.yml` | Reusable workflow: builds the image with buildx and the layer cache; pushes `ghcr.io/<owner>/acs730-lab4:sha-<12>` when `push` is true; returns `image-ref` | - | `context`, `image-name`, `push` | Called by `lab4-ci.yml` |
| `../.github/actions/python-deps/action.yml` | Composite action: setup-python with a pip cache keyed on both requirements files, then installs them | - | `python-version` | Used by the `test` job |

Branch protection on `main` requires the `summary` check before any pull request can be merged.

## Evidence

- `evidence/caller-identity.png` - the workstation's AWS identity (assumed-role/LabRole)
- `evidence/image-sizes.png`, `build-naive.txt`, `build-slim.txt` - image sizes, base images, layer history, rebuild times
- `evidence/ci-graph.png` - a green run: the test matrix fanning into build, smoke and summary, with the image tag in the summary
- `evidence/ci-timings-*.txt` - baseline, cache miss, second run and cache hit
- `evidence/ghcr-package.png` - the `acs730-lab4` package with tag `sha-2ab80c8f48fb`, matching a merge commit on `main`
- `evidence/required-check.png` - a pull request with a failing required `summary` check and a disabled merge button

## Experiments

For each experiment I made the change, observed the result, and undid it before moving on.

### 1. Invert the layer order

**What happened:** With `COPY app.py` moved above the requirements lines, a one-character change to `app.py` made Docker reinstall every dependency: the rebuild took 4.1 s, the same as a clean build, and `pip install` was not cached. With the original order, the same edit rebuilt in 0.24 s with `pip install` reported as CACHED.

**Why:** Docker caches layer by layer, and once one layer changes it rebuilds everything after it, so putting the frequently changing source above the slow, rarely changing dependency install throws that layer away on every code change. In a real project with dozens of packages that is minutes per commit, on every developer's machine and every CI run, and the fix costs nothing but the order of two lines.

### 2. Delete the .dockerignore

**What happened:** Without the `.dockerignore`, my real Dockerfile produced the same 137 MB image with only `app.py` and `requirements.txt` in `/app`. The naive Dockerfile, which copies the whole folder, sent 147 kB of context instead of 451 bytes, and its `/app` picked up the evidence screenshots, scripts, README and both Dockerfiles; the size still read 1.14 GB only because a few kilobytes disappear in gigabyte rounding.

**Why:** A `.dockerignore` only matters for what a `COPY` actually pulls in: my Dockerfile copies two named files, so it is protected either way, while `COPY . .` takes whatever the folder contains. I would still always keep one, because a single future `COPY . .` or a stray `.env` or `.git` folder in the build directory would otherwise ship straight into every image anyone pulls.

### 3. Take away contents: read

**What happened:** I removed `contents: read` from the image-building job in the reusable workflow, leaving only `packages: write`. On my public repository the run stayed green and checkout still worked, but the job's "GITHUB_TOKEN Permissions" log showed the token now held only `Metadata: read` and `Packages: write` - declaring one permission had silently dropped the contents permission.

**Why:** Checkout only survived because a public repository can be read by anyone; on a private repository the same token could not read the code and the job would fail at checkout with "repository not found", an error that looks nothing like a permissions problem. Replacing rather than adding is still the safer design: a job gets exactly what its own block lists, so a reviewer can see its full access in one place, and a forgotten line can only take access away, never quietly grant more.

### 4. Remove the re-raise

**What happened:** With the re-raise step removed and a test broken, both test cells failed and everything downstream was skipped, so the run as a whole was red - but `summary`, the required check, passed. GitHub reported the pull request as MERGEABLE with status UNSTABLE instead of BLOCKED, so the merge button would have let a failing test into `main`.

**Why:** `always()` makes the summary job run after a failure, and a job that runs to the end is green unless one of its own steps fails, so without the re-raise the required check reports success whatever happened upstream. That is worse than having no summary job at all: requiring the test job directly would at least block the merge, while a green required check that ignores failures gives false confidence - like a monitoring dashboard that shows green because the monitoring agent itself is running.

### 5. Poison the cache key

**What happened:** With the pip cache keyed on `README.md`, adding `requests` to `requirements.txt` did not change the key: the next run reported "Cache restored from key" as a hit, yet pip still downloaded and installed `requests` and its dependencies. Because the key matched exactly, the cache was not saved again, so that download would repeat on every future run while the log kept claiming a cache hit.

**Why:** setup-python's pip cache only stores downloaded files, and pip still reads `requirements.txt`, so the new package was installed and the pipeline stayed green - the wrong key cost time silently instead of breaking anything. The danger is that the log says "cached" while the cache drifts away from what is actually installed; with a cache that stores an installed environment instead of downloads, the same mistake would ship stale packages with no error at all.
