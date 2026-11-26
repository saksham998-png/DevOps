# Stage 1: install dependencies into a virtualenv
FROM python:3.12-slim AS build
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

# Stage 2: small runtime image, no pip cache or build tools, non-root user
FROM python:3.12-slim
ARG APP_VERSION=1.0.0
ENV PATH=/venv/bin:$PATH PYTHONUNBUFFERED=1 APP_VERSION=$APP_VERSION
COPY --from=build /venv /venv
WORKDIR /srv
COPY app/ app/
RUN useradd --uid 10001 --no-create-home appuser && mkdir /data && chown appuser /data
USER appuser
EXPOSE 5000
HEALTHCHECK --interval=15s --timeout=3s CMD python -c "import urllib.request as u; u.urlopen('http://localhost:5000/healthz')"
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app.wsgi:app"]
