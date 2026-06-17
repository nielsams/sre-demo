# Copilot instructions for sre-demo-application

## Project purpose

This is a **demo application built to showcase the Azure SRE agent**. It is a
read-only shopping catalog for computers and computer parts (browsing only — no
cart or checkout). The catalog should be seeded with a realistic sample
inventory. See `idea.md` for the original brief and `README.md` for the full
architecture and deploy instructions.

## Build & run

```bash
dotnet build src/app -c Release      # build
dotnet run --project src/app         # run locally on http://localhost:5275
python tools/gen_seed.py             # regenerate src/assets/seed.sql
az bicep build --file src/infra/main.bicep   # validate infra
```

There is no test project yet, and the repo is **not** a git repository.

## Tech stack

- **App:** ASP.NET Core 8 (C#), server-rendered Razor Pages / MVC — browsing only.
- **Data access:** `Oracle.ManagedDataAccess.Core` (managed driver, no Oracle client install).
- **Hosting:** Azure App Service (Linux, .NET 8), VNet-integrated.
- **IaC:** Bicep (`src/infra`) deployed via a single end-to-end script into an empty RG.

## Repository layout

The directory structure is intentional — keep new files in the right place:

- `src/app/` — ASP.NET Core 8 Razor Pages catalog website.
- `src/infra/` — Bicep (`main.bicep` + `modules/`) and the end-to-end
  `deploy.ps1` / `deploy.sh` scripts that provision into an empty resource group.
- `src/assets/` — `schema.sql` + `seed.sql`, loaded into Oracle at deploy time.
- `tools/gen_seed.py` — **generates** `seed.sql`; edit the Python product lists
  and regenerate rather than hand-editing `seed.sql`.

## Target Azure architecture

The deployment provisions and wires together these components. Preserve this
topology when editing `src/infra`:

- A **virtual network** using the `10.11.0.0/16` address space (it will be
  peered later, so do not reuse that range for anything else).
- An **Azure App Service** that runs the website, integrated with the virtual
  network.
- An **Oracle Database 21c** running on a **virtual machine**, **private access
  only** (no public endpoint). Use the **Azure Marketplace image** rather than
  installing Oracle by hand.
- An **Azure Application Gateway** fronted by a **public IP** that is the only
  internet-facing entry point.

Traffic flow: Internet → Public IP → Application Gateway → App Service (VNet) →
Oracle VM (private).

## Key conventions

- **Data access** goes through `IProductRepository` (`src/app/Data`). There are
  two implementations: `OracleProductRepository` (used when a connection string
  is configured) and `InMemoryProductRepository` (local-dev fallback). Keep both
  in sync when changing the data contract. Connection string resolves from
  `ConnectionStrings:Catalog` or the `CATALOG_CONNECTION_STRING` env var.
- **Oracle SQL** must stay parameterized; `ORDER BY` is mapped through a
  whitelist (never interpolate the sort key).
- The end-to-end deploy script targets an **empty resource group** and
  provisions everything from scratch.
- Demo data lives in `src/assets` and is loaded into Oracle at deploy time —
  keep seed/schema there, not embedded in app code.
- `/healthz` reflects database reachability and drives the App Gateway probe;
  preserve it for SRE incident demos.
- Scope is **catalog browsing only**. Do not add cart, checkout, payments, or
  auth flows unless the brief changes.
