using Oracle.ManagedDataAccess.Client;
using SreDemo.Catalog.Models;

namespace SreDemo.Catalog.Data;

/// <summary>
/// Oracle-backed catalog repository. Uses Oracle.ManagedDataAccess.Core with
/// fully parameterized queries. ORDER BY is mapped through a whitelist so the
/// sort key can never be injected.
/// </summary>
public class OracleProductRepository : IProductRepository
{
    private readonly string _connectionString;
    private readonly string _pingConnectionString;
    private readonly ILogger<OracleProductRepository> _logger;

    public OracleProductRepository(string connectionString, ILogger<OracleProductRepository> logger)
    {
        _connectionString = connectionString;
        _logger = logger;

        // Health probes must fail fast: cap the connect attempt so /healthz
        // returns Unhealthy quickly instead of hanging past the App Gateway's
        // probe timeout when the database is unreachable.
        var builder = new OracleConnectionStringBuilder(connectionString)
        {
            ConnectionTimeout = 5,
        };
        _pingConnectionString = builder.ConnectionString;
    }

    private static string OrderByClause(string? sort) => sort switch
    {
        "price_asc" => "PRICE ASC, NAME ASC",
        "price_desc" => "PRICE DESC, NAME ASC",
        "brand" => "BRAND ASC, NAME ASC",
        _ => "NAME ASC",
    };

    private async Task<OracleConnection> OpenAsync(CancellationToken ct)
    {
        var conn = new OracleConnection(_connectionString);
        await conn.OpenAsync(ct);
        return conn;
    }

    public async Task<IReadOnlyList<Category>> GetCategoriesAsync(CancellationToken ct = default)
    {
        const string sql = @"
            SELECT c.CODE, c.NAME, c.DESCRIPTION, COUNT(p.ID) AS PRODUCT_COUNT
            FROM CATEGORIES c
            LEFT JOIN PRODUCTS p ON p.CATEGORY_CODE = c.CODE
            GROUP BY c.CODE, c.NAME, c.DESCRIPTION
            ORDER BY c.NAME";

        await using var conn = await OpenAsync(ct);
        await using var cmd = new OracleCommand(sql, conn);
        await using var reader = await cmd.ExecuteReaderAsync(ct);

        var list = new List<Category>();
        while (await reader.ReadAsync(ct))
        {
            list.Add(new Category
            {
                Code = reader.GetString(0),
                Name = reader.GetString(1),
                Description = reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
                ProductCount = reader.GetInt32(3),
            });
        }
        return list;
    }

    public async Task<ProductPage> GetProductsAsync(ProductQuery query, CancellationToken ct = default)
    {
        var where = new List<string>();
        var parameters = new List<OracleParameter>();

        if (!string.IsNullOrWhiteSpace(query.Category))
        {
            where.Add("p.CATEGORY_CODE = :category");
            parameters.Add(new OracleParameter("category", query.Category));
        }
        if (!string.IsNullOrWhiteSpace(query.Brand))
        {
            where.Add("p.BRAND = :brand");
            parameters.Add(new OracleParameter("brand", query.Brand));
        }
        if (!string.IsNullOrWhiteSpace(query.Search))
        {
            where.Add("(UPPER(p.NAME) LIKE :search OR UPPER(p.SPECS) LIKE :search OR UPPER(p.BRAND) LIKE :search)");
            parameters.Add(new OracleParameter("search", $"%{query.Search.ToUpperInvariant()}%"));
        }

        var whereClause = where.Count > 0 ? "WHERE " + string.Join(" AND ", where) : string.Empty;

        var page = Math.Max(1, query.Page);
        var pageSize = Math.Clamp(query.PageSize, 1, 100);
        var offset = (page - 1) * pageSize;

        var sql = $@"
            SELECT p.ID, p.SKU, p.NAME, p.CATEGORY_CODE, c.NAME AS CATEGORY_NAME,
                   p.BRAND, p.PRICE, p.SPECS, p.STOCK, p.IMAGE_URL, p.DESCRIPTION,
                   COUNT(*) OVER () AS TOTAL_COUNT
            FROM PRODUCTS p
            JOIN CATEGORIES c ON c.CODE = p.CATEGORY_CODE
            {whereClause}
            ORDER BY {OrderByClause(query.Sort)}
            OFFSET :offset ROWS FETCH NEXT :limit ROWS ONLY";

        await using var conn = await OpenAsync(ct);
        await using var cmd = new OracleCommand(sql, conn) { BindByName = true };
        foreach (var p in parameters) cmd.Parameters.Add(p);
        cmd.Parameters.Add(new OracleParameter("offset", offset));
        cmd.Parameters.Add(new OracleParameter("limit", pageSize));

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var items = new List<Product>();
        var total = 0;
        while (await reader.ReadAsync(ct))
        {
            items.Add(MapProduct(reader));
            total = Convert.ToInt32(reader.GetDecimal(11));
        }

        return new ProductPage
        {
            Items = items,
            TotalCount = total,
            Page = page,
            PageSize = pageSize,
        };
    }

    public async Task<Product?> GetProductAsync(int id, CancellationToken ct = default)
    {
        const string sql = @"
            SELECT p.ID, p.SKU, p.NAME, p.CATEGORY_CODE, c.NAME AS CATEGORY_NAME,
                   p.BRAND, p.PRICE, p.SPECS, p.STOCK, p.IMAGE_URL, p.DESCRIPTION
            FROM PRODUCTS p
            JOIN CATEGORIES c ON c.CODE = p.CATEGORY_CODE
            WHERE p.ID = :id";

        await using var conn = await OpenAsync(ct);
        await using var cmd = new OracleCommand(sql, conn) { BindByName = true };
        cmd.Parameters.Add(new OracleParameter("id", id));
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        return await reader.ReadAsync(ct) ? MapProduct(reader) : null;
    }

    public async Task<IReadOnlyList<string>> GetBrandsAsync(string? categoryCode, CancellationToken ct = default)
    {
        var sql = @"SELECT DISTINCT BRAND FROM PRODUCTS";
        OracleParameter? param = null;
        if (!string.IsNullOrWhiteSpace(categoryCode))
        {
            sql += " WHERE CATEGORY_CODE = :category";
            param = new OracleParameter("category", categoryCode);
        }
        sql += " ORDER BY BRAND";

        await using var conn = await OpenAsync(ct);
        await using var cmd = new OracleCommand(sql, conn) { BindByName = true };
        if (param is not null) cmd.Parameters.Add(param);
        await using var reader = await cmd.ExecuteReaderAsync(ct);

        var brands = new List<string>();
        while (await reader.ReadAsync(ct))
            brands.Add(reader.GetString(0));
        return brands;
    }

    public async Task<bool> PingAsync(CancellationToken ct = default)
    {
        try
        {
            await using var conn = new OracleConnection(_pingConnectionString);
            await conn.OpenAsync(ct);
            await using var cmd = new OracleCommand("SELECT 1 FROM DUAL", conn);
            await cmd.ExecuteScalarAsync(ct);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Oracle health probe failed");
            return false;
        }
    }

    private static Product MapProduct(OracleDataReader r) => new()
    {
        Id = Convert.ToInt32(r.GetDecimal(0)),
        Sku = r.GetString(1),
        Name = r.GetString(2),
        CategoryCode = r.GetString(3),
        CategoryName = r.GetString(4),
        Brand = r.IsDBNull(5) ? string.Empty : r.GetString(5),
        Price = r.GetDecimal(6),
        Specs = r.IsDBNull(7) ? string.Empty : r.GetString(7),
        Stock = r.IsDBNull(8) ? 0 : Convert.ToInt32(r.GetDecimal(8)),
        ImageUrl = r.IsDBNull(9) ? string.Empty : r.GetString(9),
        Description = r.IsDBNull(10) ? string.Empty : r.GetString(10),
    };
}
