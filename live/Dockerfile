FROM python:3.12-slim
RUN useradd -u 10002 -m live
COPY live.py index.html /app/
USER live
WORKDIR /app
CMD ["python", "-I", "live.py"]
