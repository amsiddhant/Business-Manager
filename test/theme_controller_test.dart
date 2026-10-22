import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/theme/app_palette.dart';
import 'package:salesforce_business_manager/core/theme/theme_x.dart';
import 'package:salesforce_business_manager/state/theme_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _brands = <Color>[
  AppPalette.defaultBrand,
  Color(0xFF0B5FFF), // blue
  Color(0xFF0F766E), // teal
  Color(0xFFE11D48), // rose
  Color(0xFFF5C518), // yellow (light brand)
  Color(0xFF7DD3FC), // pale sky (light brand)
  Color(0xFF1E1B4B), // near-black indigo
];

String _hex(Color c) => c.toARGB32().toRadixString(16);

void main() {
  group('palette contrast (WCAG AA)', () {
    for (final brand in _brands) {
      for (final dark in [false, true]) {
        final name = '${_hex(brand)} ${dark ? 'dark' : 'light'}';
        test(name, () {
          final t = dark
              ? AppPalette.dark(brand: brand)
              : AppPalette.light(brand: brand);
          double on(Color a, Color b) => AppTokens.contrastRatio(a, b);

          // Text on the brand colour (filled buttons, selected chips).
          expect(on(t.textOnPrimary, t.primary), greaterThanOrEqualTo(4.5));
          // Body text on cards and the page canvas.
          expect(on(t.textPrimary, t.card), greaterThanOrEqualTo(4.5));
          expect(on(t.textPrimary, t.background), greaterThanOrEqualTo(4.5));
          expect(on(t.textSecondary, t.card), greaterThanOrEqualTo(4.5));
          // onColor always picks the readable side.
          expect(on(t.onColor(t.error), t.error), greaterThanOrEqualTo(4.5));
          if (dark) {
            // The brand and status colours are tone-shifted onto the surface.
            for (final c in [t.primary, t.success, t.warning, t.error, t.info]) {
              expect(on(c, t.card), greaterThanOrEqualTo(4.5),
                  reason: _hex(c));
            }
          }
        });
      }
    }

    test('the default light palette keeps the brand exactly', () {
      expect(AppPalette.light().primary.toARGB32(),
          AppPalette.defaultBrand.toARGB32());
    });

    test('dark mode is muted, never pure black', () {
      final t = AppPalette.dark();
      expect(t.background.toARGB32(), isNot(0xFF000000));
      expect(t.card.computeLuminance(), lessThan(0.05));
      expect(t.textPrimary.toARGB32(), isNot(0xFFFFFFFF));
    });
  });

  group('ThemeController', () {
    late SharedPreferences prefs;
    late UserPrefs user;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      user = UserPrefs(prefs)..bindUser('u1');
    });

    test('defaults to the organisation default (light)', () {
      final c = ThemeController(prefs, user);
      expect(c.mode, ThemeMode.light);
      expect(c.density, AppDensity.comfortable);
      expect(c.motion, MotionLevel.full);
      expect(c.canChooseMode, isTrue);
    });

    test("the user's choice wins, and notifies", () async {
      final c = ThemeController(prefs, user);
      var notified = 0;
      c.addListener(() => notified++);
      await user.setThemeMode(ThemeMode.dark);
      expect(c.mode, ThemeMode.dark);
      expect(notified, greaterThan(0));
      expect(c.brightnessFor(Brightness.light), Brightness.dark);
    });

    test('"System" follows the platform', () async {
      final c = ThemeController(prefs, user);
      await user.setThemeMode(ThemeMode.system);
      expect(c.brightnessFor(Brightness.dark), Brightness.dark);
      expect(c.brightnessFor(Brightness.light), Brightness.light);
    });

    test('when the admin locks the mode, user choices are ignored', () async {
      final c = ThemeController(prefs, user);
      await user.setThemeMode(ThemeMode.light);
      await c.applyOrgTheme(const OrgTheme(
        defaultMode: ThemeMode.dark,
        allowUserOverride: false,
      ));
      expect(c.canChooseMode, isFalse);
      expect(c.mode, ThemeMode.dark);
    });

    test('reduce motion caps the org level; density is per user', () async {
      final c = ThemeController(prefs, user);
      await user.setReduceMotion(true);
      expect(c.motion, MotionLevel.reduced);
      await c.applyOrgTheme(const OrgTheme(motion: MotionLevel.off));
      expect(c.motion, MotionLevel.off, reason: 'never more than the org');
      await user.setDensity(AppDensity.compact);
      expect(c.density, AppDensity.compact);
    });

    test('the org theme is cached for the next start (no flash)', () async {
      final c = ThemeController(prefs, user);
      const org = OrgTheme(
        brand: Color(0xFF0F766E),
        defaultMode: ThemeMode.dark,
        density: AppDensity.spacious,
      );
      await c.applyOrgTheme(org);

      final next = ThemeController(prefs, UserPrefs(prefs));
      expect(next.org, org);
      expect(next.mode, ThemeMode.dark);
      expect(next.density, AppDensity.spacious);
    });

    test('a corrupt cache falls back to the defaults', () async {
      await prefs.setString('sbm_org_theme_v1', '{not json');
      final c = ThemeController(prefs, user);
      expect(c.org, const OrgTheme());
    });
  });
}
