#!/usr/bin/env bash
# ============================================================================
# End-to-end deployment of the PC Parts Depot SRE demo into an empty RG.
#   1. Create the resource group.
#   2. Deploy main.bicep (VNet, Oracle VM, App Service, App Gateway).
#   3. Load schema.sql + seed.sql via `az vm run-command`.
#   4. Build, publish and zip-deploy the .NET app.
#   5. Print the public catalog URL.
#
# Usage:
#   ./deploy.sh -g rg-pcdepot-demo -l westeurope
# The password is read interactively unless provided via the PASSWORD env var.
# A single password is reused for the VM admin, Oracle SYS, and app DB user.
# ============================================================================
set -euo pipefail

RESOURCE_GROUP=""
LOCATION=""
NAME_PREFIX="pcdepot"
VM_ADMIN_USERNAME="azureuser"
DB_USER="CATALOG"
DB_SERVICE_NAME="ORCLPDB1"

usage() { echo "Usage: $0 -g <resource-group> -l <location> [-p <name-prefix>]"; exit 1; }

while getopts "g:l:p:h" opt; do
  case "$opt" in
    g) RESOURCE_GROUP="$OPTARG" ;;
    l) LOCATION="$OPTARG" ;;
    p) NAME_PREFIX="$OPTARG" ;;
    *) usage ;;
  esac
done
[[ -z "$RESOURCE_GROUP" || -z "$LOCATION" ]] && usage

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
APP_DIR="$REPO_ROOT/src/app"
ASSETS_DIR="$REPO_ROOT/src/assets"

prompt_secret() { local var="$1" label="$2"; if [[ -z "${!var:-}" ]]; then read -rsp "$label: " "$var"; echo; fi; }
# One password is reused for every credential (VM admin, Oracle SYS, app DB user).
prompt_secret PASSWORD "Password (used for the VM admin, Oracle SYS, and the app DB user)"
VM_ADMIN_PASSWORD="$PASSWORD"
DB_PASSWORD="$PASSWORD"
SYS_PASSWORD="$PASSWORD"

echo "==> Ensuring resource group '$RESOURCE_GROUP' in '$LOCATION'"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

echo "==> Deploying infrastructure (main.bicep)"
DEPLOYMENT_NAME="pcdepot-$(date +%Y%m%d%H%M%S)"

# Pass parameters via a temp JSON file rather than inline key=value, so complex
# passwords are never altered by shell quoting/expansion. Written with a
# restrictive umask and removed on exit.
PARAMS_FILE="$(mktemp)"
cleanup() { rm -f "$PARAMS_FILE"; }
trap cleanup EXIT
( umask 077
  NAME_PREFIX="$NAME_PREFIX" LOCATION="$LOCATION" VM_ADMIN_USERNAME="$VM_ADMIN_USERNAME" \
  VM_ADMIN_PASSWORD="$VM_ADMIN_PASSWORD" DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" \
  DB_SERVICE_NAME="$DB_SERVICE_NAME" python3 - "$PARAMS_FILE" <<'PY'
import json, os, sys
params = {
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "namePrefix":      {"value": os.environ["NAME_PREFIX"]},
        "location":        {"value": os.environ["LOCATION"]},
        "vmAdminUsername": {"value": os.environ["VM_ADMIN_USERNAME"]},
        "vmAdminPassword": {"value": os.environ["VM_ADMIN_PASSWORD"]},
        "dbUser":          {"value": os.environ["DB_USER"]},
        "dbPassword":      {"value": os.environ["DB_PASSWORD"]},
        "dbServiceName":   {"value": os.environ["DB_SERVICE_NAME"]},
    },
}
with open(sys.argv[1], "w") as f:
    json.dump(params, f)
PY
)
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$HERE/main.bicep" \
  --parameters "@$PARAMS_FILE" \
  --output none
rm -f "$PARAMS_FILE"

OUTPUTS=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" --query properties.outputs -o json)
WEBAPP_NAME=$(echo "$OUTPUTS" | python3 -c "import sys,json;print(json.load(sys.stdin)['webAppName']['value'])")
ORACLE_VM_NAME=$(echo "$OUTPUTS" | python3 -c "import sys,json;print(json.load(sys.stdin)['oracleVmName']['value'])")
SITE_URL=$(echo "$OUTPUTS" | python3 -c "import sys,json;print(json.load(sys.stdin)['siteUrl']['value'])")

echo "    Web app:    $WEBAPP_NAME"
echo "    Oracle VM:  $ORACLE_VM_NAME"
echo "    Public URL: $SITE_URL"

# A deallocated/stopped VM (e.g. from a previous run that was shut down to save
# cost) would make the run-command below fail. Start any VM in the RG that is
# not already running before continuing.
echo "==> Ensuring all VMs are running"
STOPPED_VMS=$(az vm list -g "$RESOURCE_GROUP" --show-details --query "[?powerState!='VM running'].name" -o tsv)
if [[ -n "$STOPPED_VMS" ]]; then
  while IFS= read -r vm; do
    [[ -z "$vm" ]] && continue
    echo "    Starting VM '$vm'..."
    az vm start -g "$RESOURCE_GROUP" -n "$vm" --output none
  done <<< "$STOPPED_VMS"
fi

echo "==> Creating Oracle database + loading schema/seed data"
SCHEMA_B64=$(base64 -w0 "$ASSETS_DIR/schema.sql")
SEED_B64=$(base64 -w0 "$ASSETS_DIR/seed.sql")
CREATE_B64=$(base64 -w0 "$HERE/scripts/create-db.sh")
LOAD_B64=$(base64 -w0 "$HERE/scripts/load-data.sh")
AUTOSTART_B64=$(base64 -w0 "$HERE/scripts/enable-db-autostart.sh")

# Base64-encode the secrets so no shell-special characters appear in the script.
DB_PWD_B64=$(printf '%s' "$DB_PASSWORD" | base64 -w0)
SYS_PWD_B64=$(printf '%s' "$SYS_PASSWORD" | base64 -w0)

# create-db.sh creates the CDB/PDB (the marketplace image has no database) and
# is idempotent; dbca takes ~20-40 min. Both steps run in one run-command and
# execute as the oracle user (required for dbca and OS-auth sqlplus).
REMOTE_SCRIPT=$(cat <<EOF
set -e
echo '$SCHEMA_B64' | base64 -d > /tmp/schema.sql
echo '$SEED_B64'   | base64 -d > /tmp/seed.sql
echo '$CREATE_B64' | base64 -d > /tmp/create-db.sh
echo '$LOAD_B64'   | base64 -d > /tmp/load-data.sh
echo '$AUTOSTART_B64' | base64 -d > /tmp/enable-db-autostart.sh
chmod +x /tmp/create-db.sh /tmp/load-data.sh /tmp/enable-db-autostart.sh
chown oracle:oinstall /tmp/create-db.sh /tmp/load-data.sh /tmp/schema.sql /tmp/seed.sql
DB_SERVICE='$DB_SERVICE_NAME'
DB_USER='$DB_USER'
DB_PASSWORD="\$(echo '$DB_PWD_B64' | base64 -d)"
SYS_PASSWORD="\$(echo '$SYS_PWD_B64' | base64 -d)"
firewall-cmd --permanent --add-port=1521/tcp 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true
run_as_oracle() {
  sudo -u oracle DB_SERVICE="\$DB_SERVICE" DB_USER="\$DB_USER" DB_PASSWORD="\$DB_PASSWORD" SYS_PASSWORD="\$SYS_PASSWORD" bash "\$1"
}
run_as_oracle /tmp/create-db.sh
run_as_oracle /tmp/load-data.sh
# Install the boot-time auto-start unit as root (the marketplace image starts the
# listener on boot but not the DB instance). Runs after the DB exists.
bash /tmp/enable-db-autostart.sh
EOF
)

SCRIPT_FILE="$(mktemp)"
trap 'rm -f "$SCRIPT_FILE"' EXIT
printf '%s' "$REMOTE_SCRIPT" > "$SCRIPT_FILE"
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ORACLE_VM_NAME" \
  --command-id RunShellScript \
  --scripts "@$SCRIPT_FILE" \
  --output table
rm -f "$SCRIPT_FILE"

echo "==> Building and publishing the application"
PUBLISH_DIR="$APP_DIR/publish"
ZIP_PATH="$APP_DIR/app.zip"
rm -rf "$PUBLISH_DIR" "$ZIP_PATH"
dotnet publish "$APP_DIR" -c Release -o "$PUBLISH_DIR"
(cd "$PUBLISH_DIR" && zip -qr "$ZIP_PATH" .)

echo "==> Deploying application to App Service"
az webapp deploy \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEBAPP_NAME" \
  --src-path "$ZIP_PATH" \
  --type zip \
  --output none

echo ""
echo "Deployment complete. Catalog is available at: $SITE_URL"
echo "(Allow a few minutes for the App Gateway backend health probe to pass.)"
