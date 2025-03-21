#!/bin/bash

#set -e  # Do NOT exit immediately to allow logging failures

BUILD_NUMBER=${CODEBUILD_BUILD_NUMBER:-"local_run"}  # Default if not in CodePipeline
LOG_FILE="migration.log"
exec > >(tee -a "$LOG_FILE") 2>&1  # Capture all stdout/stderr

echo "🔍 Fetching migrations in order: RETRY first, then WAITING..."

# Fetch all migrations with "RETRY" first, then "WAITING"
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -t -A -F"," -c "
SELECT migration_name FROM public.migrations 
WHERE applied_status IN ('RETRY', 'WAITING') 
ORDER BY CASE applied_status 
            WHEN 'RETRY' THEN 1 
            WHEN 'WAITING' THEN 2 
         END, started_at;" > /tmp/migrations_ordered

echo "✅ Migrations fetched in priority order:"
cat /tmp/migrations_ordered

# Function to extract MSSDATABASE from the last line of migration.sql
extract_mssdatabase() {
    local MIGRATION_PATH="$1"

    # Read the last line of the file
    LAST_LINE=$(tail -n 1 "$MIGRATION_PATH" | tr -d '\r')

    # Check if it starts with "--MSSDATABASE="
    if [[ "$LAST_LINE" == --MSSDATABASE=* ]]; then
        MSSDATABASE="${LAST_LINE#--MSSDATABASE=}"
        echo "✅ Extracted MSSDATABASE: $MSSDATABASE"
    else
        echo "❌ ERROR: MSSDATABASE not specified in migration.sql for $MIGRATION_NAME. Marking as ERROR." >&2
        
        UPDATE_ERROR_QUERY="
            UPDATE public.migrations 
            SET applied_status = 'ERROR', 
                logs = 'Missing --MSSDATABASE in migration.sql' 
            WHERE migration_name = '$MIGRATION_NAME';"
        
        psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "$UPDATE_ERROR_QUERY"
        exit 1  # Fail immediately
    fi
}

# Function to validate transaction safety and MSSDATABASE presence
validate_migration() {
    local MIGRATION_NAME="$1"
    local MIGRATION_PATH="migrations/$MIGRATION_NAME/migration.sql"

    echo "🔍 Validating migration: $MIGRATION_NAME"

    if [[ ! -f "$MIGRATION_PATH" ]]; then
        echo "❌ ERROR: Migration file $MIGRATION_PATH not found! Exiting pipeline." >&2
        exit 1
    fi

    # Extract MSSDATABASE and print it
    extract_mssdatabase "$MIGRATION_PATH"
    
    # Read first, second, and second-last lines
    FIRST_LINE=$(sed -n '1p' "$MIGRATION_PATH" | tr -d '\r')
    SECOND_LINE=$(sed -n '2p' "$MIGRATION_PATH" | tr -d '\r')
    SECOND_LAST_LINE=$(tail -n 2 "$MIGRATION_PATH" | head -n 1 | tr -d '\r')

    # Ensure "BEGIN" in first or second line and "COMMIT" in second-last line
    if [[ "$FIRST_LINE" != "BEGIN;" && "$SECOND_LINE" != "BEGIN;" ]] || [[ "$SECOND_LAST_LINE" != "COMMIT;" ]]; then
        echo "❌ ERROR: Migration $MIGRATION_NAME does not use transactions! Marking as ERROR." >&2
        UPDATE_ERROR_QUERY="
            UPDATE public.migrations 
            SET applied_status = 'ERROR', 
                logs = 'Non-transaction based migration.sql not allowed' 
            WHERE migration_name = '$MIGRATION_NAME';"
        psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "$UPDATE_ERROR_QUERY"
        exit 1
    fi

    echo "✅ Migration $MIGRATION_NAME passed transaction and database validation."
}

# Apply migrations in the determined order
while IFS= read -r MIGRATION_NAME; do
    echo "📌 Processing migration: $MIGRATION_NAME"

    MIGRATION_PATH=$(find migrations/ -type d -name "$MIGRATION_NAME" -exec find {} -name "migration.sql" \;)

    # Perform validation before applying the migration
    validate_migration "$MIGRATION_NAME"

    echo "⏳ Applying migration: $MIGRATION_NAME"

    LAST_LINE=$(tail -n 1 "$MIGRATION_PATH" | tr -d '\r')
    MSSDATABASE="${LAST_LINE#--MSSDATABASE=}"

    # Update migration start time in public.migrations (Uses default PGDATABASE)
    UPDATE_START="UPDATE public.migrations SET started_at = NOW() WHERE migration_name = '$MIGRATION_NAME';"
    psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "$UPDATE_START"

    # Apply migration inside a transaction using MSSDATABASE
    ERROR_LOG=$(psql -h $PGHOST -U $PGUSER -d $MSSDATABASE -v ON_ERROR_STOP=1 -f "$MIGRATION_PATH" 2>&1)

    if [[ $? -eq 0 ]]; then
        echo "✅ Migration applied successfully: $MIGRATION_NAME"

        UPDATE_SUCCESS="UPDATE public.migrations 
                        SET applied_status = 'SUCCESS', finished_at = NOW(), logs = NULL 
                        WHERE migration_name = '$MIGRATION_NAME';"
        psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "$UPDATE_SUCCESS"

    else
        echo "❌ Error applying migration: $MIGRATION_NAME"
        echo "Error details: $ERROR_LOG" >&2
        
        UPDATE_ERROR_LOGS="UPDATE public.migrations SET applied_status = 'ERROR', logs = '$ERROR_LOG' WHERE migration_name = '$MIGRATION_NAME';"
        psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "$UPDATE_ERROR_LOGS"
        exit 1  # Stop execution on failure
    fi
done < /tmp/migrations_ordered

echo "✅ All applicable migrations have been processed."