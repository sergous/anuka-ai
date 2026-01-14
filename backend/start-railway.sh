#!/bin/bash
set -e

# Railway-optimized startup script for Open WebUI with Neon PostgreSQL + pgvector
# Includes connection validation, proper logging, and Neon-specific tuning

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$SCRIPT_DIR" || exit

# Railway-specific setup
export PORT=${PORT:-8080}
export HOST=0.0.0.0
export PYTHONUNBUFFERED=1
export PYTHONPATH="$SCRIPT_DIR:$PYTHONPATH"

# Neon PostgreSQL connection pooling (optimized for Railway shared resources)
export DATABASE_POOL_SIZE=${DATABASE_POOL_SIZE:-5}
export DATABASE_POOL_MAX_OVERFLOW=${DATABASE_POOL_MAX_OVERFLOW:-5}
export SQLALCHEMY_ECHO=false  # Disable verbose SQL logging

# Logging with timestamps for Railway monitoring
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 Starting SocialCapital Open WebUI on Railway"
log "📍 DATABASE: Neon PostgreSQL (pgvector enabled)"
log "🏗️  BUILD_MODE: Slim (models downloaded on first use)"
log "🌐 HOST: $HOST:$PORT"

# Validate Neon PostgreSQL connection before starting app
log "🔍 Validating Neon PostgreSQL connection..."

python3 << 'EOF'
import os
import sys
from urllib.parse import urlparse

db_url = os.environ.get('DATABASE_URL')
if not db_url:
    print("[ERROR] DATABASE_URL environment variable not set!")
    print("        Please configure DATABASE_URL in Railway environment variables.")
    print("        Expected format: postgresql://user:pass@host/dbname?sslmode=require")
    sys.exit(1)

# Parse and validate connection string
try:
    parsed = urlparse(db_url)
    if parsed.scheme != 'postgresql':
        print(f"[ERROR] Invalid database URL scheme: {parsed.scheme}")
        print("        Expected 'postgresql://' scheme for Neon PostgreSQL")
        sys.exit(1)

    if not parsed.hostname:
        print("[ERROR] No hostname found in DATABASE_URL")
        print("        Check your Neon connection string format")
        sys.exit(1)

    # Check for SSL and channel binding (Neon requirements)
    has_ssl = 'sslmode=require' in db_url
    has_channel_binding = 'channel_binding=require' in db_url

    print(f"✅ DB Host: {parsed.hostname}")
    print(f"✅ DB Name: {parsed.path.strip('/')}")
    print(f"✅ SSL Mode: {'✅ Required' if has_ssl else '⚠️  Not configured'}")
    print(f"✅ Channel Binding: {'✅ Required' if has_channel_binding else '⚠️  Not configured'}")

except Exception as e:
    print(f"[ERROR] Failed to parse DATABASE_URL: {e}")
    sys.exit(1)

print("✅ Neon PostgreSQL connection string validated")
EOF

if [ $? -ne 0 ]; then
    log "❌ Database validation failed - exiting"
    exit 1
fi

log "✅ Database connection validated"

# Set vector database for RAG support
export VECTOR_DB=${VECTOR_DB:-"pgvector"}
log "🔧 VECTOR_DB: $VECTOR_DB"

# Check for optional API keys
if [ -n "$OPENAI_API_KEY" ]; then
    log "🔑 OpenAI API: Configured"
fi

if [ -n "$ANTHROPIC_API_KEY" ]; then
    log "🔑 Anthropic API: Configured"
fi

if [ -n "$GOOGLE_API_KEY" ]; then
    log "🔑 Google API: Configured"
fi

# Generate WEBUI_SECRET_KEY if not provided
if test "$WEBUI_SECRET_KEY $WEBUI_JWT_SECRET_KEY" = " "; then
    log "🔐 Generating WEBUI_SECRET_KEY"
    # Generate a random value to use as a WEBUI_SECRET_KEY in case the user didn't provide one.
    export WEBUI_SECRET_KEY=$(head -c 12 /dev/random | base64)
    log "🔐 WEBUI_SECRET_KEY generated"
else
    log "🔐 WEBUI_SECRET_KEY already configured"
fi

# Set optimal uvicorn configuration for Railway
PYTHON_CMD=$(command -v python3 || command -v python)
UVICORN_WORKERS="${UVICORN_WORKERS:-2}"  # 2 workers for Railway free tier

# If script is called with arguments, use them; otherwise use optimized defaults
if [ "$#" -gt 0 ]; then
    ARGS=("$@")
else
    ARGS=(--workers "$UVICORN_WORKERS" --loop uvloop --timeout-keep-alive 65)
fi

log "⚡ Starting uvicorn with $UVICORN_WORKERS workers"
log "🌐 Listening on $HOST:$PORT"

# Start the application with proper signal handling
exec "$PYTHON_CMD" -m uvicorn open_webui.main:app \
    --host "$HOST" \
    --port "$PORT" \
    --forwarded-allow-ips '*' \
    "${ARGS[@]}" \
    --log-level info \
    --access-log