# ☕ Chai Stall: small, non-root, with a health check. Used by every lab in this track.
FROM python:3.12-alpine
ARG APP_VERSION=1.0.0
ENV APP_VERSION=${APP_VERSION} PYTHONUNBUFFERED=1
RUN adduser -D -u 10001 app
WORKDIR /srv
COPY app.py .
RUN test -s /srv/app.py        # fail the BUILD, loudly, if app.py is missing or a dangling symlink (a ConfigMap-shaped build context once produced that)
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz',timeout=2).status==200 else 1)"
CMD ["python", "app.py"]
