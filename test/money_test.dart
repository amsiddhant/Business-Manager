import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';

void main() {
  group('Money construction', () {
    test('stores minor units directly', () {
      expect(const Money(12345).minor, 12345);
      expect(const Money(12345).major, 123.45);
    });

    test('fromMajor rounds to nearest minor unit', () {
      expect(Money.fromMajor(123.45).minor, 12345);
      expect(Money.fromMajor(0.1).minor, 10);
      // 1/3 of a rupee rounds to the nearest paisa.
      expect(Money.fromMajor(0.333).minor, 33);
      expect(Money.fromMajor(0.335).minor, 34);
    });

    test('parse strips grouping and currency noise', () {
      expect(Money.parse('₹1,25,000').minor, 12500000);
      expect(Money.parse(r'$1,234.50').minor, 123450);
      expect(Money.parse('').minor, 0);
      expect(Money.parse('-').minor, 0);
      expect(Money.parse('abc').minor, 0);
    });
  });

  group('Money arithmetic (integer, no float drift)', () {
    test('addition and subtraction', () {
      expect((const Money(1000) + const Money(250)).minor, 1250);
      expect((const Money(1000) - const Money(250)).minor, 750);
      expect((const Money(100) - const Money(300)).minor, -200);
    });

    test('multiplication by quantity rounds', () {
      expect((const Money(999) * 3).minor, 2997);
      // 100.5 paise * 3 = 301.5 -> rounds to 302
      expect((const Money(1005) * 0.3).minor, 302);
    });

    test('division guards against divide-by-zero', () {
      expect((const Money(1000) / 0).minor, 0);
      expect((const Money(1000) / 4).minor, 250);
    });

    test('summing many small values stays exact', () {
      // 0.1 rupees added 10 times must equal exactly 1 rupee (100 paise).
      var total = Money.zero;
      for (var i = 0; i < 10; i++) {
        total = total + Money.fromMajor(0.1);
      }
      expect(total.minor, 100);
      expect(total.major, 1.0);
    });
  });

  group('Money comparisons', () {
    test('relational operators', () {
      expect(const Money(100) > const Money(50), isTrue);
      expect(const Money(50) < const Money(100), isTrue);
      expect(const Money(100) >= const Money(100), isTrue);
      expect(const Money(100) <= const Money(100), isTrue);
    });

    test('sign helpers', () {
      expect(Money.zero.isZero, isTrue);
      expect(const Money(-1).isNegative, isTrue);
      expect(const Money(1).isPositive, isTrue);
    });

    test('equality is value based', () {
      expect(const Money(500), equals(const Money(500)));
      expect(const Money(500).hashCode, const Money(500).hashCode);
    });
  });

  group('MoneyFormatter', () {
    test('INR uses Indian grouping', () {
      final formatted = MoneyFormatter.format(Money.fromMajor(125000), CurrencyCode.inr);
      expect(formatted, contains('1,25,000'));
      expect(formatted, startsWith('₹'));
    });

    test('whole amounts drop decimals, fractional keep two', () {
      expect(MoneyFormatter.format(const Money(100000), CurrencyCode.inr),
          isNot(contains('.')));
      expect(MoneyFormatter.format(const Money(100050), CurrencyCode.inr),
          contains('.50'));
    });

    test('compact INR uses lakh/crore', () {
      expect(MoneyFormatter.compact(Money.fromMajor(150000), CurrencyCode.inr),
          contains('L'));
      expect(MoneyFormatter.compact(Money.fromMajor(20000000), CurrencyCode.inr),
          contains('Cr'));
    });

    test('compact USD uses K/M', () {
      expect(MoneyFormatter.compact(Money.fromMajor(1500), CurrencyCode.usd),
          contains('K'));
      expect(MoneyFormatter.compact(Money.fromMajor(2000000), CurrencyCode.usd),
          contains('M'));
    });
  });

  group('PercentFormatter', () {
    test('formats percentages and guards non-finite', () {
      expect(PercentFormatter.format(37.8), '37.8%');
      expect(PercentFormatter.format(double.nan), '—');
      expect(PercentFormatter.format(double.infinity), '—');
    });

    test('roas renders multiples and N/A', () {
      expect(PercentFormatter.roas(2.5), '2.50x');
      expect(PercentFormatter.roas(null), 'N/A');
      expect(PercentFormatter.roas(double.infinity), 'N/A');
    });
  });
}
