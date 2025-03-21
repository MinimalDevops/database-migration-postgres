#!/bin/bash

LOG_FILE="migration.log"
BUILD_NUMBER=${CODEBUILD_BUILD_NUMBER:-"local_run"}  # Default if not in CodePipeline
STATUS=${1:-"NOT AVAILABLE"}  # Use passed status, default to FAILURE if not provided

# Escape single quotes in logs for PostgreSQL
LOG_CONTENT=$(sed "s/'/''/g" "$LOG_FILE")

echo "📌 Storing logs for build: $BUILD_NUMBER (Final Status: $STATUS)..."

# Insert if not exists, otherwise update logs
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "
INSERT INTO migration_logs (build_number, timestamp, logs, status) 
VALUES ('$BUILD_NUMBER', NOW(), '$LOG_CONTENT', '$STATUS')
ON CONFLICT (build_number) DO UPDATE 
SET logs = migration_logs.logs || E'\n' || '$LOG_CONTENT',
    status = '$STATUS',
    timestamp = NOW();"

echo "✅ Migration logs stored successfully."