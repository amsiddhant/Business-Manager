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
    version: '1.4.0',
    date: 'October 2026',
    title: 'Every page redesigned: smarter tables, easier forms',
    highlights: [
      'Every list and record page has a new look. Lists open with headline '
          'figures for what you are looking at, and record pages put the key '
          'numbers, status and actions right at the top.',
      'Tables are far more powerful: one-tap status filters, filters on any '
          'column, sorting, choosing and reordering columns, and saved views. '
          'Totals at the bottom follow your filters.',
      'Select several rows to change their status or delete them in one go.',
      'Export downloads exactly what you see: your search, filters and '
          'columns.',
      'On a phone, tables turn into easy-to-read cards.',
      'Forms open in a side panel (full screen on a phone) and are split into '
          'clear sections you can jump between. If a save fails, the form lists '
          'the fields that need attention.',
      'Forms keep an unsaved draft of new records. Close by accident and you '
          'will be offered your draft next time.',
      'Amounts use your business\'s currency and are grouped as you type '
          '(1,25,000). Date fields have Today and Clear buttons.',
      'Press Ctrl+Enter (⌘+Enter on Mac) to save a form, and Esc to close it.',
      'Duplicate an order to record a similar one in seconds. The order form '
          'shows revenue, cost and profit as you type.',
      'Forms suggest values from your own records, such as a product\'s last '
          'and typical price. Nothing is filled in until you tap a '
          'suggestion.',
      'Archived and inactive businesses can be restored from the list or '
          'the business page.',
    ],
  ),
  ReleaseNote(
    version: '1.3.0',
    date: 'October 2026',
    title: 'A new dashboard, and an alerts center',
    highlights: [
      'The dashboard is completely redesigned. It opens with a greeting, your '
          'four headline figures and how they changed, each with a 12-month '
          'trend line.',
      'Compare with the previous period or the same period last year. While '
          'a period is still running, both sides stop at today.',
      'See where the period is heading at your current pace, on the new '
          'Revenue & Profit Trend chart.',
      'New charts: a profit waterfall from revenue to net profit, spend by '
          'platform, return on ad spend by campaign, order status, and a '
          'side-by-side comparison of your businesses.',
      'Attention & insights picks out what changed: big moves in revenue or '
          'margin, one product carrying the sales, campaigns not paying back, '
          'and unusual spend.',
      'Tap any figure to open its report. Rows in the dashboard tables open '
          'the record, and search now finds every row, not just the top ten.',
      'Every chart can be viewed as a table.',
      'The new alerts center lists contracts expiring or overdue, campaigns '
          'ending, products with thin margins and unusual spend. Snooze or '
          'dismiss alerts; the bell shows how many need you.',
      'Works on any screen: on a phone the dashboard rearranges itself and '
          'the tables become simple lists.',
    ],
  ),
  ReleaseNote(
    version: '1.2.0',
    date: 'October 2026',
    title: 'New navigation, dark mode and quick search',
    highlights: [
      'A dark theme. Switch between Light, Dark and System from your profile '
          'menu.',
      'New navigation: sections are grouped in the sidebar, which you can '
          'collapse. Tablets get an icon rail, and phones a bottom bar.',
      'Pin any page to the sidebar for one-click access.',
      'Press Ctrl+K (⌘K on Mac) to search everything or jump anywhere. Press ? '
          'to see all keyboard shortcuts.',
      'Each section remembers where you were, and your business and period '
          'selection is kept when you come back.',
      'Press Ctrl+Enter in any form to save.',
      'Sign-in remembers your username and warns you when Caps Lock is on.',
      'Prefer fewer animations? Press Ctrl+K and choose Reduce motion. Your '
          "device's reduce-motion setting is respected too.",
    ],
  ),
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
