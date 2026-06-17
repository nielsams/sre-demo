using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using SreDemo.Catalog.Data;
using SreDemo.Catalog.Models;

namespace SreDemo.Catalog.Pages;

public class ProductModel : PageModel
{
    private readonly IProductRepository _repository;

    public ProductModel(IProductRepository repository) => _repository = repository;

    public Product Product { get; private set; } = new();

    public async Task<IActionResult> OnGetAsync(int id, CancellationToken ct)
    {
        var product = await _repository.GetProductAsync(id, ct);
        if (product is null)
            return NotFound();

        Product = product;
        return Page();
    }
}
