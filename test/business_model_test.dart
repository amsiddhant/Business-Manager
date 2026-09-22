import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/models/business.dart';

/// Unit tests for the [Business] lifecycle + tenure additions: the pure
/// `tenure(asOf)` calculation (active vs. closed, missing dates), the
/// active/closed lifecycle axis staying independent of visibility [status],
/// and the map round-trip persisting the new fields (with graceful defaults for
/// legacy documents written before these fields existed).
void main() {
  group('Business.tenure', () {
    test('active business measures start -> asOf', () {
      final b = Business(
        id: 'BIZ-1',
        name: 'Acme',
        startDate: DateTime(2022, 6, 15),
      );
      final t = b.tenure(DateTime(2026, 9, 20))!;
      expect(t.years, 4);
      expect(t.months, 3);
      expect(t.days, 5);
      expect(t.isPast, isFalse); // asOf is after start
    });

    test('closed business measures start -> endDate, ignoring asOf', () {
      final b = Business(
        id: 'BIZ-1',
        name: 'Acme',
        lifecycle: BusinessLifecycle.closed,
        startDate: DateTime(2020, 1, 1),
        endDate: DateTime(2023, 1, 1),
      );
      // asOf is years later, but the span must cap at the closure date.
      final t = b.tenure(DateTime(2026, 9, 20))!;
      expect(t.years, 3);
      expect(t.months, 0);
      expect(t.days, 0);
    });

    test('closed business without an end date falls back to asOf', () {
      final b = Business(
        id: 'BIZ-1',
        name: 'Acme',
        lifecycle: BusinessLifecycle.closed,
        startDate: DateTime(2024, 9, 20),
      );
      final t = b.tenure(DateTime(2026, 9, 20))!;
      expect(t.years, 2);
    });

    test('no start date yields null tenure', () {
      const b = Business(id: 'BIZ-1', name: 'Acme');
      expect(b.tenure(DateTime(2026, 9, 20)), isNull);
    });

    test('shortLabel gives a compact headline for the banner', () {
      final b = Business(
        id: 'BIZ-1',
        name: 'Acme',
        startDate: DateTime(2025, 3, 20),
      );
      expect(b.tenure(DateTime(2026, 9, 20))!.shortLabel, '1 yr 6 mo');
    });
  });

  group('Business lifecycle vs. status', () {
    test('isClosed tracks the lifecycle axis only', () {
      const active = Business(id: 'B', name: 'N');
      expect(active.isClosed, isFalse);
      expect(active.lifecycle, BusinessLifecycle.active);

      const closed =
          Business(id: 'B', name: 'N', lifecycle: BusinessLifecycle.closed);
      expect(closed.isClosed, isTrue);
      // Visibility status is unaffected by closing the business.
      expect(closed.status, EntityStatus.active);
      expect(closed.isActive, isTrue); // isActive reflects visibility, not trading
    });

    test('a closed business can still be archived independently', () {
      const b = Business(
        id: 'B',
        name: 'N',
        lifecycle: BusinessLifecycle.closed,
        status: EntityStatus.archived,
      );
      expect(b.isClosed, isTrue);
      expect(b.status, EntityStatus.archived);
    });
  });

  group('BusinessLifecycle.fromWire', () {
    test('parses known wires and defaults unknown/null to active', () {
      expect(BusinessLifecycle.fromWire('CLOSED'), BusinessLifecycle.closed);
      expect(BusinessLifecycle.fromWire('ACTIVE'), BusinessLifecycle.active);
      expect(BusinessLifecycle.fromWire(null), BusinessLifecycle.active);
      expect(BusinessLifecycle.fromWire('NONSENSE'), BusinessLifecycle.active);
    });
  });

  group('Business map round-trip', () {
    test('persists lifecycle, founders, owner and dates', () {
      final original = Business(
        id: 'BIZ-1',
        name: 'Acme',
        lifecycle: BusinessLifecycle.closed,
        foundedBy: 'Jane Doe',
        ownedBy: 'John Roe',
        startDate: DateTime(2020, 1, 1),
        endDate: DateTime(2023, 6, 30),
      );
      final restored = Business.fromMap(original.toMap());
      expect(restored.lifecycle, BusinessLifecycle.closed);
      expect(restored.foundedBy, 'Jane Doe');
      expect(restored.ownedBy, 'John Roe');
      expect(restored.startDate, DateTime(2020, 1, 1));
      expect(restored.endDate, DateTime(2023, 6, 30));
    });

    test('active business omits dates without error', () {
      const b = Business(id: 'BIZ-1', name: 'Acme');
      final map = b.toMap();
      expect(map.containsKey('startDate'), isFalse);
      expect(map.containsKey('endDate'), isFalse);
      final restored = Business.fromMap(map);
      expect(restored.startDate, isNull);
      expect(restored.endDate, isNull);
      expect(restored.lifecycle, BusinessLifecycle.active);
    });

    test('legacy document without new keys defaults gracefully', () {
      // Mimics a business written before these fields existed.
      final restored = Business.fromMap({
        'id': 'BIZ-1',
        'name': 'Acme',
        'status': 'ACTIVE',
      });
      expect(restored.lifecycle, BusinessLifecycle.active);
      expect(restored.foundedBy, '');
      expect(restored.ownedBy, '');
      expect(restored.startDate, isNull);
      expect(restored.endDate, isNull);
      expect(restored.tenure(DateTime(2026, 9, 20)), isNull);
    });
  });
}
