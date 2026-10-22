import '../../core/routing/app_routes.dart';
import '../../core/routing/nav_registry.dart';
import '../../state/data_controller.dart';

/// What the top bar calls a page: its section and, on a detail page, the
/// record's name (`Orders › ORD-000123`).
class PageTitle {
  const PageTitle({required this.section, this.record, this.sectionRoute});

  /// The section's display name, e.g. "Orders".
  final String section;

  /// The record's display name on a detail page, else null.
  final String? record;

  /// The section's list route, e.g. `/orders`.
  final String? sectionRoute;

  bool get isDetail => record != null;

  /// The most specific name: the record on detail pages, else the section.
  String get label => record ?? section;

  static PageTitle of(DataController data, String location) {
    final path = Uri.tryParse(location)?.path ?? location;
    final section = Routes.sectionOf(path);
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final id = segments.length > 1 ? Uri.decodeComponent(segments[1]) : null;
    return PageTitle(
      section: NavRegistry.titleFor(path),
      sectionRoute: section,
      record: id == null ? null : (recordName(data, section, id) ?? id),
    );
  }

  /// The display name of record [id] in [section], if it's loaded.
  static String? recordName(DataController data, String? section, String id) {
    switch (section) {
      case Routes.businesses:
        return data.businessById(id)?.name;
      case Routes.products:
        return data.productById(id)?.name;
      case Routes.campaigns:
        return data.campaignById(id)?.name;
      case Routes.orders:
        return data.orderById(id)?.id;
      case Routes.expenses:
        return data.expenseById(id)?.name;
      case Routes.dealers:
        return data.dealerById(id)?.name;
      case Routes.customers:
        return data.customerById(id)?.name;
    }
    return null;
  }
}
