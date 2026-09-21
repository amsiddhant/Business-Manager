import '../enums.dart';
import '../../models/business.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import 'csv_import.dart';
import 'money.dart';

/// Splits a multi-value CSV cell (e.g. a customer's businesses) into trimmed,
/// non-empty tokens. We split only on `;` and newline — the separators
/// [CustomerCsv.row] emits — and deliberately NOT on comma or pipe, either of
/// which can occur inside a legitimate business name ("Acme, Inc.", "A|B Co").
List<String> _splitMulti(String cell) => cell
    .split(RegExp(r'[;\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Resolves an [EntityStatus] from a free-form CSV token by matching against
/// each value's label and wire form (case/punctuation-insensitively), falling
/// back to [EntityStatus.active] when blank or unrecognised.
EntityStatus _resolveStatus(String token) {
  final n = csvNormalize(token);
  if (n.isEmpty) return EntityStatus.active;
  for (final v in EntityStatus.values) {
    if (csvNormalize(v.label) == n || csvNormalize(v.wire) == n) return v;
  }
  return EntityStatus.active;
}

/// Resolves a [CompanySize] from a free-form CSV token (label or wire form),
/// falling back to [CompanySize.small].
CompanySize _resolveSize(String token) {
  final n = csvNormalize(token);
  if (n.isEmpty) return CompanySize.small;
  for (final v in CompanySize.values) {
    if (csvNormalize(v.label) == n || csvNormalize(v.wire) == n) return v;
  }
  return CompanySize.small;
}

/// Resolves a [DealStatus] from a free-form CSV token (label or wire form),
/// falling back to [DealStatus.pending].
DealStatus _resolveDealStatus(String token) {
  final n = csvNormalize(token);
  if (n.isEmpty) return DealStatus.pending;
  for (final v in DealStatus.values) {
    if (csvNormalize(v.label) == n || csvNormalize(v.wire) == n) return v;
  }
  return DealStatus.pending;
}

/// Looks up an accessible [Business] by its id or name, tolerating differences
/// in case, spacing and punctuation. Built from the caller's access-scoped set,
/// so a token that resolves to null is treated as unknown / out-of-scope and
/// the row is rejected — a CSV can never import into a business the user cannot
/// reach (the repository re-checks this on save regardless).
class BusinessResolver {
  BusinessResolver(List<Business> businesses)
      : _byId = {for (final b in businesses) csvNormalize(b.id): b},
        _byName = {for (final b in businesses) csvNormalize(b.name): b},
        isEmpty = businesses.isEmpty;

  final Map<String, Business> _byId;
  final Map<String, Business> _byName;
  final bool isEmpty;

  /// The single accessible business, when there is exactly one — used as the
  /// implicit target for rows that name no business.
  Business? get sole => _byId.length == 1 ? _byId.values.first : null;

  Business? resolve(String token) {
    final n = csvNormalize(token);
    if (n.isEmpty) return null;
    return _byId[n] ?? _byName[n];
  }

  /// Whether [businessId] is one of the accessible businesses (exact id match).
  /// Used to validate a caller-supplied fallback id before trusting it.
  bool contains(String businessId) => _byId.containsKey(csvNormalize(businessId));
}

/// CSV column mapping for [Product] export/import. Export emits human-readable
/// values (prices as major units, status as a label); import parses forgivingly
/// and always mints a fresh record (ids in the file are ignored) so re-importing
/// an export never silently overwrites an existing product.
class ProductCsv {
  ProductCsv._();

  static const List<String> header = [
    'Product ID',
    'Name',
    'SKU',
    'Category',
    'Description',
    'Buying Price',
    'Selling Price',
    'Product URL',
    'Status',
    'Business ID',
    'Business Name',
  ];

  static List<Object?> row(Product p, {required String businessName}) => [
        p.id,
        p.name,
        p.sku,
        p.category,
        p.description,
        p.buyingPrice.major,
        p.sellingPrice.major,
        p.url,
        p.status.label,
        p.businessId,
        businessName,
      ];

  /// Parses one data [row] into a new [Product] (blank id, to be assigned on
  /// save). Throws [FormatException] with a user-facing message when the row is
  /// invalid (missing name, or an unknown / out-of-scope business).
  ///
  /// [fallbackBusinessId] targets rows that name no business, used only when a
  /// single business is in scope.
  static Product parseRow(
    CsvDocument doc,
    List<String> row,
    BusinessResolver businesses, {
    String? fallbackBusinessId,
  }) {
    final name = doc.value(row, const ['Name', 'Product Name', 'Product']).trim();
    if (name.isEmpty) throw const FormatException('Product name is required.');

    final bizToken =
        doc.value(row, const ['Business ID', 'Business', 'Business Name']);
    String businessId;
    if (bizToken.trim().isNotEmpty) {
      final biz = businesses.resolve(bizToken);
      if (biz == null) {
        throw FormatException(
            'Business "$bizToken" is not one you can access.');
      }
      businessId = biz.id;
    } else if (fallbackBusinessId != null) {
      businessId = fallbackBusinessId;
    } else if (businesses.sole != null) {
      businessId = businesses.sole!.id;
    } else {
      throw const FormatException(
          'No business specified. Add a "Business" column or select a single '
          'business first.');
    }

    return Product(id: '', businessId: businessId, name: name).copyWith(
      sku: doc.value(row, const ['SKU']).trim(),
      category: doc.value(row, const ['Category']).trim(),
      description: doc.value(row, const ['Description']).trim(),
      buyingPrice: Money.parse(
          doc.value(row, const ['Buying Price', 'Buying', 'Cost Price'])),
      sellingPrice: Money.parse(
          doc.value(row, const ['Selling Price', 'Selling', 'Price'])),
      url: doc.value(row, const ['Product URL', 'URL']).trim(),
      status: _resolveStatus(doc.value(row, const ['Status'])),
    );
  }
}

/// CSV column mapping for [Customer] export/import. A customer's businesses are
/// emitted as a `;`-separated list (ids and names in parallel columns) and
/// parsed back tolerantly; every referenced business must be accessible. Import
/// always mints a fresh record. Embedded contracts and comments are not part of
/// the CSV shape — imported customers start with none.
class CustomerCsv {
  CustomerCsv._();

  static const List<String> header = [
    'Customer ID',
    'Name',
    'Business Type',
    'Size',
    'Deal Status',
    'Contact No',
    'Email',
    'City',
    'State',
    'Country',
    'Social Media',
    'Description',
    'Business IDs',
    'Business Names',
  ];

  static List<Object?> row(
    Customer c, {
    required String Function(String businessId) businessName,
  }) =>
      [
        c.id,
        c.name,
        c.businessType,
        c.size.label,
        c.dealStatus.label,
        c.contactNo,
        c.email,
        c.city,
        c.state,
        c.country,
        c.socialMedia,
        c.description,
        c.businessIds.join('; '),
        c.businessIds.map(businessName).join('; '),
      ];

  /// Parses one data [row] into a new [Customer] (blank id). Throws
  /// [FormatException] with a user-facing message when the row is invalid
  /// (missing name, no resolvable business, or a business outside the caller's
  /// access). [fallbackBusinessId] targets rows that name no business, used
  /// only when a single business is in scope.
  static Customer parseRow(
    CsvDocument doc,
    List<String> row,
    BusinessResolver businesses, {
    String? fallbackBusinessId,
  }) {
    final name = doc.value(row, const ['Name', 'Customer Name']).trim();
    if (name.isEmpty) throw const FormatException('Customer name is required.');

    // Businesses may be listed by id and/or by name across two columns. The
    // id column is authoritative (stable, always exact); the name column is a
    // fallback for rows that carry no ids — a self-export always emits ids, so
    // a mangled/renamed name never rejects a row whose ids resolve cleanly.
    final idTokens = _splitMulti(doc.value(
        row, const ['Business IDs', 'Business ID', 'Businesses', 'Business']));
    final nameTokens = idTokens.isNotEmpty
        ? const <String>[]
        : _splitMulti(doc.value(row, const ['Business Names', 'Business Name']));

    final businessIds = <String>{};
    for (final t in [...idTokens, ...nameTokens]) {
      final biz = businesses.resolve(t);
      if (biz == null) {
        throw FormatException('Business "$t" is not one you can access.');
      }
      businessIds.add(biz.id);
    }
    if (businessIds.isEmpty) {
      if (fallbackBusinessId != null) {
        businessIds.add(fallbackBusinessId);
      } else if (businesses.sole != null) {
        businessIds.add(businesses.sole!.id);
      } else {
        throw const FormatException(
            'No business specified. Add a "Business IDs" column or select a '
            'single business first.');
      }
    }

    final email = doc.value(row, const ['Email']).trim();

    return Customer(id: '', businessIds: const [], name: name).copyWith(
      businessIds: businessIds.toList(),
      businessType: doc.value(row, const ['Business Type', 'Type']).trim(),
      size: _resolveSize(doc.value(row, const ['Size', 'Company Size'])),
      dealStatus:
          _resolveDealStatus(doc.value(row, const ['Deal Status', 'Status'])),
      contactNo: doc.value(row, const ['Contact No', 'Contact', 'Phone']).trim(),
      email: email,
      city: doc.value(row, const ['City']).trim(),
      state: doc.value(row, const ['State']).trim(),
      country: () {
        final v = doc.value(row, const ['Country']).trim();
        return v.isEmpty ? 'India' : v;
      }(),
      socialMedia: doc.value(row, const ['Social Media', 'Social']).trim(),
      description: doc.value(row, const ['Description', 'Notes']).trim(),
    );
  }
}
