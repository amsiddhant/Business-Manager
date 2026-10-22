/// One entry on the "What's new" page.
class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.title,
    required this.highlights,
  });

  final String version;

  /// Month and year, e.g. "October 2026".
  final String date;
  final String title;

  /// What changed, in the words a user would use.
  final List<String> highlights;
}

/// Every release, newest first. Add an entry with each version bump.
const List<ReleaseNote> kReleaseNotes = [
  ReleaseNote(
    version: '1.1.0',
    date: 'October 2026',
    title: 'Faster, and saves are instant',
    highlights: [
      'Saving, editing and deleting update the screen straight away, without '
          'reloading everything.',
      'The app opens faster: your last data shows at once while the latest '
          'loads in the background.',
      'The top bar shows when your data last synced. Use Sync now to pick up '
          "other people's changes.",
      'Signing in with your login ID works for everyone. You can also sign in '
          'with your email address.',
      'Campaigns have a Type field, and expenses a Description field.',
      "Opening a page you don't have access to shows a clear message.",
      'New versions reach you straight away, instead of an old copy staying '
          'cached in your browser.',
    ],
  ),
  ReleaseNote(
    version: '1.0.0',
    date: 'Initial release',
    title: 'Business Manager',
    highlights: [
      'Dashboard with profit scorecards, charts and tables.',
      'Businesses, products, campaigns, orders, expenses, dealers and '
          'customers.',
      'Reports with CSV export, and invoices for customers.',
      'Users with roles and per-person permissions.',
    ],
  ),
];
