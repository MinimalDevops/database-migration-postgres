# PostgreSQL Database Migration Tool

## Overview
This repository provides an automated migration solution for PostgreSQL databases using AWS CodePipeline. The tool streamlines the process of deploying database changes, including SQL queries and stored procedures, by integrating CI/CD practices.

## Key Features
- **Automated Migrations:** Uses AWS CodePipeline to manage and execute database migrations.
- **Retry and Skip Mechanisms:** Handles failed migrations with retry options and allows skipping problematic migrations.
- **Logging:** Centralized logging of migration results and pipeline statuses.
- **Rollback Support:** Ensures that failed migrations can be retried or skipped without manual intervention.
- **Environment Agnostic:** Works seamlessly with multiple environments (DEV, QA, PROD).

---

## Prerequisites

### Environment Variables for Logging
The tool relies on an environment variable to capture the build number. When running through AWS CodePipeline, it uses the following environment variable:
- `CODEBUILD_BUILD_NUMBER`: Build number set automatically by AWS CodeBuild.

If you are using a different CI/CD tool or automation platform, you may need to define a similar environment variable to ensure logs are stored correctly.

Example:
- For Jenkins, you might use `BUILD_ID` or `BUILD_NUMBER`.
- For GitLab CI/CD, you could use `CI_JOB_ID`.

The tool gracefully handles cases where the build number is not set by defaulting to `local_run` if the environment variable is missing.
- AWS CodePipeline and CodeBuild set up.
- PostgreSQL database instance running and accessible.
- AWS Secrets Manager configured with database credentials.

### Environment Variables
The following environment variables must be set during pipeline execution:
- `PGHOST`: Database host (fetched from Secrets Manager).
- `PGUSER`: Database user (fetched from Secrets Manager).
- `PGDATABASE`: Database name (default: `postgres`).
- `PGPASSWORD`: Database password (fetched from Secrets Manager).
- `PGPORT`: Database port (fetched from Secrets Manager).

---

## Migration Table Structures
### Migration Metadata Table
Tracks individual migration statuses and timestamps.
```sql
CREATE TABLE public.migrations (
    id varchar(36) NOT NULL,
    finished_at timestamptz NULL,
    migration_name varchar(255) NOT NULL,
    logs text NULL,
    rolled_back_at timestamptz NULL,
    started_at timestamptz NOT NULL DEFAULT now(),
    applied_status text NOT NULL,
    PRIMARY KEY (id)
);
```

### Migration Logs Table
Logs build number, status, and detailed execution logs.
```sql
CREATE TABLE IF NOT EXISTS migration_logs (
    id SERIAL PRIMARY KEY,
    build_number TEXT UNIQUE NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    logs TEXT NOT NULL,
    status TEXT CHECK (status IN ('SUCCESS', 'FAILURE'))
);
```

---

## Migration Scripts
### disable_yum_priorities.sh
- Disables `yum` priority protection to ensure smooth package updates.

### log_migration.sh
- Logs build number, timestamp, logs, and status to the migration logs table.

### process_migration.sh
- Processes migration files and validates their format and transaction safety.

### retry_migration.sh
- Identifies and retries failed migrations automatically if configured.

### apply_migration.sh
- Applies migrations to the target database in a prioritized order.

---

## Build Specification (buildspec.yaml)
The build specification file defines the pipeline steps, as described below:

### Install Phase
- Installs necessary packages (PostgreSQL, AWS CLI, and nc).
- Disables `yum` priority protection.

### Pre-Build Phase
- Fetches database credentials from AWS Secrets Manager.
- Checks database reachability using `nc`.

### Build Phase
- Runs `retry_migration.sh` to handle failed migrations.
- Generates a list of pending migrations.
- Processes and applies migrations using `process_migration.sh` and `apply_migration.sh`.

### Post-Build Phase
- Logs migration success or failure using `log_migration.sh`.

#### Example buildspec.yaml
```yaml
version: 0.2
phases:
  install:
    runtime-versions:
      python: 3.9
  pre_build:
    commands:
      - scripts/disable_yum_priorities.sh
      - yum update -y
      - yum install -y postgresql15 awscli-2 nc
  build:
    commands:
      - scripts/retry_migration.sh
      - scripts/process_migration.sh
      - scripts/apply_migration.sh || EXIT_CODE=$?
  post_build:
    commands:
      - if [ -z "$EXIT_CODE" ]; then EXIT_CODE=0; fi
      - if [ "$EXIT_CODE" -eq 0 ]; then ./scripts/log_migration.sh "SUCCESS"; else ./scripts/log_migration.sh "FAILURE"; fi
```

---

## Best Practices
- Use **transactions** (`BEGIN; ... COMMIT;`) in every migration.
- Follow consistent **naming conventions** for migration files.
- Avoid combining multiple database operations into a single migration.
- Use **--retry** or **--skip** as appropriate to manage problematic migrations.

---

## Troubleshooting
### Common Issues
- **Database Connection Failure:** Check the credentials and network settings.
- **Migration Error:** Review migration logs and ensure scripts are valid SQL.
- **Permission Denied:** Verify IAM role and permissions for Secrets Manager.

---

## License
MIT License

For more details, feel free to open an issue or contact the maintainers.

