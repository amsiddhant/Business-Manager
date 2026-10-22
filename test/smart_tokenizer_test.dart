import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/services/smart/smart_config.dart';
import 'package:salesforce_business_manager/services/smart/smart_tokenizer.dart';

void main() {
  test('hash is 32-bit FNV-1a', () {
    expect(SmartTokenizer.hash(''), 0x811c9dc5);
    expect(SmartTokenizer.hash('a'), 0xe40c292c);
    expect(SmartTokenizer.hash('foobar'), 0xbf9cf968);
    expect(SmartTokenizer.hash('Some text'), SmartTokenizer.hash('Some text'));
    expect(SmartTokenizer.hash('one'), isNot(SmartTokenizer.hash('two')));
    expect(SmartTokenizer.hash('a long enough text to overflow'),
        inInclusiveRange(0, 0xffffffff));
  });

  test('words are lower-case, 3+ chars, without filler', () {
    expect(SmartTokenizer.words('The AWS Hosting, for Acme Pvt Ltd - 24x7!'),
        ['aws', 'hosting', 'acme', '24x7']);
    expect(SmartTokenizer.words('a b to'), isEmpty);
  });

  group('encode', () {
    test('is deterministic with ids in [1, buckets)', () {
      final row = {'n': 'Google Workspace', 'v': 'Google', 'd': 'monthly seats'};
      final a = SmartTokenizer.encode(row);
      expect(a, SmartTokenizer.encode(row));
      expect(a.length, SmartConfig.tokens);
      for (final id in a) {
        expect(id, inInclusiveRange(1, SmartConfig.buckets - 1));
      }
    });

    test('field order does not matter', () {
      expect(SmartTokenizer.encode({'n': 'alpha beta', 'v': 'gamma'}),
          SmartTokenizer.encode({'v': 'gamma', 'n': 'alpha beta'}));
    });

    test('fills the slots cyclically', () {
      final ids = SmartTokenizer.encode({'n': 'alpha'}, length: 5);
      expect(ids.toSet().length, 1);
      final two = SmartTokenizer.encode({'n': 'alpha beta'}, length: 7);
      // Two words and their pair: three ids repeating.
      expect(two[3], two[0]);
      expect(two[4], two[1]);
      expect(two[6], two[0]);
      expect(two.take(3).toSet().length, 3);
    });

    test('a row with no words is the id of <empty>', () {
      final expected = 1 +
          SmartTokenizer.hash('<empty>') % (SmartConfig.buckets - 1);
      expect(SmartTokenizer.encode({'n': 'a', 'v': ''}).toSet(), {expected});
      expect(SmartTokenizer.encode(const {}).toSet(), {expected});
    });

    test('stop words are dropped', () {
      expect(SmartTokenizer.encode({'n': 'the plan'}),
          SmartTokenizer.encode(const {}));
      expect(SmartTokenizer.encode({'n': 'the hosting plan'}),
          SmartTokenizer.encode({'n': 'hosting'}));
    });

    test('the field tag changes the ids', () {
      expect(SmartTokenizer.encode({'n': 'amazon'}),
          isNot(SmartTokenizer.encode({'v': 'amazon'})));
    });
  });

  test('encodeAll stacks the rows', () {
    final rows = [
      {'n': 'amazon'},
      {'n': 'google ads'},
    ];
    final all = SmartTokenizer.encodeAll(rows, length: 4);
    expect(all.length, 8);
    expect(all.sublist(0, 4), SmartTokenizer.encode(rows[0], length: 4));
    expect(all.sublist(4), SmartTokenizer.encode(rows[1], length: 4));
  });
}
