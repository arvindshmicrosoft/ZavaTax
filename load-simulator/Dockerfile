# Zava Tax Load Simulator - Dockerfile
# For deployment to Azure Container Apps

FROM python:3.11-slim

# Install ODBC Driver for SQL Server
RUN apt-get update && apt-get install -y \
    curl \
    gnupg2 \
    unixodbc-dev \
    && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && curl https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code (new organized structure)
COPY oltp/ ./oltp/
COPY analytics/ ./analytics/
COPY shared/ ./shared/

# Environment variables (override at runtime)
ENV SQL_SERVER=localhost
ENV SQL_DATABASE=zavatax
ENV SQL_USE_AZURE_AD=true
ENV NUM_WORKERS=10
ENV BATCH_SIZE=1000
ENV DURATION_SECONDS=300
ENV TARGET_THROUGHPUT_MBPS=50
ENV METRICS_ENABLED=true
ENV METRICS_PORT=8000
ENV LOG_LEVEL=INFO

# Expose metrics port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/metrics || exit 1

# Run the OLTP simulator (default)
# Override with: docker run ... python -m analytics.main --connections 50
ENTRYPOINT ["python", "-m", "oltp.main"]
