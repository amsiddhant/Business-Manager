import '../../models/app_settings.dart';
import '../../models/app_user.dart';
import 'app_routes.dart';

/// Which global scope selectors a page actually uses. The top bar only shows
/// the selectors that change what's on screen.
enum ScopeUse {
  none,
  business,
  period,
  businessAndPeriod;

  bool get usesBusiness => this == business || this == businessAndPeriod;
  bool get usesPeriod => this == period || this == businessAndPeriod;
}

/// A labelled group of sidebar destinations.
class NavGroup {
  const NavGroup(this.label, this.routes);

  final String label;

  /// Section routes, in display order (see [kNavDestinations]).
  final List<String> routes;
}

/// Sidebar grouping, top to bottom.
const List<NavGroup> kNavGroups = [
  NavGroup('Overview',
      [Routes.dashboard, Routes.alerts, Routes.goals, Routes.reports]),
  NavGroup('Sales', [Routes.orders, Routes.customers, Routes.campaigns]),
  NavGroup('Catalog', [Routes.products, Routes.businesses]),
  NavGroup('Spend', [Routes.expenses, Routes.dealers]),
  NavGroup('Admin', [Routes.users, Routes.settings]),
];

/// The sections on the mobile bottom bar, in order (filtered by permission;
/// the rest live under "More").
const List<String> kMobilePrimaryRoutes = [
  Routes.dashboard,
  Routes.orders,
  Routes.customers,
  Routes.reports,
];

/// The shell's branches, in the order `app_router.dart` declares them. Each
/// section keeps its own navigator (and so its list state) while you're away.
const List<String> kShellBranches = [
  Routes.dashboard,
  Routes.alerts,
  Routes.goals,
  Routes.businesses,
  Routes.products,
  Routes.campaigns,
  Routes.orders,
  Routes.expenses,
  Routes.dealers,
  Routes.customers,
  Routes.reports,
  Routes.users,
  Routes.settings,
  Routes.whatsNew,
];

/// Navigation lookups shared by the sidebar, rail, bottom bar, top bar and
/// command palette.
class NavRegistry {
  NavRegistry._();

  static NavDestination? destinationFor(String route) {
    for (final d in kNavDestinations) {
      if (d.route == route) return d;
    }
    return null;
  }

  static bool canSee(AppUser user, NavDestination d) =>
      user.can(d.permission) && (!d.ownerOnly || user.isOwner);

  /// Every destination [user] may see, in sidebar order. Sections the
  /// organisation switched off (in [modules]) are left out.
  static List<NavDestination> visible(AppUser user, {ModuleSettings? modules}) =>
      [
        for (final g in kNavGroups) ..._items(user, g, modules),
      ];

  /// [kNavGroups] filtered for [user]; empty groups are dropped.
  static List<({NavGroup group, List<NavDestination> items})> groupsFor(
      AppUser user,
      {ModuleSettings? modules}) {
    return [
      for (final g in kNavGroups)
        if (_items(user, g, modules) case final items when items.isNotEmpty)
          (group: g, items: items),
    ];
  }

  static List<NavDestination> _items(
          AppUser user, NavGroup g, ModuleSettings? modules) =>
      [
        for (final r in g.routes) ?destinationFor(r),
      ]
          .where((d) =>
              canSee(user, d) && (modules == null || modules.isEnabled(d.route)))
          .toList();

  /// The bottom-bar sections for [user]: the organisation's choice
  /// ([navigation]) when it has one, otherwise the primary ones they may
  /// open, topped up from the rest of the sidebar so there are up to four.
  static List<NavDestination> mobilePrimary(
    AppUser user, {
    ModuleSettings? modules,
    NavigationSettings? navigation,
  }) {
    final all = visible(user, modules: modules);
    final chosen = navigation?.mobilePrimary ?? const <String>[];
    if (chosen.isNotEmpty) {
      final picked = [
        for (final r in chosen) ...all.where((d) => d.route == r),
      ].take(NavigationSettings.maxMobileItems).toList();
      if (picked.isNotEmpty) return picked;
    }
    final primary = [
      for (final r in kMobilePrimaryRoutes)
        ...all.where((d) => d.route == r),
    ];
    for (final d in all) {
      if (primary.length >= 4) break;
      if (!primary.contains(d)) primary.add(d);
    }
    return primary.take(4).toList();
  }

  /// The shell branch [location] belongs to, or null.
  static int? branchIndexOf(String location) {
    final i = kShellBranches.indexOf(Routes.sectionOf(location) ?? '');
    return i < 0 ? null : i;
  }

  /// Which scope selectors the page at [location] uses.
  static ScopeUse scopeFor(String location) {
    final path = Uri.tryParse(location)?.path ?? location;
    final section = Routes.sectionOf(path);
    final isRoot = path == section;
    switch (section) {
      case Routes.dashboard:
      case Routes.reports:
        return ScopeUse.businessAndPeriod;
      case Routes.orders:
      case Routes.customers:
      case Routes.campaigns:
      case Routes.products:
      case Routes.expenses:
      case Routes.dealers:
        // Product detail shows figures for the selected period.
        if (!isRoot) {
          return section == Routes.products ? ScopeUse.period : ScopeUse.none;
        }
        return ScopeUse.business;
      case Routes.businesses:
        return isRoot ? ScopeUse.none : ScopeUse.period;
      case Routes.goals:
        return ScopeUse.business;
      default:
        return ScopeUse.none;
    }
  }

  /// Whether [location] is a section's list page (not a detail page).
  static bool isSectionRoot(String location) {
    final path = Uri.tryParse(location)?.path ?? location;
    return path == Routes.sectionOf(path);
  }

  /// The section's display name for [location].
  static String titleFor(String location) {
    final section = Routes.sectionOf(location);
    if (section == Routes.whatsNew) return "What's new";
    return destinationFor(section ?? '')?.label ?? 'Business Manager';
  }
}
