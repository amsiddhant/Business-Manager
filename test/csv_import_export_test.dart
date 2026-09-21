import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/csv_import.dart';
import 'package:salesforce_business_manager/core/utils/entity_csv.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/business.dart';
import 'package:salesforce_business_manager/models/customer.dart';
import 'package:salesforce_business_manager/models/product.dart';

/// Pure-layer tests for the CSV import/export feature: [CsvImport.parse],
/// [ProductCsv]/[CustomerCsv] row encode + parse, [BusinessResolver] and the
/// enum resolvers. No Firebase, no widgets — the repository re-enforces
/// permissions and business access on save, and that path is covered by the
/// repository tests. Also pins the three regressions the review confirmed:
/// delimiter auto-detect flipping, comma/pipe fragmentation of business names,
/// and Business-IDs precedence over names.
Business _biz(String id, String name) => Business(id: id, name: name);

void main() {
  // ---- csvNormalize --------------------------------------------------------

  group('csvNormalize', () {
    test('lowercases and strips spaces/punctuation for equivalent tokens', () {
      expect(csvNormalize('Deal Status'), csvNormalize('deal_status'));
      expect(csvNormalize('Deal Status'), csvNormalize('dealStatus'));
      expect(csvNormalize('  Business ID  '), 'businessid');
    });

    test('keeps digits, strips symbols to empty when all non-alnum', () {
      expect(csvNormalize('PROD-00001'), 'prod00001');
      expect(csvNormalize('—/•'), isEmpty);
    });
  });

  // ---- CsvImport.parse ------------------------------------------------------

  group('CsvImport.parse', () {
    test('returns null for empty and whitespace-only input', () {
      expect(CsvImport.parse(''), isNull);
      expect(CsvImport.parse('   \n  \r\n'), isNull);
    });

    test('returns null when header present but no data rows', () {
      expect(CsvImport.parse('Name,SKU\n'), isNull);
    });

    test('strips a leading UTF-8 BOM before decoding', () {
      final doc = CsvImport.parse('﻿Name,SKU\nWidget,W1')!;
      expect(doc.headers.first, 'Name');
      expect(doc.value(doc.rows.first, const ['Name']), 'Widget');
    });

    test('drops fully-blank rows but keeps partially-filled ones', () {
      final doc = CsvImport.parse('Name,SKU\nWidget,\n,\nGadget,G1')!;
      expect(doc.rows.length, 2);
      expect(doc.value(doc.rows[0], const ['Name']), 'Widget');
      expect(doc.value(doc.rows[1], const ['Name']), 'Gadget');
    });

    test('trims header and cell whitespace', () {
      final doc = CsvImport.parse('  Name ,  SKU \n  Widget ,  W1 ')!;
      expect(doc.headers, ['Name', 'SKU']);
      expect(doc.value(doc.rows.first, const ['SKU']), 'W1');
    });

    test('ragged short row yields empty string, not an error', () {
      final doc = CsvImport.parse('Name,SKU,Category\nWidget')!;
      expect(doc.value(doc.rows.first, const ['Category']), '');
    });

    test('quoted cell containing a comma decodes as one intact field', () {
      final doc = CsvImport.parse('Name,City\n"Acme, Inc.",Pune')!;
      expect(doc.value(doc.rows.first, const ['Name']), 'Acme, Inc.');
      expect(doc.value(doc.rows.first, const ['City']), 'Pune');
    });

    test("honours an Excel 'sep=;' hint line", () {
      final doc = CsvImport.parse('sep=;\nName;SKU\nWidget;W1')!;
      expect(doc.headers, ['Name', 'SKU']);
      expect(doc.value(doc.rows.first, const ['SKU']), 'W1');
    });

    test('REGRESSION: semicolon-heavy comma data keeps column structure', () {
      // A single quoted cell packed with semicolons used to fool delimiter
      // auto-detection into flipping the whole parse to ';'.
      final doc = CsvImport.parse('Name,Business IDs\n'
          'Widget,"BUS-1; BUS-2; BUS-3; BUS-4; BUS-5"')!;
      expect(doc.headers, ['Name', 'Business IDs']);
      expect(doc.value(doc.rows.first, const ['Name']), 'Widget');
      expect(doc.value(doc.rows.first, const ['Business IDs']),
          'BUS-1; BUS-2; BUS-3; BUS-4; BUS-5');
    });
  });

  // ---- CsvDocument alias resolution ----------------------------------------

  group('CsvDocument alias resolution', () {
    test('matches the first present alias, punctuation-insensitively', () {
      final doc = CsvImport.parse('Contact No,E-Mail\n99999,a@b.com')!;
      expect(doc.value(doc.rows.first, const ['Phone', 'Contact No']), '99999');
      expect(doc.value(doc.rows.first, const ['Email']), 'a@b.com');
    });

    test('returns empty when no alias names a present column', () {
      final doc = CsvImport.parse('Name\nWidget')!;
      expect(doc.value(doc.rows.first, const ['Nope']), '');
    });
  });

  // ---- ImportReport ---------------------------------------------------------

  group('ImportReport', () {
    test('accumulates counts and 1-based row-prefixed messages', () {
      final r = ImportReport()
        ..created = 2
        ..addError(4, 'boom');
      expect(r.failed, 1);
      expect(r.total, 3);
      expect(r.hasErrors, isTrue);
      expect(r.errors.single, 'Row 4: boom');
    });
  });

  // ---- BusinessResolver -----------------------------------------------------

  group('BusinessResolver', () {
    final resolver = BusinessResolver([
      _biz('BUS-1', 'Acme Store'),
      _biz('BUS-2', 'Beta Traders'),
    ]);

    test('resolves by id and by name, tolerating case/spacing', () {
      expect(resolver.resolve('bus-1')!.id, 'BUS-1');
      expect(resolver.resolve('  acme store ')!.id, 'BUS-1');
      expect(resolver.resolve('BETATRADERS')!.id, 'BUS-2');
    });

    test('unknown or empty token resolves to null', () {
      expect(resolver.resolve('BUS-9'), isNull);
      expect(resolver.resolve(''), isNull);
    });

    test('contains recognises accessible ids only', () {
      expect(resolver.contains('BUS-1'), isTrue);
      expect(resolver.contains('bus-2'), isTrue);
      expect(resolver.contains('BUS-9'), isFalse);
    });

    test('sole returns the single business, else null', () {
      expect(BusinessResolver([_biz('BUS-1', 'Solo')]).sole!.id, 'BUS-1');
      expect(resolver.sole, isNull);
    });

    test('id lookup wins when a token matches an id and another name', () {
      final r = BusinessResolver([
        _biz('SHARED', 'First'),
        _biz('BUS-2', 'SHARED'),
      ]);
      expect(r.resolve('SHARED')!.id, 'SHARED');
    });
  });

  // ---- ProductCsv -----------------------------------------------------------

  group('ProductCsv', () {
    final resolver = BusinessResolver([_biz('BUS-1', 'Acme Store')]);
    final multi = BusinessResolver(
        [_biz('BUS-1', 'Acme Store'), _biz('BUS-2', 'Beta Traders')]);

    test('row emits 11 columns with prices as major units and status label',
        () {
      final p = Product(id: 'PROD-1', businessId: 'BUS-1', name: 'Widget')
          .copyWith(
        sku: 'W1',
        buyingPrice: Money.fromMajor(100),
        sellingPrice: Money.fromMajor(150),
        status: EntityStatus.inactive,
      );
      final row = ProductCsv.row(p, businessName: 'Acme Store');
      expect(row.length, ProductCsv.header.length);
      expect(row[0], 'PROD-1');
      expect(row[5], 100.0);
      expect(row[6], 150.0);
      expect(row[8], 'Inactive');
      expect(row[10], 'Acme Store');
    });

    test('parseRow builds a fresh (blank-id) product in single-business scope',
        () {
      final doc = CsvImport.parse(
          'Name,SKU,Buying Price,Selling Price,Status\n'
          'Widget,W1,1234.50,1999,Inactive')!;
      final p = ProductCsv.parseRow(doc, doc.rows.first, resolver);
      expect(p.id, isEmpty);
      expect(p.businessId, 'BUS-1'); // sole business
      expect(p.name, 'Widget');
      expect(p.buyingPrice, Money.fromMajor(1234.50));
      expect(p.status, EntityStatus.inactive);
    });

    test('missing/blank name throws FormatException', () {
      final doc = CsvImport.parse('Name,SKU\n ,W1')!;
      expect(() => ProductCsv.parseRow(doc, doc.rows.first, resolver),
          throwsFormatException);
    });

    test('named business outside the accessible set is rejected', () {
      final doc = CsvImport.parse('Name,Business ID\nWidget,BUS-9')!;
      expect(() => ProductCsv.parseRow(doc, doc.rows.first, multi),
          throwsFormatException);
    });

    test('named business resolves by name when in scope', () {
      final doc = CsvImport.parse('Name,Business Name\nWidget,Beta Traders')!;
      final p = ProductCsv.parseRow(doc, doc.rows.first, multi);
      expect(p.businessId, 'BUS-2');
    });

    test('no business + multiple in scope + no fallback throws', () {
      final doc = CsvImport.parse('Name\nWidget')!;
      expect(() => ProductCsv.parseRow(doc, doc.rows.first, multi),
          throwsFormatException);
    });

    test('no business uses fallbackBusinessId over sole when provided', () {
      final doc = CsvImport.parse('Name\nWidget')!;
      final p = ProductCsv.parseRow(doc, doc.rows.first, multi,
          fallbackBusinessId: 'BUS-2');
      expect(p.businessId, 'BUS-2');
    });

    test('blank/garbage prices parse to zero; grouped prices parse exactly',
        () {
      final doc = CsvImport.parse('Name,Buying Price,Selling Price\n'
          'Widget,,"1,25,000.50"')!;
      final p = ProductCsv.parseRow(doc, doc.rows.first, resolver);
      expect(p.buyingPrice, Money.zero);
      expect(p.sellingPrice, Money.fromMajor(125000.50));
    });

    test('round-trip: row -> parse -> parseRow reconstructs core fields', () {
      final original =
          Product(id: 'PROD-9', businessId: 'BUS-1', name: 'Round Trip')
              .copyWith(
        sku: 'RT1',
        category: 'Gadgets',
        buyingPrice: Money.fromMajor(49.99),
        sellingPrice: Money.fromMajor(79.99),
        url: 'https://x.example/p',
        status: EntityStatus.active,
      );
      final csv = <List<Object?>>[
        ProductCsv.header,
        ProductCsv.row(original, businessName: 'Acme Store'),
      ];
      // Encode via the same encoder the app downloads with, then re-parse.
      final text = _encode(csv);
      final doc = CsvImport.parse(text)!;
      final parsed = ProductCsv.parseRow(doc, doc.rows.first, resolver);
      expect(parsed.id, isEmpty); // ids in the file are ignored
      expect(parsed.name, original.name);
      expect(parsed.sku, original.sku);
      expect(parsed.category, original.category);
      expect(parsed.buyingPrice, original.buyingPrice);
      expect(parsed.sellingPrice, original.sellingPrice); // precision survives
      expect(parsed.url, original.url);
      expect(parsed.businessId, original.businessId);
    });
  });

  // ---- CustomerCsv ----------------------------------------------------------

  group('CustomerCsv', () {
    final multi = BusinessResolver(
        [_biz('BUS-1', 'Acme Store'), _biz('BUS-2', 'Beta Traders')]);
    String nameOf(String id) =>
        {'BUS-1': 'Acme Store', 'BUS-2': 'Beta Traders'}[id] ?? id;

    test('row emits 14 columns; businesses as ; -joined ids and names', () {
      final c = Customer(id: 'CUST-1', businessIds: const [], name: 'Jane')
          .copyWith(businessIds: ['BUS-1', 'BUS-2']);
      final row = CustomerCsv.row(c, businessName: nameOf);
      expect(row.length, CustomerCsv.header.length);
      expect(row[12], 'BUS-1; BUS-2');
      expect(row[13], 'Acme Store; Beta Traders');
    });

    test('parseRow parses scalar fields; blank country defaults to India', () {
      final doc = CsvImport.parse(
          'Name,Deal Status,Email,City,Business IDs\n'
          'Jane,In Progress,j@x.com,Pune,BUS-1')!;
      final c = CustomerCsv.parseRow(doc, doc.rows.first, multi);
      expect(c.id, isEmpty);
      expect(c.name, 'Jane');
      expect(c.dealStatus, DealStatus.inProgress);
      expect(c.email, 'j@x.com');
      expect(c.country, 'India');
      expect(c.businessIds, ['BUS-1']);
    });

    test('missing name throws FormatException', () {
      final doc = CsvImport.parse('Name,Business IDs\n ,BUS-1')!;
      expect(() => CustomerCsv.parseRow(doc, doc.rows.first, multi),
          throwsFormatException);
    });

    test('any out-of-scope business token rejects the whole row', () {
      final doc =
          CsvImport.parse('Name,Business IDs\nJane,"BUS-1; BUS-9"')!;
      expect(() => CustomerCsv.parseRow(doc, doc.rows.first, multi),
          throwsFormatException);
    });

    test('multi-business resolves + de-duplicates across id and name', () {
      final doc = CsvImport.parse('Name,Business IDs\n'
          'Jane,"BUS-1; BUS-2"')!;
      final c = CustomerCsv.parseRow(doc, doc.rows.first, multi);
      expect(c.businessIds.toSet(), {'BUS-1', 'BUS-2'});
    });

    test('no business tokens + no fallback + multi scope throws', () {
      final doc = CsvImport.parse('Name\nJane')!;
      expect(() => CustomerCsv.parseRow(doc, doc.rows.first, multi),
          throwsFormatException);
    });

    test('REGRESSION: a business name with a comma is not fragmented', () {
      final commaName = BusinessResolver([_biz('BUS-1', 'Acme, Inc.')]);
      final doc = CsvImport.parse('Name,Business Names\n'
          'Jane,"Acme, Inc."')!;
      final c = CustomerCsv.parseRow(doc, doc.rows.first, commaName);
      expect(c.businessIds, ['BUS-1']);
    });

    test('REGRESSION: a business name with a pipe is not fragmented', () {
      final pipeName = BusinessResolver([_biz('BUS-1', 'A|B Co')]);
      final doc = CsvImport.parse('Name,Business Names\nJane,A|B Co')!;
      final c = CustomerCsv.parseRow(doc, doc.rows.first, pipeName);
      expect(c.businessIds, ['BUS-1']);
    });

    test('semicolon still splits a genuine multi-value cell', () {
      final doc =
          CsvImport.parse('Name,Business Names\nJane,"Acme Store; Beta Traders"')!;
      final c = CustomerCsv.parseRow(doc, doc.rows.first, multi);
      expect(c.businessIds.toSet(), {'BUS-1', 'BUS-2'});
    });

    test('CONFIRMED FINDING: unresolvable name is ignored when IDs resolve',
        () {
      // Business IDs are authoritative; a stale/renamed name column must not
      // reject a row whose ids are all in scope.
      final doc = CsvImport.parse('Name,Business IDs,Business Names\n'
          'Jane,BUS-1,"Old Renamed Co"')!;
      final c = CustomerCsv.parseRow(doc, doc.rows.first, multi);
      expect(c.businessIds, ['BUS-1']);
    });

    test('accepts alternate header names (Type, Company Size, Phone, Notes)',
        () {
      final doc = CsvImport.parse('Name,Type,Company Size,Phone,Notes,Business\n'
          'Jane,SaaS,Enterprise (1000+),12345,hello,BUS-1')!;
      final c = CustomerCsv.parseRow(doc, doc.rows.first, multi);
      expect(c.businessType, 'SaaS');
      expect(c.size, CompanySize.enterprise);
      expect(c.contactNo, '12345');
      expect(c.description, 'hello');
      expect(c.businessIds, ['BUS-1']);
    });

    test('round-trip reconstructs customer fields (id dropped)', () {
      final original =
          Customer(id: 'CUST-9', businessIds: const [], name: 'Round Trip')
              .copyWith(
        businessIds: ['BUS-1', 'BUS-2'],
        businessType: 'Retail',
        size: CompanySize.medium,
        dealStatus: DealStatus.successful,
        email: 'rt@x.com',
        city: 'Pune',
        country: 'India',
      );
      final text = _encode(<List<Object?>>[
        CustomerCsv.header,
        CustomerCsv.row(original, businessName: nameOf),
      ]);
      final doc = CsvImport.parse(text)!;
      final parsed = CustomerCsv.parseRow(doc, doc.rows.first, multi);
      expect(parsed.id, isEmpty);
      expect(parsed.name, original.name);
      expect(parsed.businessType, original.businessType);
      expect(parsed.size, original.size);
      expect(parsed.dealStatus, original.dealStatus);
      expect(parsed.email, original.email);
      expect(parsed.businessIds.toSet(), original.businessIds.toSet());
    });
  });

  // ---- enum resolvers (exercised through parseRow) -------------------------

  group('enum resolvers via parseRow', () {
    final sole = BusinessResolver([_biz('BUS-1', 'Acme Store')]);

    test('status resolves by label and wire; blank/unknown -> active', () {
      Product parse(String status) {
        final doc = CsvImport.parse('Name,Status\nWidget,$status')!;
        return ProductCsv.parseRow(doc, doc.rows.first, sole);
      }

      expect(parse('Inactive').status, EntityStatus.inactive);
      expect(parse('ARCHIVED').status, EntityStatus.archived);
      expect(parse('').status, EntityStatus.active);
      expect(parse('nonsense').status, EntityStatus.active);
    });

    test('size + deal status resolve by wire and parenthetical label', () {
      Customer parse(String size, String deal) {
        final doc = CsvImport.parse('Name,Size,Deal Status,Business\n'
            'Jane,$size,$deal,BUS-1')!;
        return CustomerCsv.parseRow(doc, doc.rows.first, sole);
      }

      expect(parse('MEDIUM', 'IN_PROGRESS').size, CompanySize.medium);
      expect(parse('Micro (1–10)', 'Successful').size, CompanySize.micro);
      expect(parse('', '').size, CompanySize.small); // fallback
      expect(parse('x', 'x').dealStatus, DealStatus.pending); // fallback
    });
  });
}

/// Encodes a CSV matrix exactly as `CsvExport.download` does (UTF-8 BOM +
/// comma delimiter) using the same `csv` package, so round-trip tests exercise
/// the real encode → parse path. `CsvExport` itself isn't imported because it
/// pulls in browser-only download code that can't load under the VM test.
final _exportCodec = Csv(addBom: true);
String _encode(List<List<Object?>> rows) => _exportCodec.encode(rows);
