namespace SreDemo.Catalog.Models;

public class Product
{
    public int Id { get; set; }
    public string Sku { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string CategoryCode { get; set; } = string.Empty;
    public string CategoryName { get; set; } = string.Empty;
    public string Brand { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public string Specs { get; set; } = string.Empty;
    public int Stock { get; set; }
    public string ImageUrl { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
}
