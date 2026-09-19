import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/widgets/common/status_badge.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('StatusBadge', () {
    testWidgets('renders the entity status label', (tester) async {
      await tester.pumpWidget(_wrap(StatusBadge.entity(EntityStatus.active)));
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('role badge shows the role label', (tester) async {
      await tester.pumpWidget(_wrap(StatusBadge.role(UserRole.owner)));
      expect(find.text('Owner'), findsOneWidget);
    });

    testWidgets('order badge shows the order status label', (tester) async {
      await tester.pumpWidget(_wrap(StatusBadge.order(OrderStatus.delivered)));
      expect(find.text('Delivered'), findsOneWidget);
    });

    testWidgets('custom label + tone renders', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatusBadge(label: 'Connected', tone: BadgeTone.success)),
      );
      expect(find.text('Connected'), findsOneWidget);
    });
  });
}
