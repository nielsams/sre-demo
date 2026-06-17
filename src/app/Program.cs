using Microsoft.Extensions.Diagnostics.HealthChecks;
using SreDemo.Catalog.Data;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages();

// Connection string resolution order:
//   1. ConnectionStrings:Catalog (appsettings / App Service connection strings)
//   2. CATALOG_CONNECTION_STRING environment variable
// If none is present we fall back to the in-memory repository so the app runs
// locally and during early development without an Oracle instance.
var connectionString =
    builder.Configuration.GetConnectionString("Catalog")
    ?? builder.Configuration["CATALOG_CONNECTION_STRING"];

if (!string.IsNullOrWhiteSpace(connectionString))
{
    builder.Services.AddSingleton<IProductRepository>(sp =>
        new OracleProductRepository(
            connectionString,
            sp.GetRequiredService<ILogger<OracleProductRepository>>()));
}
else
{
    builder.Services.AddSingleton<IProductRepository, InMemoryProductRepository>();
}

builder.Services.AddHealthChecks()
    .AddCheck<CatalogHealthCheck>("catalog-db");

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();
app.MapRazorPages();

// Liveness/readiness probe consumed by the Application Gateway health probe and
// used to demonstrate SRE incident detection when the database is unavailable.
app.MapHealthChecks("/healthz");

app.Run();

internal sealed class CatalogHealthCheck : IHealthCheck
{
    private readonly IProductRepository _repository;

    public CatalogHealthCheck(IProductRepository repository) => _repository = repository;

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        var ok = await _repository.PingAsync(cancellationToken);
        return ok
            ? HealthCheckResult.Healthy("Catalog data store reachable")
            : HealthCheckResult.Unhealthy("Catalog data store unreachable");
    }
}
