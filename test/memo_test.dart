import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/state/memo.dart';

void main() {
  group('StampedMemo', () {
    test('computes once per key while the stamp is unchanged', () {
      final memo = StampedMemo();
      var calls = 0;
      int compute() => ++calls;

      expect(memo.get(1, 'a', compute), 1);
      expect(memo.get(1, 'a', compute), 1);
      expect(memo.get(1, 'b', compute), 2);
      expect(calls, 2);
    });

    test('a new stamp drops every cached value', () {
      final memo = StampedMemo();
      var calls = 0;
      int compute() => ++calls;

      memo.get(1, 'a', compute);
      memo.get(1, 'b', compute);
      expect(memo.get(2, 'a', compute), 3);
      expect(memo.get(2, 'b', compute), 4);
    });

    test('record keys compare by value', () {
      final memo = StampedMemo();
      var calls = 0;
      memo.get(1, (#productsFor, 'BIZ-1'), () => ++calls);
      memo.get(1, (#productsFor, 'BIZ-1'), () => ++calls);
      memo.get(1, (#productsFor, null), () => ++calls);
      expect(calls, 2);
    });

    test('a null result is cached too', () {
      final memo = StampedMemo();
      var calls = 0;
      String? compute() {
        calls++;
        return null;
      }

      memo.get<String?>(1, 'k', compute);
      memo.get<String?>(1, 'k', compute);
      expect(calls, 1);
    });

    test('clear forgets everything', () {
      final memo = StampedMemo();
      var calls = 0;
      memo.get(1, 'a', () => ++calls);
      memo.clear();
      memo.get(1, 'a', () => ++calls);
      expect(calls, 2);
    });
  });
}
