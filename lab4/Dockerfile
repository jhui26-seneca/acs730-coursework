FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=dev

WORKDIR /app

# Dependencies first, from a file that changes rarely.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Source last: a code change invalidates only this layer and what follows.
COPY app.py ./

RUN useradd --system --no-create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app:app"]
