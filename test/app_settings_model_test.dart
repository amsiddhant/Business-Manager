import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/routing/app_routes.dart';
import 'package:salesforce_business_manager/core/theme/app_density.dart';
import 'package:salesforce_business_manager/core/theme/app_motion.dart';
import 'package:salesforce_business_manager/core/theme/app_palette.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('a missing or empty document means all defaults', () {
      expect(AppSettings.fromMap(null), const AppSettings());
      expect(AppSettings.fromMap(const {}), const AppSettings());
      final d = AppSettings.fromMap(null);
      expect(d.branding.appName, BrandingSettings.defaultAppName);
      expect(d.branding.brand, AppPalette.defaultBrand);
      expect(d.defaults.fyStartMonth, FinancialYear.defaultStartMonth);
      expect(d.defaults.pageSize, 25);
      expect(d.sync.autoRefreshMinutes, 30);
      expect(d.modules.disabled, isEmpty);
      expect(d.features.disabled, isEmpty);
    });

    test('toMap/fromMap round-trips every section', () {
      final s = AppSettings(
        branding: const BrandingSettings(
          appName: 'Acme Ops',
          shortName: 'Acme',
          tagline: 'Everything in one place',
          primaryColor: 0xFF0B7A75,
          logoHash: 'abc123-4096',
          showLogoOnLogin: false,
        ),
        theme: const ThemeSettings(
          defaultMode: ThemeMode.dark,
          allowUserOverride: false,
          density: AppDensity.compact,
          motion: MotionLevel.reduced,
          corners: CornerStyle.rounded,
          chartPalette: ChartPaletteStyle.calm,
        ),
        navigation: const NavigationSettings(
          mobilePrimary: [Routes.orders, Routes.customers],
          landingRoute: Routes.orders,
        ),
        modules: const ModuleSettings(disabled: {Routes.dealers}),
        features: const FeatureSettings(
            disabled: {AppFeature.csvImport, AppFeature.whatsNew}),
        defaults: const DefaultSettings(
          currency: CurrencyCode.usd,
          dateFormat: 'yyyy-MM-dd',
          numberGrouping: NumberGrouping.international,
          period: PeriodType.month,
          comparison: ComparisonBasis.lastYear,
          fyStartMonth: 1,
          orderStatus: OrderStatus.confirmed,
          pageSize: 50,
        ),
        dashboard: const DashboardSettings(
          order: ['charts', 'hero'],
          hidden: {'tables'},
          heroKpis: ['revenue', 'orders', 'units', 'netProfit'],
        ),
        tables: const TableSettings(
          density: AppDensity.spacious,
          zebra: true,
          stickyHeader: false,
          defaultColumns: {
            'orders.list': ['id', 'date', 'total'],
          },
        ),
        alerts: const AlertSettings(
          disabledTypes: {'lowMargin'},
          contractWindowDays: 45,
          contractUrgentDays: 10,
          overdueLookbackDays: 30,
          campaignEndingDays: 14,
          lowMarginPercent: 12.5,
          minOrdersForMargin: 5,
          spendZ: 3,
          spendZHigh: 5,
          goalAtRiskPercent: 80,
        ),
        sync: const SyncSettings(autoRefreshMinutes: 0),
        smart: const SmartSettings(minRows: 100, wipeOnSignOut: false),
        updatedAt: DateTime.utc(2026, 10, 22, 9, 30),
        updatedBy: 'Owner',
      );
      final back = AppSettings.fromMap(s.toMap());
      expect(back, s);
      expect(back.toMap()['schemaVersion'], AppSettings.schemaVersion);
      expect(back.sync.staleAfter, isNull);
    });

    test('sameAs ignores who saved and when', () {
      const a = AppSettings();
      final b = a.copyWith(updatedAt: DateTime(2026), updatedBy: 'Admin');
      expect(a.sameAs(b), isTrue);
      expect(a == b, isFalse);
      expect(
          a.sameAs(a.copyWith(
              branding: a.branding.copyWith(appName: 'Something else'))),
          isFalse);
    });

    test('wrong types and unknown values fall back to defaults', () {
      final s = AppSettings.fromMap({
        'branding': 'not a map',
        'theme': {
          'defaultMode': 'neon',
          'corners': 7,
          'chartPalette': 'rainbow',
        },
        'navigation': {
          'landingRoute': '/nowhere',
          'mobilePrimary': ['/orders', '/nowhere', '/orders', 3],
        },
        'modules': {
          'disabled': [Routes.dashboard, Routes.settings, Routes.orders, 'x'],
        },
        'features': {
          'disabled': ['csvExport', 'teleport'],
        },
        'defaults': {
          'currency': 'XYZ',
          'dateFormat': 'yy',
          'period': 'custom',
          'fyStartMonth': 5,
          'orderStatus': 'LOST',
          'pageSize': 33,
        },
        'dashboard': {
          'heroKpis': ['revenue', 'orders', 'revenue'],
        },
        'sync': {'autoRefreshMinutes': 7},
        'updatedAt': 12,
      });
      expect(s.branding, const BrandingSettings());
      expect(s.theme, const ThemeSettings());
      expect(s.navigation.landingRoute, Routes.dashboard);
      expect(s.navigation.mobilePrimary, [Routes.orders]);
      // Always-on sections can't be switched off; unknown ids are dropped.
      expect(s.modules.disabled, {Routes.orders});
      expect(s.features.disabled, {AppFeature.csvExport});
      expect(s.defaults, const DefaultSettings());
      // Not exactly four (after de-duplicating) = the built-in choice.
      expect(s.dashboard.heroKpis, isEmpty);
      expect(s.sync.autoRefreshMinutes, 30);
      expect(s.updatedAt, isNull);
    });

    test('text is trimmed and capped', () {
      final b = BrandingSettings.fromMap({
        'appName': '  ${'A' * 100}  ',
        'shortName': 'S' * 50,
        'tagline': '   ',
      });
      expect(b.appName.length, BrandingSettings.maxAppName);
      expect(b.shortName.length, BrandingSettings.maxShortName);
      expect(b.tagline, '');
    });

    test('the brand colour is always opaque', () {
      final b = BrandingSettings.fromMap({'primaryColor': 0x000B7A75});
      expect(b.primaryColor, 0xFF0B7A75);
      expect(b.brand.a, 1.0);
      expect(BrandingSettings.fromMap({'logoHash': ''}).hasLogo, isFalse);
      expect(BrandingSettings.fromMap({'logoHash': 'x' * 65}).hasLogo, isFalse);
      expect(BrandingSettings.fromMap({'logoHash': 'abc'}).hasLogo, isTrue);
    });

    test('nullable fields can be cleared through copyWith', () {
      const b = BrandingSettings(primaryColor: 0xFF112233, logoHash: 'h');
      final cleared = b.copyWith(primaryColor: () => null, logoHash: () => null);
      expect(cleared.primaryColor, isNull);
      expect(cleared.hasLogo, isFalse);
      const d = DefaultSettings(orderStatus: OrderStatus.shipped);
      expect(d.copyWith(orderStatus: () => null).orderStatus, isNull);
      const t = TableSettings(density: AppDensity.compact);
      expect(t.copyWith(density: () => null).density, isNull);
    });
  });

  group('ModuleSettings', () {
    test('switching a section off hides it and its detail pages', () {
      final m =
          const ModuleSettings().toggle(Routes.orders, enabled: false);
      expect(m.isEnabled(Routes.orders), isFalse);
      expect(m.allows('/orders'), isFalse);
      expect(m.allows('/orders/ORD-000001'), isFalse);
      expect(m.allows('/customers'), isTrue);
      expect(m.toggle(Routes.orders, enabled: true), const ModuleSettings());
    });

    test('always-on sections stay on', () {
      const m = ModuleSettings(disabled: {Routes.dashboard, Routes.settings});
      for (final r in ModuleSettings.alwaysOn) {
        expect(m.isEnabled(r), isTrue, reason: r);
      }
      expect(m.allows('/'), isTrue);
    });

    test('every optional section is a navigation destination', () {
      final routes = {for (final d in kNavDestinations) d.route};
      for (final r in ModuleSettings.optional) {
        expect(routes, contains(r));
        expect(ModuleSettings.alwaysOn, isNot(contains(r)));
      }
    });
  });

  test('FeatureSettings toggles a feature', () {
    final f =
        const FeatureSettings().toggle(AppFeature.bulkActions, enabled: false);
    expect(f.isOn(AppFeature.bulkActions), isFalse);
    expect(f.isOn(AppFeature.csvExport), isTrue);
    expect(FeatureSettings.fromMap(f.toMap()), f);
    expect(f.toggle(AppFeature.bulkActions, enabled: true),
        const FeatureSettings());
  });

  group('DashboardSettings.arrange', () {
    const builtIn = ['hero', 'attention', 'goals', 'charts', 'tables'];

    test('empty order keeps the built-in order', () {
      expect(const DashboardSettings().arrange(builtIn), builtIn);
    });

    test('listed sections come first, the rest keep their place', () {
      const d = DashboardSettings(order: ['charts', 'unknown', 'hero']);
      expect(d.arrange(builtIn),
          ['charts', 'hero', 'attention', 'goals', 'tables']);
    });

    test('hidden sections are reported as not visible', () {
      const d = DashboardSettings(hidden: {'goals'});
      expect(d.isVisible('goals'), isFalse);
      expect(d.isVisible('hero'), isTrue);
    });
  });

  group('AlertSettings', () {
    test('thresholds are clamped to sensible ranges', () {
      final a = AlertSettings.fromMap({
        'contractWindowDays': 1000,
        'contractUrgentDays': -5,
        'overdueLookbackDays': 9999,
        'campaignEndingDays': 0,
        'lowMarginPercent': 99,
        'minOrdersForMargin': 0,
        'spendZ': 0.1,
        'spendZHigh': 50,
        'goalAtRiskPercent': 10,
      });
      expect(a.contractWindowDays, 120);
      expect(a.contractUrgentDays, 1);
      expect(a.overdueLookbackDays, 365);
      expect(a.campaignEndingDays, 1);
      expect(a.lowMarginPercent, 50);
      expect(a.minOrdersForMargin, 1);
      expect(a.spendZ, 1.5);
      expect(a.spendZHigh, 10);
      expect(a.goalAtRiskPercent, 50);
    });

    test('the urgent window never exceeds the alert window', () {
      final a = AlertSettings.fromMap(
          {'contractWindowDays': 10, 'contractUrgentDays': 25});
      expect(a.contractUrgentDays, 10);
    });

    test('the urgent z-score never falls below the flagging one', () {
      final a = AlertSettings.fromMap({'spendZ': 5, 'spendZHigh': 2});
      expect(a.spendZHigh, 5);
    });

    test('copyWith clamps too', () {
      final a = const AlertSettings().copyWith(contractWindowDays: 3);
      expect(a.contractWindowDays, 7);
      expect(a.contractUrgentDays, 7);
    });

    test('isOn reads the disabled type names', () {
      const a = AlertSettings(disabledTypes: {'lowMargin'});
      expect(a.isOn('lowMargin'), isFalse);
      expect(a.isOn('campaignEnding'), isTrue);
    });
  });

  test('TableSettings drops empty or malformed default columns', () {
    final t = TableSettings.fromMap({
      'defaultColumns': {
        'orders.list': ['id', 'total'],
        'customers.list': <String>[],
        'products.list': 'id',
      },
    });
    expect(t.defaultColumns.keys, ['orders.list']);
    expect(t.columnsFor('orders.list'), ['id', 'total']);
    expect(t.columnsFor('customers.list'), isNull);
    expect(t.stickyHeader, isTrue);
    expect(t.zebra, isFalse);
  });

  test('SmartSettings clamps the row minimum', () {
    expect(SmartSettings.fromMap({'minRows': 1}).minRows, 20);
    expect(SmartSettings.fromMap({'minRows': 10000}).minRows, 500);
  });
}
