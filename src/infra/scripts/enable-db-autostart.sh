#!/usr/bin/env bash
# ============================================================================
# Installs a systemd unit that auto-starts the Oracle instance on boot.
#
# The Oracle marketplace image auto-starts the *listener* on boot but NOT the
# database instance. After a VM reboot/deallocate-start the listener comes up
# with "no services" until the instance is started, so the app gets ORA-12514
# and the App Gateway backend goes unhealthy (HTTP 503). This unit runs Oracle's
# dbstart at boot (and dbshut on shutdown); combined with the oratab "Y" flag and
# the PDB saved-open state, the database and its PDB come back automatically.
#
# Intended to run ON the Oracle VM as ROOT (via `az vm run-command invoke`),
# after create-db.sh has created the database. Idempotent.
#
# Optional environment variables:
#   ORACLE_HOME - Oracle home (auto-detected under /u01 if unset)
#   ORACLE_SID  - CDB SID (auto-detected from /etc/oratab, default ORCL)
# ============================================================================
set -euo pipefail

ORACLE_HOME="${ORACLE_HOME:-$(ls -d /u01/app/oracle/product/*/dbhome_1 2>/dev/null | head -n1)}"
ORACLE_SID="${ORACLE_SID:-$(grep -E '^[A-Za-z0-9_]+:' /etc/oratab 2>/dev/null | grep -v '^#' | head -1 | cut -d: -f1)}"
ORACLE_SID="${ORACLE_SID:-ORCL}"

if [[ -z "${ORACLE_HOME}" ]]; then
  echo "ERROR: could not locate ORACLE_HOME under /u01" >&2
  exit 1
fi

# Ensure the oratab auto-start flag is set so dbstart knows to start this SID.
if [[ -f /etc/oratab ]]; then
  if grep -q "^${ORACLE_SID}:" /etc/oratab; then
    sed -i "s#^${ORACLE_SID}:.*#${ORACLE_SID}:${ORACLE_HOME}:Y#" /etc/oratab || true
  else
    echo "${ORACLE_SID}:${ORACLE_HOME}:Y" >> /etc/oratab || true
  fi
fi

cat > /etc/systemd/system/oracle-db.service <<UNIT
[Unit]
Description=Oracle Database (dbstart/dbshut)
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=oracle
Group=oinstall
Environment=ORACLE_HOME=${ORACLE_HOME}
Environment=ORACLE_SID=${ORACLE_SID}
ExecStart=${ORACLE_HOME}/bin/dbstart ${ORACLE_HOME}
ExecStop=${ORACLE_HOME}/bin/dbshut ${ORACLE_HOME}

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable oracle-db.service

echo "==> oracle-db.service enabled (SID=${ORACLE_SID} HOME=${ORACLE_HOME})"
