namespace SreDemo.Catalog.Models;

public class Category
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public int ProductCount { get; set; }
}
