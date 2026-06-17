using SreDemo.Catalog.Models;

namespace SreDemo.Catalog.Data;

public interface IProductRepository
{
    Task<IReadOnlyList<Category>> GetCategoriesAsync(CancellationToken ct = default);
    Task<ProductPage> GetProductsAsync(ProductQuery query, CancellationToken ct = default);
    Task<Product?> GetProductAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<string>> GetBrandsAsync(string? categoryCode, CancellationToken ct = default);

    /// <summary>Lightweight connectivity probe used by the health endpoint.</summary>
    Task<bool> PingAsync(CancellationToken ct = default);
}
