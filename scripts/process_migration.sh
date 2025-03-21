#!/bin/bash

#set -e # Exit on first error

BUILD_NUMBER=${CODEBUILD_BUILD_NUMBER:-"local_run"}  # Default if not in CodePipeline
LOG_FILE="migration.log"
exec > >(tee -a "$LOG_FILE") 2>&1  # Capture all stdout/stderr

ALL_SUCCESS=true  # Flag to track if all migrations are already applied
ERROR_FOUND=false # Flag to track if any error migration exists
ERROR_LIST=()     # Array to store migrations with errors



echo "🔍 Checking for pending migrations..."

while IFS= read -r MIGRATION_NAME; do
    MIGRATION_PATH="migrations/$MIGRATION_NAME/migration.sql"

    if [[ ! -f "$MIGRATION_PATH" ]]; then
        echo "❌ ERROR: Migration file $MIGRATION_PATH not found! Exiting pipeline."
        exit 1
    fi

    # Compute checksum of migration file
    MIGRATION_CHECKSUM=$(sha256sum "$MIGRATION_PATH" | awk '{print $1}')

    # Query to check migration status
    STATUS_QUERY="SELECT applied_status FROM public.migrations WHERE migration_name = '$MIGRATION_NAME';"
    STATUS=$(psql -h $PGHOST -U $PGUSER -d $PGDATABASE -t -c "$STATUS_QUERY" | xargs)

    if [[ -z "$STATUS" ]]; then
        echo "➤ Migration $MIGRATION_NAME does not exist in table. Adding it..."
        INSERT_QUERY="INSERT INTO public.migrations (id, migration_name, applied_status, started_at) VALUES (gen_random_uuid(), '$MIGRATION_NAME', 'WAITING', NOW());"
        psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "$INSERT_QUERY"
        ALL_SUCCESS=false  # Since a new migration is found, not all are in SUCCESS state

    elif [[ "$STATUS" == "SUCCESS" ]]; then
        continue  # Don't print anything; handle at the end.

    elif [[ "$STATUS" == "RETRY" ]]; then
        echo "⏳ Migration $MIGRATION_NAME is in RETRY state."
        ALL_SUCCESS=false

    elif [[ "$STATUS" == "WAITING" ]]; then
        echo "⏳ Migration $MIGRATION_NAME is already in WAITING state."
        ALL_SUCCESS=false  # Since a migration is still in waiting, not all are in SUCCESS state

    elif [[ "$STATUS" == "ERROR" ]]; then
        # Read the first line of the migration.sql file
        FIRST_LINE=$(head -n 1 "$MIGRATION_PATH" | tr -d '\r')  # Remove carriage returns

        if [[ "$FIRST_LINE" =~ ^--[[:space:]]*(SKIP|skip)$ ]]; then
            echo "⏩ Migration $MIGRATION_NAME is in ERROR state but marked with '--skip'. Skipping."
            continue
        fi

        # If it's not marked as "--skip", follow the normal process
        ALL_SUCCESS=false
        ERROR_FOUND=true
        ERROR_LIST+=("$MIGRATION_NAME")
    fi
done < migrations_list

# 🚀 If all migrations were in SUCCESS, print a single message and exit
if [[ "$ALL_SUCCESS" == true ]]; then
    echo "✅ All migrations already applied. Stopping pipeline."
    exit 0
fi

# 🚨 If any migration is in ERROR state, fetch and print all errors before exiting
if [[ "$ERROR_FOUND" == true ]]; then
    echo "❌ Migrations with ERROR state detected. Listing all failed migrations:"
    
    ERROR_QUERY="SELECT migration_name, logs FROM public.migrations WHERE applied_status = 'ERROR';"
    psql -h $PGHOST -U $PGUSER -d $PGDATABASE -t -c "$ERROR_QUERY"

    exit 1  # Stop execution if any error migrations exist
fi