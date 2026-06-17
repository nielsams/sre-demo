#!/usr/bin/env bash
# ============================================================================
# Creates the Oracle 21c database that the catalog app connects to.
#
# The Oracle marketplace image (Oracle:oracle-database:oracle_db_21) ships the
# Oracle *software* only -- it does NOT create a database instance. This script
# creates a container database (CDB) named ORCL with a single pluggable database
# (PDB) whose name matches DB_SERVICE, starts a listener on 1521, and enables
# auto-start on boot. It is idempotent: if the PDB service already exists it
# exits successfully without recreating anything.
#
# Intended to run ON the Oracle VM (via `az vm run-command invoke`) BEFORE
# load-data.sh.
#
# Required environment variables:
#   DB_SERVICE   - pluggable database / service name (e.g. ORCLPDB1)
#   DB_PASSWORD  - password for the app user (also used for the PDB admin)
#   SYS_PASSWORD - SYS / SYSTEM password to set on the new database
# Optional:
#   ORACLE_SID   - CDB SID (default ORCL)
#   TOTAL_MEMORY - MB of memory for the instance (default 8192)
# ============================================================================
set -euo pipefail

: "${DB_SERVICE:?DB_SERVICE is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
# SYS_PASSWORD is accepted for backward compatibility but no longer used:
# create-db.sh derives an alphanumeric bootstrap password and the app user is
# created via OS auth.

ORACLE_SID="${ORACLE_SID:-ORCL}"
TOTAL_MEMORY="${TOTAL_MEMORY:-8192}"

# dbca's General_Purpose template restores the seed DB via RMAN, whose password
# handling breaks on shell-special characters (& * $ ...), failing with
# ORA-01017. Derive an ALPHANUMERIC bootstrap password for SYS/SYSTEM/PDB-admin
# from DB_PASSWORD. The real (possibly special-char) password is applied to the
# CATALOG app user later by load-data.sh via OS auth, so SYS internals never
# need the special-char password and the app connection string is unchanged.
BOOT_PW="Db$(printf '%s' "${DB_PASSWORD}" | tr -cd '[:alnum:]')1A"

# Discover ORACLE_HOME for the marketplace image (installed under /u01).
export ORACLE_HOME="${ORACLE_HOME:-$(ls -d /u01/app/oracle/product/*/dbhome_1 2>/dev/null | head -n1)}"
if [[ -z "${ORACLE_HOME}" || ! -x "${ORACLE_HOME}/bin/dbca" ]]; then
  echo "ERROR: could not locate ORACLE_HOME (dbca not found)" >&2
  exit 1
fi
export ORACLE_SID
export PATH="${ORACLE_HOME}/bin:${PATH}"

# ---- Idempotency: if the service is already registered, do nothing ----------
if "${ORACLE_HOME}/bin/lsnrctl" status 2>/dev/null | grep -qi "service \"${DB_SERVICE}\""; then
  echo "==> Database service ${DB_SERVICE} already present; skipping creation."
  exit 0
fi

# ---- 1. Listener on 1521 ----------------------------------------------------
echo "==> Configuring listener"
"${ORACLE_HOME}/bin/netca" -silent -responseFile "${ORACLE_HOME}/assistants/netca/netca.rsp" || true
"${ORACLE_HOME}/bin/lsnrctl" start 2>/dev/null || true

# ---- 2. Create the CDB + PDB ------------------------------------------------
echo "==> Creating database ${ORACLE_SID} with PDB ${DB_SERVICE} (this takes ~20-40 min)"
"${ORACLE_HOME}/bin/dbca" -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbName "${ORACLE_SID}" -sid "${ORACLE_SID}" \
  -createAsContainerDatabase true \
  -numberOfPDBs 1 -pdbName "${DB_SERVICE}" \
  -pdbAdminPassword "${BOOT_PW}" \
  -sysPassword "${BOOT_PW}" \
  -systemPassword "${BOOT_PW}" \
  -characterSet AL32UTF8 \
  -memoryMgmtType AUTO_SGA \
  -totalMemory "${TOTAL_MEMORY}" \
  -emConfiguration NONE \
  -redoLogFileSize 100 \
  -storageType FS \
  -datafileDestination /u01/app/oracle/oradata \
  -ignorePreReqs

# ---- 3. Open the PDB, persist open state, register the service --------------
echo "==> Opening PDB and saving state"
"${ORACLE_HOME}/bin/sqlplus" -s "/ as sysdba" <<SQL
WHENEVER SQLERROR CONTINUE
ALTER PLUGGABLE DATABASE ${DB_SERVICE} OPEN;
ALTER PLUGGABLE DATABASE ${DB_SERVICE} SAVE STATE;
ALTER SYSTEM REGISTER;
EXIT
SQL

# ---- 4. Enable auto-start on boot ------------------------------------------
# Best-effort: requires write access to /etc/oratab. SAVE STATE above already
# ensures the PDB re-opens whenever the instance starts.
if [[ -w /etc/oratab ]]; then
  if grep -q "^${ORACLE_SID}:" /etc/oratab; then
    sed -i "s#^${ORACLE_SID}:.*#${ORACLE_SID}:${ORACLE_HOME}:Y#" /etc/oratab || true
  else
    echo "${ORACLE_SID}:${ORACLE_HOME}:Y" >> /etc/oratab || true
  fi
else
  echo "NOTE: /etc/oratab not writable by $(whoami); skipping autostart flag." >&2
fi

echo "==> Database ${ORACLE_SID} / PDB ${DB_SERVICE} created"
