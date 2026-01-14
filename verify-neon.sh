#!/bin/bash
# Neon PostgreSQL + pgvector Connection Verification Script
# Run this locally to test your Neon setup before deploying to Railway

set -e

echo "🔍 Verifying Neon PostgreSQL + pgvector connection..."
echo "=================================================="

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    echo "❌ DATABASE_URL environment variable not set!"
    echo "   Please set it to your Neon connection string:"
    echo "   export DATABASE_URL='postgresql://user:pass@host/dbname?sslmode=require&channel_binding=require'"
    exit 1
fi

echo "✅ DATABASE_URL is set"

# Test basic connection with Python
echo ""
echo "🔌 Testing database connection..."
python3 << 'EOF'
import os
import sys
from urllib.parse import urlparse

try:
    from sqlalchemy import create_engine, text
    from sqlalchemy.exc import SQLAlchemyError
except ImportError:
    print("❌ SQLAlchemy not installed. Install with: pip install sqlalchemy psycopg2-binary")
    sys.exit(1)

db_url = os.environ.get('DATABASE_URL')
if not db_url:
    print("❌ DATABASE_URL not found")
    sys.exit(1)

print(f"📍 Connecting to: {db_url[:50]}...")

try:
    # Create engine
    engine = create_engine(db_url, connect_args={"connect_timeout": 10})

    # Test connection
    with engine.connect() as conn:
        result = conn.execute(text("SELECT version()"))
        version = result.fetchone()[0]
        print("✅ Connection successful!"        print(f"📊 PostgreSQL version: {version.split(' ')[1]}")

        # Test pgvector extension
        result = conn.execute(text("SELECT * FROM pg_extension WHERE extname = 'vector'"))
        if result.fetchone():
            print("✅ pgvector extension: INSTALLED")
        else:
            print("⚠️  pgvector extension: NOT FOUND")
            print("   Run in Neon console: CREATE EXTENSION IF NOT EXISTS vector;")

        # Test basic table creation (if it doesn't exist)
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS test_connection (
                id SERIAL PRIMARY KEY,
                data TEXT,
                embedding vector(384)
            )
        """))
        conn.commit()
        print("✅ Test table creation: SUCCESS")

        # Clean up
        conn.execute(text("DROP TABLE IF EXISTS test_connection"))
        conn.commit()
        print("✅ Test table cleanup: SUCCESS")

except SQLAlchemyError as e:
    print(f"❌ Database connection failed: {e}")
    print("💡 Common issues:")
    print("   - Check DATABASE_URL format")
    print("   - Verify Neon database is active")
    print("   - Ensure SSL parameters are correct")
    print("   - Check firewall/network settings")
    sys.exit(1)
except Exception as e:
    print(f"❌ Unexpected error: {e}")
    sys.exit(1)

print("")
print("🎉 All database tests passed!")
print("   Your Neon PostgreSQL + pgvector setup is ready for Railway deployment.")
EOF

echo ""
echo "📋 Next Steps:"
echo "1. If pgvector extension is missing, run in Neon console:"
echo "   CREATE EXTENSION IF NOT EXISTS vector;"
echo "2. Copy .env.railway variables to Railway dashboard"
echo "3. Deploy using: railway up --service YOUR_SERVICE_ID"
echo "4. Monitor logs for startup progress"