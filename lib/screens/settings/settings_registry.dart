import 'package:flutter/material.dart';

import 'sections/access_section.dart';
import 'sections/ai_section.dart';
import 'sections/alerts_section.dart';
import 'sections/appearance_section.dart';
import 'sections/audit_section.dart';
import 'sections/branding_section.dart';
import 'sections/danger_zone_section.dart';
import 'sections/dashboard_section.dart';
import 'sections/defaults_section.dart';
import 'sections/diagnostics_section.dart';
import 'sections/features_section.dart';
import 'sections/firebase_section.dart';
import 'sections/modules_section.dart';
import 'sections/navigation_section.dart';
import 'sections/notifications_section.dart';
import 'sections/password_section.dart';
import 'sections/profile_section.dart';
import 'sections/shortcuts_section.dart';
import 'sections/smart_section.dart';
import 'sections/tables_section.dart';
import 'sections/theme_section.dart';
import 'sections/whats_new_section.dart';
import 'settings_draft.dart';

/// Who a settings section is for.
enum SettingsGroup {
  personal('Personal'),
  organisation('Organisation'),
  system('System');

  const SettingsGroup(this.label);
  final String label;
}

/// One entry in the Settings list.
class SettingsSectionDef {
  const SettingsSectionDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.group,
    required this.builder,
    this.keywords = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final SettingsGroup group;

  /// Extra words the search matches besides the title.
  final List<String> keywords;

  /// Builds the section. [draft] is the shared organisation draft; personal
  /// and system sections ignore it.
  final Widget Function(BuildContext context, SettingsDraft draft) builder;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        subtitle.toLowerCase().contains(q) ||
        keywords.any((k) => k.toLowerCase().contains(q));
  }
}

/// Every section, in display order.
final List<SettingsSectionDef> kSettingsSections = [
  // Personal
  SettingsSectionDef(
    id: 'profile',
    title: 'Profile',
    subtitle: 'Your account details',
    icon: Icons.person_outline,
    group: SettingsGroup.personal,
    keywords: const ['name', 'email', 'login', 'account', 'role'],
    builder: (_, _) => const ProfileSection(),
  ),
  SettingsSectionDef(
    id: 'password',
    title: 'Password',
    subtitle: 'Change how you sign in',
    icon: Icons.password,
    group: SettingsGroup.personal,
    keywords: const ['security', 'sign in', 'login'],
    builder: (_, _) => const PasswordSection(),
  ),
  SettingsSectionDef(
    id: 'appearance',
    title: 'Appearance',
    subtitle: 'Light or dark, motion and density',
    icon: Icons.palette_outlined,
    group: SettingsGroup.personal,
    keywords: const ['theme', 'dark', 'light', 'reduce motion', 'compact'],
    builder: (_, _) => const AppearanceSection(),
  ),
  SettingsSectionDef(
    id: 'notifications',
    title: 'Notifications',
    subtitle: 'Choose which alerts you see',
    icon: Icons.notifications_outlined,
    group: SettingsGroup.personal,
    keywords: const ['alerts', 'hide', 'mute'],
    builder: (_, _) => const NotificationsSection(),
  ),
  SettingsSectionDef(
    id: 'ai',
    title: 'On-device AI',
    subtitle: 'Smarter forecasts and suggestions, on this device',
    icon: Icons.auto_awesome_outlined,
    group: SettingsGroup.personal,
    keywords: const [
      'ai',
      'smart',
      'tensorflow',
      'forecast',
      'suggestions',
      'privacy',
      'clear',
      'learning',
    ],
    builder: (_, _) => const AiSection(),
  ),
  SettingsSectionDef(
    id: 'shortcuts',
    title: 'Shortcuts',
    subtitle: 'Keyboard shortcuts',
    icon: Icons.keyboard_outlined,
    group: SettingsGroup.personal,
    keywords: const ['keyboard', 'keys', 'hotkeys'],
    builder: (_, _) => const ShortcutsSection(),
  ),
  SettingsSectionDef(
    id: 'whatsnew',
    title: 'What’s new',
    subtitle: 'Your version and release notes',
    icon: Icons.new_releases_outlined,
    group: SettingsGroup.personal,
    keywords: const ['version', 'release notes', 'changelog', 'update'],
    builder: (_, _) => const WhatsNewSection(),
  ),

  // Organisation
  SettingsSectionDef(
    id: 'branding',
    title: 'Branding',
    subtitle: 'Name, colour and logo',
    icon: Icons.brush_outlined,
    group: SettingsGroup.organisation,
    keywords: const ['app name', 'logo', 'colour', 'color', 'tagline'],
    builder: (_, d) => BrandingSection(draft: d),
  ),
  SettingsSectionDef(
    id: 'theme',
    title: 'Theme',
    subtitle: 'Default mode, corners and charts',
    icon: Icons.contrast,
    group: SettingsGroup.organisation,
    keywords: const ['dark', 'light', 'corners', 'chart', 'motion', 'density'],
    builder: (_, d) => ThemeSection(draft: d),
  ),
  SettingsSectionDef(
    id: 'navigation',
    title: 'Navigation',
    subtitle: 'Landing page and mobile bar',
    icon: Icons.alt_route,
    group: SettingsGroup.organisation,
    keywords: const ['landing', 'home', 'bottom bar', 'menu'],
    builder: (_, d) => NavigationSection(draft: d),
  ),
  SettingsSectionDef(
    id: 'modules',
    title: 'Modules',
    subtitle: 'Choose which areas are shown',
    icon: Icons.apps,
    group: SettingsGroup.organisation,
    keywords: const ['hide', 'show', 'menus', 'pages'],
    builder: (_, d) => ModulesSection(draft: d),
  ),
  SettingsSectionDef(
    id: 'features',
    title: 'Features',
    subtitle: 'Turn individual features on or off',
    icon: Icons.toggle_on_outlined,
    group: SettingsGroup.organisation,
    keywords: const ['switch', 'enable', 'disable'],
    builder: (_, d) => FeaturesSection(draft: d),
  ),
  SettingsSectionDef(
    id: 'defaults',
    title: 'Defaults',
    subtitle: 'Currency, dates and periods',
    icon: Icons.tune,
    group: SettingsGroup.organisation,
    keywords: const [
      'currency',
      'date format',
      'financial year',
      'fy',
      'page size',
      'refresh',
      'number',
    ],
    builder: (_, d) => DefaultsSection(draft: d),
  ),
  SettingsSectionDef(
    id: 'dashboard',
    title: 'Dashboard',
    subtitle: 'Sections and headline figures',
    icon: Icons.dashboard_outlined,
    group: SettingsGroup.organisation,
    keywords: const ['kpi', 'hero', 'order', 'reorder', 'widgets'],
    builder: (_, d) => DashboardSection(draft: d),
  ),
  SettingsSectionDef(
    id: 'tables',
    title: 'Tables',
    subtitle: 'Density, stripes and columns',
    icon: Icons.table_rows_outlined,
    group: SettingsGroup.organisation,
    keywords: const ['zebra', 'sticky', 'columns', 'rows'],
    builder: (_, d) => TablesSection(draft: d),
  ),
  SettingsSectionDef(
    id: 'alerts',
    title: 'Alerts',
    subtitle: 'What raises an alert, and when',
    icon: Icons.notifications_active_outlined,
    group: SettingsGroup.organisation,
    keywords: const ['threshold', 'contract', 'margin', 'goal', 'spend'],
    builder: (_, d) => AlertsSection(draft: d),
  ),
  SettingsSectionDef(
    id: 'smart',
    title: 'Smart AI',
    subtitle: 'Suggestions from your own records',
    icon: Icons.auto_awesome_outlined,
    group: SettingsGroup.organisation,
    keywords: const ['ai', 'learning', 'privacy', 'on-device'],
    builder: (_, d) => SmartSection(draft: d),
  ),

  // System
  SettingsSectionDef(
    id: 'firebase',
    title: 'Firebase',
    subtitle: 'Connect your own project',
    icon: Icons.local_fire_department_outlined,
    group: SettingsGroup.system,
    keywords: const ['database', 'cloud', 'demo', 'connection'],
    builder: (_, _) => const FirebaseSection(),
  ),
  SettingsSectionDef(
    id: 'access',
    title: 'Users and access',
    subtitle: 'People and sign-in',
    icon: Icons.admin_panel_settings_outlined,
    group: SettingsGroup.system,
    keywords: const ['users', 'roles', 'sign-in index', 'login id'],
    builder: (_, _) => const AccessSection(),
  ),
  SettingsSectionDef(
    id: 'audit',
    title: 'Audit log',
    subtitle: 'Recent changes',
    icon: Icons.history,
    group: SettingsGroup.system,
    keywords: const ['history', 'activity', 'who changed'],
    builder: (_, _) => const AuditSection(),
  ),
  SettingsSectionDef(
    id: 'diagnostics',
    title: 'Diagnostics',
    subtitle: 'Reads, writes and problems',
    icon: Icons.monitor_heart_outlined,
    group: SettingsGroup.system,
    keywords: const ['usage', 'quota', 'reads', 'writes', 'errors', 'support'],
    builder: (_, _) => const DiagnosticsSection(),
  ),
  SettingsSectionDef(
    id: 'danger',
    title: 'Danger zone',
    subtitle: 'Actions that can’t be undone',
    icon: Icons.warning_amber_rounded,
    group: SettingsGroup.system,
    keywords: const ['reset', 'demo data', 'wipe'],
    builder: (_, _) => const DangerZoneSection(),
  ),
];
