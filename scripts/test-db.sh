#!/usr/bin/env bash
# Builds a disposable database from the migrations, in the order they were
# applied to production, then runs every SQL integration test.
# Usage: scripts/test-db.sh   (uses the standard PG* environment variables)
# NEVER point this at a real project: it creates and drops the database named below.
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${TEST_DATABASE:-family_funnies_test}"
run() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
run -d postgres -c "drop database if exists \"$DB\"" -c "create database \"$DB\""
run -d postgres -c "do \$\$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end \$\$"
run -d "$DB" -f tests/support/supabase-stand-in.sql
for migration in foundation invitations production production-media public-launch-permissions \
  instant-verified-access family-management trash-purge usage-caps; do
  echo "migrate: $migration"
  run -d "$DB" -f "database/$migration.sql" >/dev/null
done
for t in tests/*.sql; do
  echo "test: $t"
  run -d "$DB" -f "$t" >/dev/null
done
echo "All database tests passed."
