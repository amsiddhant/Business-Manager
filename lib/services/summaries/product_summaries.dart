import '../../core/utils/money.dart';
import '../../models/product.dart';
import '../profit_calculation_service.dart';

/// Headline figures for a set of products (the Products list KPI strip).
class ProductCatalogueSummary {
  const ProductCatalogueSummary({
    required this.count,
    required this.activeCount,
    required this.categoryCount,
    required this.averageSellingPrice,
    required this.averageBuyingPrice,
    required this.averageMarkup,
  });

  final int count;
  final int activeCount;

  /// Distinct, non-empty categories.
  final int categoryCount;

  /// Mean list price over products that have one.
  final Money averageSellingPrice;

  /// Mean buying price over products that have one.
  final Money averageBuyingPrice;

  /// Mean list margin, `(selling - buying) / selling` in percent, over
  /// products with a selling price; null when none has one.
  final double? averageMarkup;

  int get inactiveCount => count - activeCount;
}

extension ProductSummaries on ProfitCalculationService {
  /// Rolls [products] up into the catalogue figures.
  ProductCatalogueSummary summariseProducts(Iterable<Product> products) {
    var count = 0;
    var active = 0;
    var sellingTotal = Money.zero;
    var sellingN = 0;
    var buyingTotal = Money.zero;
    var buyingN = 0;
    var marginSum = 0.0;
    var marginN = 0;
    final categories = <String>{};
    for (final p in products) {
      count++;
      if (p.isActive) active++;
      final category = p.category.trim().toLowerCase();
      if (category.isNotEmpty) categories.add(category);
      if (p.sellingPrice.isPositive) {
        sellingTotal += p.sellingPrice;
        sellingN++;
        marginSum +=
            (p.sellingPrice - p.buyingPrice).major / p.sellingPrice.major * 100;
        marginN++;
      }
      if (p.buyingPrice.isPositive) {
        buyingTotal += p.buyingPrice;
        buyingN++;
      }
    }
    return ProductCatalogueSummary(
      count: count,
      activeCount: active,
      categoryCount: categories.length,
      averageSellingPrice: sellingTotal / sellingN,
      averageBuyingPrice: buyingTotal / buyingN,
      averageMarkup: marginN == 0 ? null : marginSum / marginN,
    );
  }
}
