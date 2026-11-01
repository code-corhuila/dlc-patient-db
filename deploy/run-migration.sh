#!/bin/sh
set -eu
case "${PG_ENVIRONMENT:-}" in
  dev|qa|prod) ;;
  *) echo "Set PG_ENVIRONMENT to dev, qa or prod" >&2; exit 2 ;;
esac
LIQUIBASE_COMMAND_PASSWORD=$(cat /run/secrets/patients_migrator_password)
: "${LIQUIBASE_COMMAND_PASSWORD:?Empty migrator secret}"
export LIQUIBASE_COMMAND_PASSWORD
exec liquibase --search-path=/workspace --changelog-file=changelog/changelog-master.yaml \
  --url="jdbc:postgresql://${PG_HOST:?}:${PG_PORT:-5432}/${PG_DATABASE:?}" \
  --username=patients_migrator --contexts="$PG_ENVIRONMENT" \
  --database-changelog-table-name=databasechangelog_patients \
  --database-changelog-lock-table-name=databasechangeloglock_patients "$@"
