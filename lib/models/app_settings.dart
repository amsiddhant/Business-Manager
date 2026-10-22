import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../core/enums.dart';
import '../core/routing/app_routes.dart';
import '../core/theme/app_density.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_palette.dart';
import '../core/utils/date_utils.dart';

const _listEq = ListEquality<String>();
const _setEq = SetEquality<String>();
const _mapEq = MapEquality<String, List<String>>(values: ListEquality());

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhereOrNull((v) => v.name == name) ?? fallback;

int _int(Object? v, int fallback, {required int min, required int max}) =>
    v is num ? v.round().clamp(min, max) : fallback;

double _double(Object? v, double fallback,
        {required double min, required double max}) =>
    v is num ? v.toDouble().clamp(min, max) : fallback;

String _str(Object? v, String fallback, {int max = 200}) {
  if (v is! String) return fallback;
  final s = v.trim();
  if (s.isEmpty) return fallback;
  return s.length > max ? s.substring(0, max) : s;
}

List<String> _strings(Object? v, {int max = 50}) => v is List
    ? [for (final e in v.take(max)) if (e is String && e.isNotEmpty) e]
    : const [];

Map<String, dynamic> _section(Map<String, dynamic>? map, String key) {
  final v = map?[key];
  return v is Map ? Map<String, dynamic>.from(v) : const {};
}

/// The organisation's settings: one `settings/app` document, read once per
/// session and written in one go when an Owner or Admin saves.
///
/// Reading is tolerant: anything missing, unknown or out of range falls back
/// to its default, so an older (or newer) app can always open it. A missing
/// document means "all defaults" and is never written on its own.
@immutable
class AppSettings {
  const AppSettings({
    this.branding = const BrandingSettings(),
    this.theme = const ThemeSettings(),
    this.navigation = const NavigationSettings(),
    this.modules = const ModuleSettings(),
    this.features = const FeatureSettings(),
    this.defaults = const DefaultSettings(),
    this.dashboard = const DashboardSettings(),
    this.tables = const TableSettings(),
    this.alerts = const AlertSettings(),
    this.sync = const SyncSettings(),
    this.smart = const SmartSettings(),
    this.updatedAt,
    this.updatedBy = '',
  });

  static const schemaVersion = 1;

  final BrandingSettings branding;
  final ThemeSettings theme;
  final NavigationSettings navigation;
  final ModuleSettings modules;
  final FeatureSettings features;
  final DefaultSettings defaults;
  final DashboardSettings dashboard;
  final TableSettings tables;
  final AlertSettings alerts;
  final SyncSettings sync;
  final SmartSettings smart;

  /// When and by whom (display name) it was last saved.
  final DateTime? updatedAt;
  final String updatedBy;

  AppSettings copyWith({
    BrandingSettings? branding,
    ThemeSettings? theme,
    NavigationSettings? navigation,
    ModuleSettings? modules,
    FeatureSettings? features,
    DefaultSettings? defaults,
    DashboardSettings? dashboard,
    TableSettings? tables,
    AlertSettings? alerts,
    SyncSettings? sync,
    SmartSettings? smart,
    DateTime? updatedAt,
    String? updatedBy,
  }) =>
      AppSettings(
        branding: branding ?? this.branding,
        theme: theme ?? this.theme,
        navigation: navigation ?? this.navigation,
        modules: modules ?? this.modules,
        features: features ?? this.features,
        defaults: defaults ?? this.defaults,
        dashboard: dashboard ?? this.dashboard,
        tables: tables ?? this.tables,
        alerts: alerts ?? this.alerts,
        sync: sync ?? this.sync,
        smart: smart ?? this.smart,
        updatedAt: updatedAt ?? this.updatedAt,
        updatedBy: updatedBy ?? this.updatedBy,
      );

  Map<String, dynamic> toMap() => {
        'schemaVersion': schemaVersion,
        'branding': branding.toMap(),
        'theme': theme.toMap(),
        'navigation': navigation.toMap(),
        'modules': modules.toMap(),
        'features': features.toMap(),
        'defaults': defaults.toMap(),
        'dashboard': dashboard.toMap(),
        'tables': tables.toMap(),
        'alerts': alerts.toMap(),
        'sync': sync.toMap(),
        'smart': smart.toMap(),
        'updatedAt': updatedAt?.toIso8601String(),
        'updatedBy': updatedBy,
      };

  factory AppSettings.fromMap(Map<String, dynamic>? map) {
    final updatedAt = map?['updatedAt'];
    return AppSettings(
      branding: BrandingSettings.fromMap(_section(map, 'branding')),
      theme: ThemeSettings.fromMap(_section(map, 'theme')),
      navigation: NavigationSettings.fromMap(_section(map, 'navigation')),
      modules: ModuleSettings.fromMap(_section(map, 'modules')),
      features: FeatureSettings.fromMap(_section(map, 'features')),
      defaults: DefaultSettings.fromMap(_section(map, 'defaults')),
      dashboard: DashboardSettings.fromMap(_section(map, 'dashboard')),
      tables: TableSettings.fromMap(_section(map, 'tables')),
      alerts: AlertSettings.fromMap(_section(map, 'alerts')),
      sync: SyncSettings.fromMap(_section(map, 'sync')),
      smart: SmartSettings.fromMap(_section(map, 'smart')),
      updatedAt: switch (updatedAt) {
        final String s => DateTime.tryParse(s),
        final DateTime d => d,
        _ => _timestampToDate(updatedAt),
      },
      updatedBy: _str(map?['updatedBy'], '', max: 120),
    );
  }

  // Firestore Timestamps arrive as objects with `toDate()`; avoid importing
  // cloud_firestore into a model.
  static DateTime? _timestampToDate(Object? v) {
    try {
      return (v as dynamic)?.toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }

  /// Same settings, ignoring who saved them when.
  bool sameAs(AppSettings other) =>
      branding == other.branding &&
      theme == other.theme &&
      navigation == other.navigation &&
      modules == other.modules &&
      features == other.features &&
      defaults == other.defaults &&
      dashboard == other.dashboard &&
      tables == other.tables &&
      alerts == other.alerts &&
      sync == other.sync &&
      smart == other.smart;

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      sameAs(other) &&
      other.updatedAt == updatedAt &&
      other.updatedBy == updatedBy;

  @override
  int get hashCode => Object.hash(branding, theme, navigation, modules,
      features, defaults, dashboard, tables, alerts, sync, smart);
}

// ---- Branding ---------------------------------------------------------------

@immutable
class BrandingSettings {
  const BrandingSettings({
    this.appName = defaultAppName,
    this.shortName = '',
    this.tagline = '',
    this.primaryColor,
    this.logoHash,
    this.showLogoOnLogin = true,
  });

  static const defaultAppName = 'Salesforce Business Manager';
  static const maxAppName = 60;
  static const maxShortName = 20;
  static const maxTagline = 120;

  final String appName;

  /// Shown where space is tight (collapsed sidebar, mobile); empty = initials.
  final String shortName;

  /// One line under the name on the sign-in page.
  final String tagline;

  /// ARGB, always opaque; null = the built-in brand colour.
  final int? primaryColor;

  /// Identifies the logo in `settings/logo`; null = no logo.
  final String? logoHash;
  final bool showLogoOnLogin;

  Color get brand => switch (primaryColor) {
        final c? => Color(c | 0xFF000000),
        null => AppPalette.defaultBrand,
      };
  bool get hasLogo => logoHash != null;

  BrandingSettings copyWith({
    String? appName,
    String? shortName,
    String? tagline,
    int? Function()? primaryColor,
    String? Function()? logoHash,
    bool? showLogoOnLogin,
  }) =>
      BrandingSettings(
        appName: appName ?? this.appName,
        shortName: shortName ?? this.shortName,
        tagline: tagline ?? this.tagline,
        primaryColor: primaryColor != null ? primaryColor() : this.primaryColor,
        logoHash: logoHash != null ? logoHash() : this.logoHash,
        showLogoOnLogin: showLogoOnLogin ?? this.showLogoOnLogin,
      );

  Map<String, dynamic> toMap() => {
        'appName': appName,
        'shortName': shortName,
        'tagline': tagline,
        'primaryColor': primaryColor,
        'logoHash': logoHash,
        'showLogoOnLogin': showLogoOnLogin,
      };

  factory BrandingSettings.fromMap(Map<String, dynamic> m) {
    final color = m['primaryColor'];
    final hash = m['logoHash'];
    return BrandingSettings(
      appName: _str(m['appName'], defaultAppName, max: maxAppName),
      shortName: _str(m['shortName'], '', max: maxShortName),
      tagline: _str(m['tagline'], '', max: maxTagline),
      primaryColor: color is int ? (color & 0xFFFFFF) | 0xFF000000 : null,
      logoHash: hash is String && hash.isNotEmpty && hash.length <= 64
          ? hash
          : null,
      showLogoOnLogin: m['showLogoOnLogin'] != false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrandingSettings &&
      other.appName == appName &&
      other.shortName == shortName &&
      other.tagline == tagline &&
      other.primaryColor == primaryColor &&
      other.logoHash == logoHash &&
      other.showLogoOnLogin == showLogoOnLogin;

  @override
  int get hashCode => Object.hash(
      appName, shortName, tagline, primaryColor, logoHash, showLogoOnLogin);
}

// ---- Theme ------------------------------------------------------------------

/// How rounded cards, fields and buttons are.
enum CornerStyle {
  sharp('Sharp', 0.5),
  standard('Standard', 1),
  rounded('Rounded', 1.5);

  const CornerStyle(this.label, this.scale);
  final String label;

  /// Multiplies every corner radius.
  final double scale;
}

/// The colours charts draw their series in.
enum ChartPaletteStyle {
  brand('Brand'),
  vivid('Vivid'),
  calm('Calm'),
  mono('Monochrome');

  const ChartPaletteStyle(this.label);
  final String label;
}

@immutable
class ThemeSettings {
  const ThemeSettings({
    this.defaultMode = ThemeMode.light,
    this.allowUserOverride = true,
    this.density = AppDensity.comfortable,
    this.motion = MotionLevel.full,
    this.corners = CornerStyle.standard,
    this.chartPalette = ChartPaletteStyle.brand,
  });

  final ThemeMode defaultMode;
  final bool allowUserOverride;
  final AppDensity density;
  final MotionLevel motion;
  final CornerStyle corners;
  final ChartPaletteStyle chartPalette;

  ThemeSettings copyWith({
    ThemeMode? defaultMode,
    bool? allowUserOverride,
    AppDensity? density,
    MotionLevel? motion,
    CornerStyle? corners,
    ChartPaletteStyle? chartPalette,
  }) =>
      ThemeSettings(
        defaultMode: defaultMode ?? this.defaultMode,
        allowUserOverride: allowUserOverride ?? this.allowUserOverride,
        density: density ?? this.density,
        motion: motion ?? this.motion,
        corners: corners ?? this.corners,
        chartPalette: chartPalette ?? this.chartPalette,
      );

  Map<String, dynamic> toMap() => {
        'defaultMode': defaultMode.name,
        'allowUserOverride': allowUserOverride,
        'density': density.name,
        'motion': motion.name,
        'corners': corners.name,
        'chartPalette': chartPalette.name,
      };

  factory ThemeSettings.fromMap(Map<String, dynamic> m) => ThemeSettings(
        defaultMode:
            _enumByName(ThemeMode.values, m['defaultMode'], ThemeMode.light),
        allowUserOverride: m['allowUserOverride'] != false,
        density: AppDensity.fromName(m['density'] as String?),
        motion: MotionLevel.fromName(m['motion'] as String?),
        corners:
            _enumByName(CornerStyle.values, m['corners'], CornerStyle.standard),
        chartPalette: _enumByName(ChartPaletteStyle.values, m['chartPalette'],
            ChartPaletteStyle.brand),
      );

  @override
  bool operator ==(Object other) =>
      other is ThemeSettings &&
      other.defaultMode == defaultMode &&
      other.allowUserOverride == allowUserOverride &&
      other.density == density &&
      other.motion == motion &&
      other.corners == corners &&
      other.chartPalette == chartPalette;

  @override
  int get hashCode => Object.hash(
      defaultMode, allowUserOverride, density, motion, corners, chartPalette);
}

// ---- Navigation -------------------------------------------------------------

@immutable
class NavigationSettings {
  const NavigationSettings({
    this.mobilePrimary = const [],
    this.landingRoute = Routes.dashboard,
  });

  /// Up to four sections for the mobile bottom bar, in order. Empty = the
  /// built-in choice.
  final List<String> mobilePrimary;

  /// Where people land after signing in.
  final String landingRoute;

  static const maxMobileItems = 4;

  NavigationSettings copyWith({
    List<String>? mobilePrimary,
    String? landingRoute,
  }) =>
      NavigationSettings(
        mobilePrimary: mobilePrimary ?? this.mobilePrimary,
        landingRoute: landingRoute ?? this.landingRoute,
      );

  Map<String, dynamic> toMap() => {
        'mobilePrimary': mobilePrimary,
        'landingRoute': landingRoute,
      };

  factory NavigationSettings.fromMap(Map<String, dynamic> m) {
    final sections = {for (final d in kNavDestinations) d.route};
    final landing = m['landingRoute'];
    return NavigationSettings(
      mobilePrimary: [
        for (final r in _strings(m['mobilePrimary']).toSet())
          if (sections.contains(r)) r,
      ].take(maxMobileItems).toList(),
      landingRoute: landing is String && sections.contains(landing)
          ? landing
          : Routes.dashboard,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NavigationSettings &&
      _listEq.equals(other.mobilePrimary, mobilePrimary) &&
      other.landingRoute == landingRoute;

  @override
  int get hashCode => Object.hash(_listEq.hash(mobilePrimary), landingRoute);
}

// ---- Modules ----------------------------------------------------------------

/// Which sections are switched on. Switching one off only hides it: every
/// financial total still includes its data.
@immutable
class ModuleSettings {
  const ModuleSettings({this.disabled = const {}});

  /// Sections that can't be switched off.
  static const alwaysOn = {
    Routes.dashboard,
    Routes.users,
    Routes.settings,
    Routes.whatsNew,
  };

  /// Sections an admin may switch off, in display order.
  static const optional = [
    Routes.alerts,
    Routes.goals,
    Routes.reports,
    Routes.orders,
    Routes.customers,
    Routes.campaigns,
    Routes.products,
    Routes.businesses,
    Routes.expenses,
    Routes.dealers,
  ];

  /// Section routes that are off.
  final Set<String> disabled;

  /// Whether the section [route] (e.g. `/orders`) is on.
  bool isEnabled(String route) =>
      alwaysOn.contains(route) || !disabled.contains(route);

  /// Whether the page at [location] belongs to a section that's on.
  bool allows(String location) =>
      isEnabled(Routes.sectionOf(location) ?? Routes.dashboard);

  ModuleSettings toggle(String route, {required bool enabled}) =>
      ModuleSettings(
          disabled: enabled ? ({...disabled}..remove(route)) : {...disabled, route});

  Map<String, dynamic> toMap() => {'disabled': disabled.toList()..sort()};

  factory ModuleSettings.fromMap(Map<String, dynamic> m) => ModuleSettings(
        disabled: {
          for (final r in _strings(m['disabled']))
            if (optional.contains(r)) r,
        },
      );

  @override
  bool operator ==(Object other) =>
      other is ModuleSettings && _setEq.equals(other.disabled, disabled);

  @override
  int get hashCode => _setEq.hash(disabled);
}

// ---- Features ---------------------------------------------------------------

enum AppFeature {
  commandPalette('Command palette', 'Ctrl/Cmd+K to search and jump anywhere'),
  insights('Dashboard insights', 'Plain-language highlights on the dashboard'),
  forecasts('Forecasts', 'Projected figures and trend bands'),
  anomalies('Anomaly detection', 'Flags unusual spend'),
  suggestions('Smart suggestions', 'One-tap suggestions in forms'),
  drafts('Form drafts', 'Unsaved forms are kept on this device'),
  bulkActions('Bulk actions', 'Select rows to delete, export or update'),
  savedViews('Saved table views', 'Save filters, sorting and columns'),
  csvImport('CSV import', 'Import products and customers from CSV'),
  csvExport('CSV export', 'Export tables and reports'),
  invoices('Invoices', 'PDF invoices for customers'),
  whatsNew("What's new", 'Release notes after an update');

  const AppFeature(this.label, this.description);
  final String label;
  final String description;
}

@immutable
class FeatureSettings {
  const FeatureSettings({this.disabled = const {}});

  final Set<AppFeature> disabled;

  bool isOn(AppFeature f) => !disabled.contains(f);

  FeatureSettings toggle(AppFeature f, {required bool enabled}) =>
      FeatureSettings(
          disabled: enabled ? ({...disabled}..remove(f)) : {...disabled, f});

  Map<String, dynamic> toMap() =>
      {'disabled': [for (final f in disabled) f.name]..sort()};

  factory FeatureSettings.fromMap(Map<String, dynamic> m) {
    final byName = AppFeature.values.asNameMap();
    return FeatureSettings(disabled: {
      for (final n in _strings(m['disabled'])) ?byName[n],
    });
  }

  @override
  bool operator ==(Object other) =>
      other is FeatureSettings &&
      const SetEquality<AppFeature>().equals(other.disabled, disabled);

  @override
  int get hashCode => const SetEquality<AppFeature>().hash(disabled);
}

// ---- Defaults ---------------------------------------------------------------

/// How long numbers are grouped.
enum NumberGrouping {
  byCurrency('By currency', 'Lakh/crore for ₹, thousands otherwise'),
  indian('Indian', '12,34,567'),
  international('International', '1,234,567');

  const NumberGrouping(this.label, this.example);
  final String label;
  final String example;
}

@immutable
class DefaultSettings {
  const DefaultSettings({
    this.currency = CurrencyCode.inr,
    this.dateFormat = AppDate.defaultPattern,
    this.numberGrouping = NumberGrouping.byCurrency,
    this.period = PeriodType.financialYear,
    this.comparison = ComparisonBasis.previousPeriod,
    this.fyStartMonth = FinancialYear.defaultStartMonth,
    this.orderStatus,
    this.pageSize = 25,
  });

  /// The date formats people can choose.
  static const dateFormats = [
    'dd-MMM-yyyy',
    'dd/MM/yyyy',
    'MM/dd/yyyy',
    'yyyy-MM-dd',
    'd MMM yyyy',
    'MMM d, yyyy',
  ];

  /// The periods the dashboard can open on.
  static const periods = [
    PeriodType.financialYear,
    PeriodType.calendarYear,
    PeriodType.quarter,
    PeriodType.month,
  ];

  static const pageSizes = [10, 25, 50, 100];

  /// Currency for new businesses.
  final CurrencyCode currency;
  final String dateFormat;
  final NumberGrouping numberGrouping;

  /// The period selected for someone who hasn't picked one yet.
  final PeriodType period;
  final ComparisonBasis comparison;

  /// 1, 4, 7 or 10 (Jan, Apr, Jul, Oct).
  final int fyStartMonth;

  /// Status for new orders; null = the form's own default.
  final OrderStatus? orderStatus;

  /// Rows per table page.
  final int pageSize;

  DefaultSettings copyWith({
    CurrencyCode? currency,
    String? dateFormat,
    NumberGrouping? numberGrouping,
    PeriodType? period,
    ComparisonBasis? comparison,
    int? fyStartMonth,
    OrderStatus? Function()? orderStatus,
    int? pageSize,
  }) =>
      DefaultSettings(
        currency: currency ?? this.currency,
        dateFormat: dateFormat ?? this.dateFormat,
        numberGrouping: numberGrouping ?? this.numberGrouping,
        period: period ?? this.period,
        comparison: comparison ?? this.comparison,
        fyStartMonth: fyStartMonth ?? this.fyStartMonth,
        orderStatus: orderStatus != null ? orderStatus() : this.orderStatus,
        pageSize: pageSize ?? this.pageSize,
      );

  Map<String, dynamic> toMap() => {
        'currency': currency.wire,
        'dateFormat': dateFormat,
        'numberGrouping': numberGrouping.name,
        'period': period.name,
        'comparison': comparison.name,
        'fyStartMonth': fyStartMonth,
        'orderStatus': orderStatus?.wire,
        'pageSize': pageSize,
      };

  factory DefaultSettings.fromMap(Map<String, dynamic> m) {
    final fy = m['fyStartMonth'];
    final size = m['pageSize'];
    final format = m['dateFormat'];
    final period =
        _enumByName(PeriodType.values, m['period'], PeriodType.financialYear);
    final status = m['orderStatus'];
    return DefaultSettings(
      currency: CurrencyCode.fromWire(m['currency'] as String?),
      dateFormat: format is String && dateFormats.contains(format)
          ? format
          : AppDate.defaultPattern,
      numberGrouping: _enumByName(
          NumberGrouping.values, m['numberGrouping'], NumberGrouping.byCurrency),
      period: periods.contains(period) ? period : PeriodType.financialYear,
      comparison: _enumByName(ComparisonBasis.values, m['comparison'],
          ComparisonBasis.previousPeriod),
      fyStartMonth: fy is int && FinancialYear.startMonths.contains(fy)
          ? fy
          : FinancialYear.defaultStartMonth,
      orderStatus: status is String
          ? OrderStatus.values.firstWhereOrNull((s) => s.wire == status)
          : null,
      pageSize: size is int && pageSizes.contains(size) ? size : 25,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DefaultSettings &&
      other.currency == currency &&
      other.dateFormat == dateFormat &&
      other.numberGrouping == numberGrouping &&
      other.period == period &&
      other.comparison == comparison &&
      other.fyStartMonth == fyStartMonth &&
      other.orderStatus == orderStatus &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(currency, dateFormat, numberGrouping, period,
      comparison, fyStartMonth, orderStatus, pageSize);
}

// ---- Dashboard --------------------------------------------------------------

@immutable
class DashboardSettings {
  const DashboardSettings({
    this.order = const [],
    this.hidden = const {},
    this.heroKpis = const [],
  });

  /// Dashboard section ids in display order; sections missing from it keep
  /// their built-in place after the listed ones. Empty = built-in order.
  final List<String> order;

  /// Section ids that aren't shown.
  final Set<String> hidden;

  /// The four headline KPIs (`KpiMetric` names). Empty = built-in.
  final List<String> heroKpis;

  static const heroCount = 4;

  /// [builtIn] ids in this order: listed ones first, the rest after in
  /// their built-in order. Unknown ids are ignored.
  List<String> arrange(List<String> builtIn) => [
        for (final id in order)
          if (builtIn.contains(id)) id,
        for (final id in builtIn)
          if (!order.contains(id)) id,
      ];

  bool isVisible(String id) => !hidden.contains(id);

  DashboardSettings copyWith({
    List<String>? order,
    Set<String>? hidden,
    List<String>? heroKpis,
  }) =>
      DashboardSettings(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
        heroKpis: heroKpis ?? this.heroKpis,
      );

  Map<String, dynamic> toMap() => {
        'order': order,
        'hidden': hidden.toList()..sort(),
        'heroKpis': heroKpis,
      };

  factory DashboardSettings.fromMap(Map<String, dynamic> m) {
    final kpis = _strings(m['heroKpis']).toSet().toList();
    return DashboardSettings(
      order: _strings(m['order']).toSet().toList(),
      hidden: _strings(m['hidden']).toSet(),
      heroKpis: kpis.length == heroCount ? kpis : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardSettings &&
      _listEq.equals(other.order, order) &&
      _setEq.equals(other.hidden, hidden) &&
      _listEq.equals(other.heroKpis, heroKpis);

  @override
  int get hashCode => Object.hash(
      _listEq.hash(order), _setEq.hash(hidden), _listEq.hash(heroKpis));
}

// ---- Tables -----------------------------------------------------------------

@immutable
class TableSettings {
  const TableSettings({
    this.density,
    this.zebra = false,
    this.stickyHeader = true,
    this.defaultColumns = const {},
  });

  /// Row density for tables; null = follow the theme's density.
  final AppDensity? density;

  /// Alternate row shading.
  final bool zebra;
  final bool stickyHeader;

  /// Grid id (e.g. `orders.list`) → the column ids shown by default, in
  /// order. People can still change their own columns.
  final Map<String, List<String>> defaultColumns;

  List<String>? columnsFor(String gridId) => defaultColumns[gridId];

  TableSettings copyWith({
    AppDensity? Function()? density,
    bool? zebra,
    bool? stickyHeader,
    Map<String, List<String>>? defaultColumns,
  }) =>
      TableSettings(
        density: density != null ? density() : this.density,
        zebra: zebra ?? this.zebra,
        stickyHeader: stickyHeader ?? this.stickyHeader,
        defaultColumns: defaultColumns ?? this.defaultColumns,
      );

  Map<String, dynamic> toMap() => {
        'density': density?.name,
        'zebra': zebra,
        'stickyHeader': stickyHeader,
        'defaultColumns': defaultColumns,
      };

  factory TableSettings.fromMap(Map<String, dynamic> m) {
    final cols = m['defaultColumns'];
    final density = m['density'];
    return TableSettings(
      density: density is String
          ? AppDensity.values.firstWhereOrNull((d) => d.name == density)
          : null,
      zebra: m['zebra'] == true,
      stickyHeader: m['stickyHeader'] != false,
      defaultColumns: {
        if (cols is Map)
          for (final MapEntry(:key, :value) in cols.entries.take(60))
            if (key is String && _strings(value).isNotEmpty)
              key: _strings(value),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TableSettings &&
      other.density == density &&
      other.zebra == zebra &&
      other.stickyHeader == stickyHeader &&
      _mapEq.equals(other.defaultColumns, defaultColumns);

  @override
  int get hashCode =>
      Object.hash(density, zebra, stickyHeader, _mapEq.hash(defaultColumns));
}

// ---- Alerts -----------------------------------------------------------------

/// Which alerts are raised, and when. Alert types are stored by name (see
/// `AlertType`), so this model doesn't depend on the alert service.
@immutable
class AlertSettings {
  const AlertSettings({
    this.disabledTypes = const {},
    this.contractWindowDays = 30,
    this.contractUrgentDays = 7,
    this.overdueLookbackDays = 90,
    this.campaignEndingDays = 7,
    this.lowMarginPercent = 10,
    this.minOrdersForMargin = 3,
    this.spendZ = 2.5,
    this.spendZHigh = 4,
    this.goalAtRiskPercent = 90,
  });

  /// `AlertType` names that are switched off for everyone.
  final Set<String> disabledTypes;

  /// Contracts expiring within this many days raise an alert…
  final int contractWindowDays;

  /// …which is urgent within this many.
  final int contractUrgentDays;

  /// Expired contracts stay on the list this long.
  final int overdueLookbackDays;
  final int campaignEndingDays;

  /// Products under this net margin (%) are flagged.
  final double lowMarginPercent;
  final int minOrdersForMargin;

  /// How unusual spend must be (robust z-score) to be flagged, and to be
  /// urgent.
  final double spendZ;
  final double spendZHigh;

  /// A goal projected to land under this % of its target is at risk.
  final int goalAtRiskPercent;

  bool isOn(String typeName) => !disabledTypes.contains(typeName);

  AlertSettings copyWith({
    Set<String>? disabledTypes,
    int? contractWindowDays,
    int? contractUrgentDays,
    int? overdueLookbackDays,
    int? campaignEndingDays,
    double? lowMarginPercent,
    int? minOrdersForMargin,
    double? spendZ,
    double? spendZHigh,
    int? goalAtRiskPercent,
  }) =>
      AlertSettings.fromMap(AlertSettings(
        disabledTypes: disabledTypes ?? this.disabledTypes,
        contractWindowDays: contractWindowDays ?? this.contractWindowDays,
        contractUrgentDays: contractUrgentDays ?? this.contractUrgentDays,
        overdueLookbackDays: overdueLookbackDays ?? this.overdueLookbackDays,
        campaignEndingDays: campaignEndingDays ?? this.campaignEndingDays,
        lowMarginPercent: lowMarginPercent ?? this.lowMarginPercent,
        minOrdersForMargin: minOrdersForMargin ?? this.minOrdersForMargin,
        spendZ: spendZ ?? this.spendZ,
        spendZHigh: spendZHigh ?? this.spendZHigh,
        goalAtRiskPercent: goalAtRiskPercent ?? this.goalAtRiskPercent,
      ).toMap());

  Map<String, dynamic> toMap() => {
        'disabledTypes': disabledTypes.toList()..sort(),
        'contractWindowDays': contractWindowDays,
        'contractUrgentDays': contractUrgentDays,
        'overdueLookbackDays': overdueLookbackDays,
        'campaignEndingDays': campaignEndingDays,
        'lowMarginPercent': lowMarginPercent,
        'minOrdersForMargin': minOrdersForMargin,
        'spendZ': spendZ,
        'spendZHigh': spendZHigh,
        'goalAtRiskPercent': goalAtRiskPercent,
      };

  /// Clamped to sensible ranges; the urgent window never exceeds the alert
  /// window, nor the urgent z-score fall below the flagging one.
  factory AlertSettings.fromMap(Map<String, dynamic> m) {
    final window = _int(m['contractWindowDays'], 30, min: 7, max: 120);
    final z = _double(m['spendZ'], 2.5, min: 1.5, max: 6);
    return AlertSettings(
      disabledTypes: _strings(m['disabledTypes']).toSet(),
      contractWindowDays: window,
      contractUrgentDays:
          _int(m['contractUrgentDays'], 7, min: 1, max: 30).clamp(1, window),
      overdueLookbackDays:
          _int(m['overdueLookbackDays'], 90, min: 0, max: 365),
      campaignEndingDays: _int(m['campaignEndingDays'], 7, min: 1, max: 30),
      lowMarginPercent: _double(m['lowMarginPercent'], 10, min: 0, max: 50),
      minOrdersForMargin: _int(m['minOrdersForMargin'], 3, min: 1, max: 50),
      spendZ: z,
      spendZHigh: _double(m['spendZHigh'], 4, min: 1.5, max: 10).clamp(z, 10),
      goalAtRiskPercent: _int(m['goalAtRiskPercent'], 90, min: 50, max: 100),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AlertSettings &&
      _setEq.equals(other.disabledTypes, disabledTypes) &&
      other.contractWindowDays == contractWindowDays &&
      other.contractUrgentDays == contractUrgentDays &&
      other.overdueLookbackDays == overdueLookbackDays &&
      other.campaignEndingDays == campaignEndingDays &&
      other.lowMarginPercent == lowMarginPercent &&
      other.minOrdersForMargin == minOrdersForMargin &&
      other.spendZ == spendZ &&
      other.spendZHigh == spendZHigh &&
      other.goalAtRiskPercent == goalAtRiskPercent;

  @override
  int get hashCode => Object.hash(
      _setEq.hash(disabledTypes),
      contractWindowDays,
      contractUrgentDays,
      overdueLookbackDays,
      campaignEndingDays,
      lowMarginPercent,
      minOrdersForMargin,
      spendZ,
      spendZHigh,
      goalAtRiskPercent);
}

// ---- Sync & smart -----------------------------------------------------------

@immutable
class SyncSettings {
  const SyncSettings({this.autoRefreshMinutes = 30});

  static const choices = [0, 5, 15, 30, 60];

  /// Re-read from the server when the tab comes back after this long;
  /// 0 = only on "Sync now". Each sync costs reads, so keep it modest.
  final int autoRefreshMinutes;

  Duration? get staleAfter => autoRefreshMinutes == 0
      ? null
      : Duration(minutes: autoRefreshMinutes);

  Map<String, dynamic> toMap() => {'autoRefreshMinutes': autoRefreshMinutes};

  factory SyncSettings.fromMap(Map<String, dynamic> m) {
    final v = m['autoRefreshMinutes'];
    return SyncSettings(
        autoRefreshMinutes: v is int && choices.contains(v) ? v : 30);
  }

  @override
  bool operator ==(Object other) =>
      other is SyncSettings && other.autoRefreshMinutes == autoRefreshMinutes;

  @override
  int get hashCode => autoRefreshMinutes.hashCode;
}

/// On-device AI (P5).
@immutable
class SmartSettings {
  const SmartSettings({this.minRows = 50, this.wipeOnSignOut = true});

  /// Records needed before a learned model replaces the simple rules.
  final int minRows;

  /// Clear on-device AI data when someone signs out.
  final bool wipeOnSignOut;

  SmartSettings copyWith({int? minRows, bool? wipeOnSignOut}) => SmartSettings(
        minRows: minRows ?? this.minRows,
        wipeOnSignOut: wipeOnSignOut ?? this.wipeOnSignOut,
      );

  Map<String, dynamic> toMap() =>
      {'minRows': minRows, 'wipeOnSignOut': wipeOnSignOut};

  factory SmartSettings.fromMap(Map<String, dynamic> m) => SmartSettings(
        minRows: _int(m['minRows'], 50, min: 20, max: 500),
        wipeOnSignOut: m['wipeOnSignOut'] != false,
      );

  @override
  bool operator ==(Object other) =>
      other is SmartSettings &&
      other.minRows == minRows &&
      other.wipeOnSignOut == wipeOnSignOut;

  @override
  int get hashCode => Object.hash(minRows, wipeOnSignOut);
}
