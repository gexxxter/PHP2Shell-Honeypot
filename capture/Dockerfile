FROM python:3.12-slim
RUN useradd -u 10001 -m hp && mkdir -p /data && chown hp /data
COPY capture.py decoy.py /app/
USER hp
WORKDIR /app
CMD ["python", "-I", "capture.py"]
