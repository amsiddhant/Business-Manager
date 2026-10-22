/// The dashboard's sections, in their default order. The dashboard builds
/// them from this list, so Settings (P4) can reorder and hide them without
/// touching the screen.
enum DashboardSectionId {
  hero('Headline figures'),
  attention('Alerts and insights'),
  overview('Revenue and expenses'),
  profit('Profit and trend'),
  scorecards('More figures'),
  products('Products'),
  trends('Marketing and orders'),
  breakdowns('Breakdowns'),
  tables('Tables');

  const DashboardSectionId(this.label);
  final String label;
}

/// The default layout: every section, in order.
const kDefaultDashboardSections = DashboardSectionId.values;
