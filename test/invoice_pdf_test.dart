import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/business.dart';
import 'package:salesforce_business_manager/models/customer.dart';
import 'package:salesforce_business_manager/models/invoice.dart';
import 'package:salesforce_business_manager/services/invoice_service.dart';

/// Renders the invoice to real PDF bytes to prove the layout builds and — the
/// path the pure-model tests can't reach — the bundled signature PNG actually
/// decodes and embeds via `pw.MemoryImage`.
void main() {
  const business = Business(
    id: 'BIZ-1',
    name: 'Acme Cloud Pvt Ltd',
    type: 'SaaS',
    website: 'acme.example',
    country: 'India',
  );

  final invoice = Invoice.forCustomer(
    customer: Customer(
      id: 'CUST-00042',
      businessIds: const ['BIZ-1'],
      name: 'Globex Retail',
      contactNo: '+91 90000 00000',
      email: 'ap@globex.example',
      city: 'Mumbai',
      serviceContract: ServiceContract(
        businessId: 'BIZ-1',
        price: const Money(500000),
        plan: SubscriptionPlan.pro,
        billingCycle: BillingCycle.monthly,
        purchaseDate: DateTime(2026, 4, 1),
        expiryDate: DateTime(2027, 3, 31),
      ),
    ),
    business: business,
    currency: CurrencyCode.inr,
    issuerName: 'Jane Owner',
    issuerTitle: 'Owner',
    now: DateTime(2026, 9, 21, 10, 30),
  );

  const service = InvoiceService();

  bool looksLikePdf(List<int> bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 && // %
      bytes[1] == 0x50 && // P
      bytes[2] == 0x44 && // D
      bytes[3] == 0x46; // F

  test('builds a valid PDF without a signature (flourish fallback)', () async {
    final bytes = await service.buildPdfBytes(invoice);
    expect(looksLikePdf(bytes), isTrue);
    expect(bytes.length, greaterThan(1000));
  });

  test('embeds the bundled signature PNG when supplied', () async {
    final sig = File('assets/images/signature.png').readAsBytesSync();
    final withSig =
        await service.buildPdfBytes(invoice, signatureBytes: sig);
    final withoutSig = await service.buildPdfBytes(invoice);

    expect(looksLikePdf(withSig), isTrue);
    // Embedding the raster signature makes the document meaningfully larger
    // than the vector-only fallback, confirming the image landed in the PDF.
    expect(withSig.length, greaterThan(withoutSig.length));
  });
}
