namespace SreDemo.Catalog.Models;

public class ProductQuery
{
    public string? Category { get; set; }
    public string? Search { get; set; }
    public string? Brand { get; set; }
    public string Sort { get; set; } = "name";
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 24;
}

public class ProductPage
{
    public IReadOnlyList<Product> Items { get; set; } = Array.Empty<Product>();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);
}
