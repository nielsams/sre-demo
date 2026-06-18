#requires -Version 7.0
<#
.SYNOPSIS
    End-to-end deployment of the PC Parts Depot SRE demo into an empty resource group.

.DESCRIPTION
    1. Creates the resource group (if needed).
    2. Deploys all infrastructure from main.bicep (VNet, Oracle VM, App Service, App Gateway).
    3. Loads schema.sql + seed.sql into the Oracle database via `az vm run-command`.
    4. Builds, publishes and zip-deploys the .NET app to the App Service.
    5. Prints the public catalog URL.

.EXAMPLE
    ./deploy.ps1 -ResourceGroup rg-pcdepot-demo -Location westeurope
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $Location,
    [string] $NamePrefix = 'pcdepot',
    [string] $VmAdminUsername = 'azureuser',
    [string] $DbUser = 'CATALOG',
    [securestring] $Password = (Read-Host -AsSecureString -Prompt 'Password (used for the VM admin, Oracle SYS, and the app DB user)'),
    [string] $DbServiceName = 'ORCLPDB1'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Resolve-Path (Join-Path $here '..' '..')
$appDir = Join-Path $repoRoot 'src/app'
$assetsDir = Join-Path $repoRoot 'src/assets'

function ConvertFrom-SecureStringPlain([securestring] $s) {
    [System.Net.NetworkCredential]::new('', $s).Password
}

# One password is reused for every credential (VM admin, Oracle SYS, app DB user).
$plainPwd = ConvertFrom-SecureStringPlain $Password
$vmPwd = $plainPwd
$dbPwd = $plainPwd
$sysPwd = $plainPwd

Write-Host "==> Ensuring resource group '$ResourceGroup' in '$Location'" -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none

Write-Host '==> Deploying infrastructure (main.bicep)' -ForegroundColor Cyan
$deploymentName = "pcdepot-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Pass parameters via a temp JSON file rather than inline `key=value`. Inline
# values are mangled by the az.cmd batch wrapper on Windows when they contain
# shell-special characters (& % ^ | < >), which corrupts complex passwords.
$paramsFile = Join-Path ([IO.Path]::GetTempPath()) "pcdepot-params-$([guid]::NewGuid()).json"
$paramsObject = @{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters     = @{
        namePrefix      = @{ value = $NamePrefix }
        location        = @{ value = $Location }
        vmAdminUsername = @{ value = $VmAdminUsername }
        vmAdminPassword = @{ value = $vmPwd }
        dbUser          = @{ value = $DbUser }
        dbPassword      = @{ value = $dbPwd }
        dbServiceName   = @{ value = $DbServiceName }
    }
}
try {
    $paramsObject | ConvertTo-Json -Depth 5 | Set-Content -Path $paramsFile -Encoding utf8
    az deployment group create `
        --resource-group $ResourceGroup `
        --name $deploymentName `
        --template-file (Join-Path $here 'main.bicep') `
        --parameters "@$paramsFile" `
        --output none
}
finally {
    Remove-Item $paramsFile -Force -ErrorAction SilentlyContinue
}

$outputs = az deployment group show --resource-group $ResourceGroup --name $deploymentName --query properties.outputs --output json | ConvertFrom-Json
$webAppName = $outputs.webAppName.value
$oracleVmName = $outputs.oracleVmName.value
$siteUrl = $outputs.siteUrl.value

Write-Host "    Web app:    $webAppName"
Write-Host "    Oracle VM:  $oracleVmName"
Write-Host "    Public URL: $siteUrl"

# A deallocated/stopped VM (e.g. from a previous run that was shut down to save
# cost) would make the run-command below fail. Start any VM in the RG that is
# not already running before continuing.
Write-Host '==> Ensuring all VMs are running' -ForegroundColor Cyan
$stoppedVms = az vm list --resource-group $ResourceGroup --show-details --query "[?powerState!='VM running'].name" --output tsv
foreach ($vm in ($stoppedVms -split "`n" | Where-Object { $_.Trim() -ne '' })) {
    $vm = $vm.Trim()
    Write-Host "    Starting VM '$vm'..."
    az vm start --resource-group $ResourceGroup --name $vm --output none
}

Write-Host '==> Creating Oracle database + loading schema/seed data' -ForegroundColor Cyan
$schemaB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $assetsDir 'schema.sql')))
$seedB64   = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $assetsDir 'seed.sql')))
$createB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $here 'scripts/create-db.sh')))
$loadB64   = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $here 'scripts/load-data.sh')))
$autostartB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $here 'scripts/enable-db-autostart.sh')))

# Base64-encode the secrets too, so no shell-special characters appear anywhere
# in the script text (base64 is [A-Za-z0-9+/=] only). Decoded on the VM.
$dbPwdB64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dbPwd))
$sysPwdB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sysPwd))

# Creating the database with dbca takes ~20-40 minutes; create-db.sh is
# idempotent so re-runs are cheap. Both steps run in one run-command so the
# load happens immediately after the database is ready.
$remoteScript = @"
set -e
echo '$schemaB64' | base64 -d > /tmp/schema.sql
echo '$seedB64'   | base64 -d > /tmp/seed.sql
echo '$createB64' | base64 -d > /tmp/create-db.sh
echo '$loadB64'   | base64 -d > /tmp/load-data.sh
echo '$autostartB64' | base64 -d > /tmp/enable-db-autostart.sh
chmod +x /tmp/create-db.sh /tmp/load-data.sh /tmp/enable-db-autostart.sh
export DB_SERVICE='$DbServiceName'
export DB_USER='$DbUser'
export DB_PASSWORD="`$(echo '$dbPwdB64' | base64 -d)"
export SYS_PASSWORD="`$(echo '$sysPwdB64' | base64 -d)"
chown oracle:oinstall /tmp/create-db.sh /tmp/load-data.sh /tmp/schema.sql /tmp/seed.sql
# The marketplace image runs firewalld; open the Oracle port so the App Service
# subnet can reach the listener (the Azure NSG alone is not sufficient).
firewall-cmd --permanent --add-port=1521/tcp 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true
run_as_oracle() {
  sudo -u oracle DB_SERVICE="`$DB_SERVICE" DB_USER="`$DB_USER" DB_PASSWORD="`$DB_PASSWORD" SYS_PASSWORD="`$SYS_PASSWORD" bash "`$1"
}
run_as_oracle /tmp/create-db.sh
run_as_oracle /tmp/load-data.sh
# Install the boot-time auto-start unit as root (the marketplace image starts the
# listener on boot but not the DB instance). Runs after the DB exists.
bash /tmp/enable-db-autostart.sh
"@

# Pass the script via a temp file (@file) to avoid az.cmd batch-wrapper mangling.
$scriptFile = Join-Path ([IO.Path]::GetTempPath()) "pcdepot-load-$([guid]::NewGuid()).sh"
try {
    # Write with LF endings; the script runs on Linux.
    [IO.File]::WriteAllText($scriptFile, ($remoteScript -replace "`r`n", "`n"))
    az vm run-command invoke `
        --resource-group $ResourceGroup `
        --name $oracleVmName `
        --command-id RunShellScript `
        --scripts "@$scriptFile" `
        --output table
}
finally {
    Remove-Item $scriptFile -Force -ErrorAction SilentlyContinue
}

Write-Host '==> Building and publishing the application' -ForegroundColor Cyan
$publishDir = Join-Path $appDir 'publish'
$zipPath = Join-Path $appDir 'app.zip'
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

dotnet publish $appDir -c Release -o $publishDir
Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zipPath -Force

Write-Host '==> Deploying application to App Service' -ForegroundColor Cyan
az webapp deploy `
    --resource-group $ResourceGroup `
    --name $webAppName `
    --src-path $zipPath `
    --type zip `
    --output none

Write-Host ''
Write-Host "Deployment complete. Catalog is available at: $siteUrl" -ForegroundColor Green
Write-Host '(Allow a few minutes for the App Gateway backend health probe to pass.)'
