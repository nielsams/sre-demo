using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using SreDemo.Catalog.Data;
using SreDemo.Catalog.Models;

namespace SreDemo.Catalog.Pages;

public class CatalogModel : PageModel
{
    private readonly IProductRepository _repository;

    public CatalogModel(IProductRepository repository) => _repository = repository;

    [BindProperty(SupportsGet = true)]
    public string? Category { get; set; }

    [BindProperty(SupportsGet = true)]
    public string? Brand { get; set; }

    [BindProperty(SupportsGet = true)]
    public string? Search { get; set; }

    [BindProperty(SupportsGet = true)]
    public string Sort { get; set; } = "name";

    [BindProperty(SupportsGet = true, Name = "page")]
    public int PageNumber { get; set; } = 1;

    public IReadOnlyList<Category> Categories { get; private set; } = Array.Empty<Category>();
    public IReadOnlyList<string> Brands { get; private set; } = Array.Empty<string>();
    public ProductPage Results { get; private set; } = new();

    public static readonly (string Value, string Label)[] SortOptions =
    {
        ("name", "Name (A–Z)"),
        ("price_asc", "Price (low to high)"),
        ("price_desc", "Price (high to low)"),
        ("brand", "Brand"),
    };

    public async Task OnGetAsync(CancellationToken ct)
    {
        Categories = await _repository.GetCategoriesAsync(ct);
        Brands = await _repository.GetBrandsAsync(Category, ct);
        Results = await _repository.GetProductsAsync(new ProductQuery
        {
            Category = Category,
            Brand = Brand,
            Search = Search,
            Sort = Sort,
            Page = PageNumber,
        }, ct);
    }

    public string? CurrentCategoryName =>
        Categories.FirstOrDefault(c => c.Code == Category)?.Name;
}
