# ACS730 midterm practice image.
#
# This Dockerfile does not currently produce a working image. Task 1.
FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

RUN pip install --no-cache-dir -r requirements.txt

COPY requirements.txt ./
COPY app.py ./

USER appuser

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
