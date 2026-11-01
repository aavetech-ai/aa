FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
COPY config ./config
COPY tests ./tests
COPY tools ./tools
RUN mkdir -p data
EXPOSE 8000
# Render (and most PaaS) inject $PORT and terminate TLS at the proxy, so we must
# bind to $PORT and trust X-Forwarded-* headers for correct https payment links.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
