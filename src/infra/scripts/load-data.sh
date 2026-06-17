#!/usr/bin/env bash
# ============================================================================
# Loads the catalog schema + seed data into the Oracle 21c instance.
# Intended to run ON the Oracle VM (via `az vm run-command invoke`).
#
# Expects these files to already exist on the VM:
#   /tmp/schema.sql
#   /tmp/seed.sql
# And these environment variables:
#   DB_SERVICE   - pluggable database / service name (e.g. ORCLPDB1)
#   DB_USER      - application schema user to create (e.g. CATALOG)
#   DB_PASSWORD  - application user password
#   SYS_PASSWORD - SYS password set when the DB was created
# ============================================================================
set -euo pipefail

: "${DB_SERVICE:?DB_SERVICE is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
# SYS_PASSWORD no longer required: this script uses local OS (sysdba) auth.

# Discover the Oracle environment from the marketplace image.
if [[ -f /etc/profile.d/oracle.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/oracle.sh || true
fi
export ORACLE_HOME="${ORACLE_HOME:-$(ls -d /u01/app/oracle/product/*/dbhome_1 /opt/oracle/product/*/dbhome_1 2>/dev/null | head -n1)}"
export ORACLE_SID="${ORACLE_SID:-ORCL}"
export PATH="$ORACLE_HOME/bin:$PATH"

# Authenticate locally with OS (sysdba) auth and switch into the PDB. This
# avoids putting the password on a connect string, where SQL*Plus would treat
# any '&' as a substitution variable. SET DEFINE OFF disables substitution so
# passwords containing '&' are applied verbatim.
echo "==> Creating application user ${DB_USER} in ${DB_SERVICE}"
sqlplus -s "/ as sysdba" <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = UPPER('${DB_USER}');
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER ${DB_USER} IDENTIFIED BY "${DB_PASSWORD}"';
  ELSE
    EXECUTE IMMEDIATE 'ALTER USER ${DB_USER} IDENTIFIED BY "${DB_PASSWORD}"';
  END IF;
END;
/
GRANT CONNECT, RESOURCE TO ${DB_USER};
ALTER USER ${DB_USER} QUOTA UNLIMITED ON USERS;
EXIT
SQL

echo "==> Applying schema.sql"
sqlplus -s "/ as sysdba" <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
ALTER SESSION SET CURRENT_SCHEMA = ${DB_USER};
@/tmp/schema.sql
EXIT
SQL

echo "==> Applying seed.sql"
sqlplus -s "/ as sysdba" <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
ALTER SESSION SET CURRENT_SCHEMA = ${DB_USER};
@/tmp/seed.sql
EXIT
SQL

echo "==> Row counts"
sqlplus -s "/ as sysdba" <<SQL
SET HEADING ON
ALTER SESSION SET CONTAINER = ${DB_SERVICE};
ALTER SESSION SET CURRENT_SCHEMA = ${DB_USER};
SELECT (SELECT COUNT(*) FROM CATEGORIES) AS categories,
       (SELECT COUNT(*) FROM PRODUCTS)   AS products
FROM DUAL;
EXIT
SQL

echo "==> Data load complete"
