# PC Parts Depot — Azure SRE Agent demo

A read-only shopping catalog for computers and computer parts, built to
demonstrate the **Azure SRE agent**. It ships as a complete, deployable Azure
solution: an ASP.NET Core website fronted by an Application Gateway and backed
by an Oracle Database 21c instance on a private VM.

> Browsing only — there is intentionally no cart or checkout.

## Architecture

```
            Internet
               │
        ┌──────▼───────┐  Public IP
        │ App Gateway  │  (snet-appgw 10.11.0.0/24)
        └──────┬───────┘
               │ HTTPS
        ┌──────▼───────┐  App Service (.NET 8, Linux)
        │  Catalog web │  (snet-appsvc 10.11.1.0/24, VNet-integrated)
        └──────┬───────┘
               │ 1521 (private)
        ┌──────▼───────┐  Oracle Database 21c on a VM
        │   Oracle DB  │  (snet-db 10.11.2.0/24, no public IP)
        └──────────────┘
        VNet 10.11.0.0/16
```

- **VNet** `10.11.0.0/16` (reserved for later peering).
- **Application Gateway** (Standard_v2) with a public IP is the only
  internet-facing entry point; health probe hits `/healthz`.
- **App Service** runs the catalog, integrated into the VNet for private
  outbound to Oracle; inbound is restricted to the App Gateway subnet.
- **Oracle 21c VM** (Azure Marketplace image) has no public IP and only accepts
  port 1521 from the App Service subnet.

## Repository layout

| Path | Contents |
|------|----------|
| `src/app/` | ASP.NET Core 8 Razor Pages catalog website |
| `src/assets/` | `schema.sql` + `seed.sql` (demo inventory) |
| `src/infra/` | Bicep templates and the end-to-end deploy scripts |
| `tools/` | `gen_seed.py` — regenerates `seed.sql` |

## Application

The app uses `Oracle.ManagedDataAccess.Core` via an `IProductRepository`
abstraction. When **no** connection string is configured it falls back to an
in-memory repository, so you can run it locally without Oracle.

```bash
cd src/app
dotnet run
# Browse http://localhost:5275  (health: /healthz)
```

Configure Oracle access with either:

- `ConnectionStrings:Catalog` (appsettings or App Service connection string), or
- the `CATALOG_CONNECTION_STRING` environment variable.

Example connection string:

```
User Id=CATALOG;Password=<pwd>;Data Source=//10.11.2.10:1521/ORCLPDB1;
```

### Build & test

```bash
dotnet build src/app -c Release
```

## Deploy to Azure

Prerequisites: Azure CLI (logged in), .NET 8 SDK, and PowerShell 7
(`deploy.ps1`) or Bash (`deploy.sh`). Deploy into an **empty** resource group:

```powershell
cd src/infra
./deploy.ps1 -ResourceGroup rg-pcdepot-demo -Location westeurope
```

```bash
cd src/infra
./deploy.sh -g rg-pcdepot-demo -l westeurope
```

The script deploys `main.bicep`, loads the schema + seed data onto the Oracle VM
via `az vm run-command`, then builds and zip-deploys the app. It prints the
public catalog URL when finished.

### Regenerating the seed data

```bash
python tools/gen_seed.py
```

## Notes for the SRE demo

- `/healthz` returns **Unhealthy** when the database is unreachable — useful for
  triggering and diagnosing incidents with the Azure SRE agent.
- The Oracle VM, App Service connection string, and DB credentials are demo
  values. For anything beyond a throwaway demo, move credentials to Key Vault.
