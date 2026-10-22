import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/theme/theme_x.dart';

void main() {
  group('AppMotion', () {
    test('full motion: the documented durations, and movement', () {
      const m = AppMotion(MotionLevel.full);
      expect(m.fast, const Duration(milliseconds: 120));
      expect(m.base, const Duration(milliseconds: 200));
      expect(m.slow, const Duration(milliseconds: 320));
      expect(m.chart, const Duration(milliseconds: 650));
      expect(m.stagger, const Duration(milliseconds: 40));
      expect(m.allowsMovement, isTrue);
    });

    test('reduced motion: fades keep their timing, nothing moves', () {
      const m = AppMotion(MotionLevel.reduced);
      expect(m.base, const Duration(milliseconds: 200));
      expect(m.allowsMovement, isFalse);
      expect(m.chart, Duration.zero);
      expect(m.stagger, Duration.zero);
    });

    test('motion off: every duration is zero', () {
      const m = AppMotion(MotionLevel.off);
      expect(m.enabled, isFalse);
      for (final d in [m.fast, m.base, m.slow, m.chart, m.stagger]) {
        expect(d, Duration.zero);
      }
    });

    test('atMost picks the stricter level', () {
      expect(MotionLevel.full.atMost(MotionLevel.reduced), MotionLevel.reduced);
      expect(MotionLevel.off.atMost(MotionLevel.reduced), MotionLevel.off);
      expect(MotionLevel.reduced.atMost(MotionLevel.full), MotionLevel.reduced);
    });

    test('fromName tolerates unknown values', () {
      expect(MotionLevel.fromName('off'), MotionLevel.off);
      expect(MotionLevel.fromName('nonsense'), MotionLevel.full);
      expect(MotionLevel.fromName(null), MotionLevel.full);
    });
  });

  group('context.motion', () {
    Future<AppMotion> motionIn(WidgetTester tester,
        {MotionLevel? level, bool osReduce = false}) async {
      late AppMotion motion;
      await tester.pumpWidget(MaterialApp(
        // A fresh app each time: MaterialApp animates between themes, so a
        // reused one would still report the previous level on this frame.
        key: UniqueKey(),
        theme: level == null ? null : ThemeData(extensions: [AppMotion(level)]),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: osReduce),
          child: Builder(builder: (context) {
            motion = context.motion;
            return const SizedBox();
          }),
        ),
      ));
      return motion;
    }

    testWidgets('defaults to full motion', (tester) async {
      expect((await motionIn(tester)).level, MotionLevel.full);
    });

    testWidgets("the OS 'reduce motion' setting caps it", (tester) async {
      expect((await motionIn(tester, osReduce: true)).level,
          MotionLevel.reduced);
    });

    testWidgets('the app setting applies, and the OS can only lower it',
        (tester) async {
      expect((await motionIn(tester, level: MotionLevel.off, osReduce: true))
              .level,
          MotionLevel.off);
      expect((await motionIn(tester, level: MotionLevel.reduced)).level,
          MotionLevel.reduced);
    });
  });
}
