# Forge — GitHub Actions dashboard. One small image: stock Python + the
# optional Anthropic SDK (for the AI explainer). Everything else is stdlib.
FROM python:3.12-slim

LABEL org.opencontainers.image.title="Forge" \
      org.opencontainers.image.description="Live dashboard, test tracker and failure alerts for GitHub Actions, with an AI explainer" \
      org.opencontainers.image.source="https://github.com/codephilip/forge-ci" \
      org.opencontainers.image.licenses="MIT"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080 \
    FORGE_DB=/data/forge.db

RUN pip install --no-cache-dir anthropic==1.7.0 \
 && useradd --system --uid 10001 --home-dir /data forge \
 && mkdir -p /data && chown forge /data

COPY forge/ /app/

USER forge
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=4)"

CMD ["python", "/app/server.py"]
