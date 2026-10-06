FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /app
RUN pip install --no-cache-dir uv==0.12.23
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY mono ./mono
COPY migrations ./migrations
COPY alembic.ini ./
RUN useradd --uid 10001 --create-home mono
USER mono
ENV PATH="/opt/venv/bin:$PATH"
EXPOSE 8000
# Migrations then idempotent terminal provisioning before serving: the free
# host offers no shell or pre-deploy step. A different terminal stops startup.
CMD ["sh", "-c", "alembic upgrade head && python -m mono.provision && exec uvicorn mono.main:app --host 0.0.0.0 --port ${PORT:-8000} --no-access-log"]
