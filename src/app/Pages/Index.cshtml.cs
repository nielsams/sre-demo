using Microsoft.AspNetCore.Mvc.RazorPages;
using SreDemo.Catalog.Data;
using SreDemo.Catalog.Models;

namespace SreDemo.Catalog.Pages;

public class IndexModel : PageModel
{
    private readonly IProductRepository _repository;

    public IndexModel(IProductRepository repository) => _repository = repository;

    public IReadOnlyList<Category> Categories { get; private set; } = Array.Empty<Category>();
    public IReadOnlyList<Product> Featured { get; private set; } = Array.Empty<Product>();

    public async Task OnGetAsync(CancellationToken ct)
    {
        Categories = await _repository.GetCategoriesAsync(ct);
        var page = await _repository.GetProductsAsync(new ProductQuery { Sort = "price_desc", PageSize = 8 }, ct);
        Featured = page.Items;
    }
}
