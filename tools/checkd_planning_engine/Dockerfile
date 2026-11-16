FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/tools/checkd_planning_engine/src \
    CHECKD_MCP_ENV=production
WORKDIR /app
COPY docs/contracts/agent-planning-v0.json /app/docs/contracts/agent-planning-v0.json
COPY tools/checkd_planning_engine/src /app/tools/checkd_planning_engine/src
RUN useradd --system --uid 10001 checkd && chown -R checkd:checkd /app
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"
CMD ["python", "-m", "checkd_planning_engine.remote_server"]
