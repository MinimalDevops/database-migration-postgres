#!/bin/bash

#set -e  # Do NOT exit immediately to allow processing all errors

#ERROR_FOUND=false  # Flag to track if any unresolved error exists

BUILD_NUMBER=${CODEBUILD_BUILD_NUMBER:-"local_run"}  # Default if not in CodePipeline
LOG_FILE="migration.log"
exec > >(tee -a "$LOG_FILE") 2>&1  # Capture all stdout/stderr

echo "Fetching all failed migrations before retry..."

# ✅ Ensure `logs` are properly quoted to prevent `read` from breaking lines incorrectly
ERROR_MIGRATIONS=$(psql -h $PGHOST -U $PGUSER -d $PGDATABASE -t -A -F"|" -c "
    SELECT migration_name
    FROM public.migrations WHERE applied_status = 'ERROR';
")

if [[ -z "$ERROR_MIGRATIONS" ]]; then
    echo "✅ No migrations in ERROR state. Nothing to retry."
    exit 0
fi

echo "✅ Migrations with ERROR status fetched."
echo ""

# Process each failed migration
echo "$ERROR_MIGRATIONS" | while IFS="|" read -r MIGRATION_NAME ; do
    MIGRATION_PATH="migrations/$MIGRATION_NAME/migration.sql"

    # 🚨 Exit pipeline if migration.sql is missing
    if [[ ! -f "$MIGRATION_PATH" ]]; then
        echo "❌ ERROR: Migration file $MIGRATION_PATH not found! Exiting pipeline."
        exit 1
    fi

    # ✅ Read the first line of migration.sql and remove carriage returns
    FIRST_LINE=$(head -n 1 "$MIGRATION_PATH" | tr -d '\r')

    # ✅ If `--skip` is found, do NOTHING ELSE (prevent extra output)
    if [[ "$FIRST_LINE" =~ ^--[[:space:]]*(SKIP|skip)$ ]]; then
        echo "⏩ Migration $MIGRATION_NAME has '--skip' directive. Skipping retry."
        continue
    fi

    # ✅ If `--retry` is found, update migration status
    if [[ "$FIRST_LINE" =~ ^--[[:space:]]*(RETRY|retry)$ ]]; then
        echo "🔄 Migration $MIGRATION_NAME has '--retry' directive. Updating status to RETRY..."
        UPDATE_QUERY="UPDATE public.migrations SET applied_status = 'RETRY' WHERE migration_name = '$MIGRATION_NAME';"
        psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "$UPDATE_QUERY"
        echo "✅ Migration $MIGRATION_NAME marked as RETRY."
        continue
    fi

    # ✅ If neither `--skip` nor `--retry` is found, print a warning
    #ERROR_FOUND=true
    echo "🚨 Migration $MIGRATION_NAME does not contain a valid directive in the first line!"
    echo "❗ Please add one of the following options in the first line of $MIGRATION_PATH:"
    echo "   - '--skip'   (to ignore retry)"
    echo "   - '--retry'  (to retry automatically)"
    
done

echo "✅ Retry Check Completed."
