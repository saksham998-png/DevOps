FROM python:3.12-slim AS build
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
ARG APP_VERSION=dev
ENV PATH=/venv/bin:$PATH PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 APP_VERSION=$APP_VERSION
COPY --from=build /venv /venv
WORKDIR /srv
COPY app/ app/
RUN useradd --uid 10001 --no-create-home appuser
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s CMD python -c "import urllib.request as u; u.urlopen('http://localhost:8080/healthz')"
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--graceful-timeout", "20", "app.wsgi:app"]
