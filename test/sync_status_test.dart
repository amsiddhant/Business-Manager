import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/widgets/layout/sync_status.dart';

void main() {
  final now = DateTime(2026, 10, 22, 12);

  test('syncedAgoLabel', () {
    expect(syncedAgoLabel(null, now), isNull);
    expect(syncedAgoLabel(now.subtract(const Duration(seconds: 30)), now),
        'Synced just now');
    expect(syncedAgoLabel(now.subtract(const Duration(minutes: 5)), now),
        'Synced 5 min ago');
    expect(syncedAgoLabel(now.subtract(const Duration(hours: 1)), now),
        'Synced 1 hr ago');
    expect(syncedAgoLabel(now.subtract(const Duration(hours: 3)), now),
        'Synced 3 hrs ago');
    expect(syncedAgoLabel(now.subtract(const Duration(days: 1)), now),
        'Synced 1 day ago');
    expect(syncedAgoLabel(now.subtract(const Duration(days: 4)), now),
        'Synced 4 days ago');
  });
}
