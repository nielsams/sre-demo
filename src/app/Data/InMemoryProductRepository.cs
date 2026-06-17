using SreDemo.Catalog.Models;

namespace SreDemo.Catalog.Data;

/// <summary>
/// In-memory catalog used when no Oracle connection string is configured
/// (local development). The authoritative inventory lives in src/assets and is
/// loaded into Oracle at deploy time; this is a small representative subset.
/// </summary>
public class InMemoryProductRepository : IProductRepository
{
    private readonly List<Category> _categories = new()
    {
        new() { Code = "CPU", Name = "Processors", Description = "Desktop CPUs" },
        new() { Code = "GPU", Name = "Graphics Cards", Description = "Discrete GPUs" },
        new() { Code = "RAM", Name = "Memory", Description = "DDR4/DDR5 kits" },
        new() { Code = "SSD", Name = "Storage", Description = "SSDs and NVMe drives" },
        new() { Code = "MBD", Name = "Motherboards", Description = "ATX/mATX boards" },
        new() { Code = "PSU", Name = "Power Supplies", Description = "ATX power supplies" },
    };

    private readonly List<Product> _products = new()
    {
        new() { Id = 1, Sku = "CPU-RYZ-7800X3D", Name = "AMD Ryzen 7 7800X3D", CategoryCode = "CPU", Brand = "AMD", Price = 359.00m, Stock = 24, Specs = "8C/16T, 4.2GHz, AM5, 96MB L3", ImageUrl = "/images/placeholder.svg", Description = "Gaming-focused 3D V-Cache CPU." },
        new() { Id = 2, Sku = "CPU-INT-14700K", Name = "Intel Core i7-14700K", CategoryCode = "CPU", Brand = "Intel", Price = 399.00m, Stock = 18, Specs = "20C/28T, 5.6GHz, LGA1700", ImageUrl = "/images/placeholder.svg", Description = "High-performance desktop processor." },
        new() { Id = 3, Sku = "GPU-NV-RTX4070", Name = "NVIDIA GeForce RTX 4070", CategoryCode = "GPU", Brand = "NVIDIA", Price = 549.00m, Stock = 12, Specs = "12GB GDDR6X, 2475MHz boost", ImageUrl = "/images/placeholder.svg", Description = "1440p gaming graphics card." },
        new() { Id = 4, Sku = "GPU-AMD-RX7800XT", Name = "AMD Radeon RX 7800 XT", CategoryCode = "GPU", Brand = "AMD", Price = 499.00m, Stock = 9, Specs = "16GB GDDR6, RDNA 3", ImageUrl = "/images/placeholder.svg", Description = "High-VRAM 1440p card." },
        new() { Id = 5, Sku = "RAM-COR-32-6000", Name = "Corsair Vengeance 32GB DDR5-6000", CategoryCode = "RAM", Brand = "Corsair", Price = 114.00m, Stock = 40, Specs = "2x16GB, CL30, DDR5", ImageUrl = "/images/placeholder.svg", Description = "Enthusiast DDR5 kit." },
        new() { Id = 6, Sku = "SSD-SAM-990-2TB", Name = "Samsung 990 Pro 2TB NVMe", CategoryCode = "SSD", Brand = "Samsung", Price = 169.00m, Stock = 33, Specs = "PCIe 4.0, 7450MB/s read", ImageUrl = "/images/placeholder.svg", Description = "Flagship Gen4 NVMe SSD." },
        new() { Id = 7, Sku = "MBD-ASU-B650E", Name = "ASUS ROG Strix B650E-F", CategoryCode = "MBD", Brand = "ASUS", Price = 259.00m, Stock = 15, Specs = "AM5, DDR5, PCIe 5.0", ImageUrl = "/images/placeholder.svg", Description = "Feature-rich AM5 motherboard." },
        new() { Id = 8, Sku = "PSU-SEA-850W", Name = "Seasonic Focus GX-850", CategoryCode = "PSU", Brand = "Seasonic", Price = 129.00m, Stock = 27, Specs = "850W, 80+ Gold, fully modular", ImageUrl = "/images/placeholder.svg", Description = "Reliable 80+ Gold PSU." },
    };

    public Task<IReadOnlyList<Category>> GetCategoriesAsync(CancellationToken ct = default)
    {
        foreach (var c in _categories)
            c.ProductCount = _products.Count(p => p.CategoryCode == c.Code);
        return Task.FromResult<IReadOnlyList<Category>>(_categories);
    }

    public Task<ProductPage> GetProductsAsync(ProductQuery query, CancellationToken ct = default)
    {
        IEnumerable<Product> q = _products;

        if (!string.IsNullOrWhiteSpace(query.Category))
            q = q.Where(p => p.CategoryCode == query.Category);
        if (!string.IsNullOrWhiteSpace(query.Brand))
            q = q.Where(p => p.Brand == query.Brand);
        if (!string.IsNullOrWhiteSpace(query.Search))
        {
            var s = query.Search.Trim();
            q = q.Where(p =>
                p.Name.Contains(s, StringComparison.OrdinalIgnoreCase) ||
                p.Specs.Contains(s, StringComparison.OrdinalIgnoreCase) ||
                p.Brand.Contains(s, StringComparison.OrdinalIgnoreCase));
        }

        q = query.Sort switch
        {
            "price_asc" => q.OrderBy(p => p.Price).ThenBy(p => p.Name),
            "price_desc" => q.OrderByDescending(p => p.Price).ThenBy(p => p.Name),
            "brand" => q.OrderBy(p => p.Brand).ThenBy(p => p.Name),
            _ => q.OrderBy(p => p.Name),
        };

        var all = q.ToList();
        var page = Math.Max(1, query.Page);
        var pageSize = Math.Clamp(query.PageSize, 1, 100);
        var items = all.Skip((page - 1) * pageSize).Take(pageSize).ToList();

        foreach (var p in items)
            p.CategoryName = _categories.FirstOrDefault(c => c.Code == p.CategoryCode)?.Name ?? p.CategoryCode;

        return Task.FromResult(new ProductPage
        {
            Items = items,
            TotalCount = all.Count,
            Page = page,
            PageSize = pageSize,
        });
    }

    public Task<Product?> GetProductAsync(int id, CancellationToken ct = default)
    {
        var p = _products.FirstOrDefault(x => x.Id == id);
        if (p is not null)
            p.CategoryName = _categories.FirstOrDefault(c => c.Code == p.CategoryCode)?.Name ?? p.CategoryCode;
        return Task.FromResult(p);
    }

    public Task<IReadOnlyList<string>> GetBrandsAsync(string? categoryCode, CancellationToken ct = default)
    {
        var brands = _products
            .Where(p => string.IsNullOrWhiteSpace(categoryCode) || p.CategoryCode == categoryCode)
            .Select(p => p.Brand)
            .Distinct()
            .OrderBy(b => b)
            .ToList();
        return Task.FromResult<IReadOnlyList<string>>(brands);
    }

    public Task<bool> PingAsync(CancellationToken ct = default) => Task.FromResult(true);
}
