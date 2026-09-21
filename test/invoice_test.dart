import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/business.dart';
import 'package:salesforce_business_manager/models/customer.dart';
import 'package:salesforce_business_manager/models/invoice.dart';
import 'package:salesforce_business_manager/screens/customers/invoice_action.dart';

/// A minimal seller business used across the invoicing tests.
Business _business({CurrencyCode currency = CurrencyCode.inr}) => Business(
      id: 'BIZ-1',
      name: 'Acme Cloud Pvt Ltd',
      type: 'SaaS',
      website: 'acme.example',
      country: 'India',
      currency: currency,
    );

/// A customer carrying [contract] as its active service contract for BIZ-1.
Customer _customerWith(ServiceContract? contract) => Customer(
      id: 'CUST-00042',
      businessIds: const ['BIZ-1'],
      name: 'Globex Retail',
      businessType: 'Retail',
      contactNo: '+91 90000 00000',
      email: 'ap@globex.example',
      city: 'Mumbai',
      contractsByBusiness: contract == null
          ? const {}
          : {'BIZ-1': BusinessContract(active: contract)},
    );

final _now = DateTime(2026, 9, 21, 10, 30);

Invoice _invoiceFor(ServiceContract? contract, {Business? business}) =>
    Invoice.forCustomer(
      customer: _customerWith(contract),
      contract: contract,
      business: business ?? _business(),
      currency: business?.currency ?? CurrencyCode.inr,
      issuerName: 'Jane Owner',
      issuerTitle: 'Owner',
      now: _now,
    );

void main() {
  group('Invoice.forCustomer line derivation', () {
    test('a recurring plan becomes a single recurring subscription line', () {
      const contract = ServiceContract(
        price: Money(500000), // ₹5,000 / cycle
        plan: SubscriptionPlan.pro,
        billingCycle: BillingCycle.monthly,
      );
      final invoice = _invoiceFor(contract);

      expect(invoice.lines.length, 1);
      final line = invoice.lines.single;
      expect(line.description, 'Pro Plan Subscription');
      expect(line.oneTime, isFalse);
      expect(line.unitPrice, const Money(500000));
      expect(line.amount, const Money(500000));
      expect(invoice.billingCycle, BillingCycle.monthly);
    });

    test('a one-time plan price becomes a one-time flagged line', () {
      const contract = ServiceContract(
        price: Money(1200000),
        priceOneTime: true,
        plan: SubscriptionPlan.legend,
      );
      final invoice = _invoiceFor(contract);

      expect(invoice.lines.length, 1);
      final line = invoice.lines.single;
      expect(line.description, 'Legend Plan');
      expect(line.oneTime, isTrue);
      expect(line.unitPrice, const Money(1200000));
    });

    test('add-ons are appended as their own recurring lines', () {
      const contract = ServiceContract(
        price: Money(500000),
        plan: SubscriptionPlan.basic,
        billingCycle: BillingCycle.yearly,
        addOns: [
          ServiceAddOn(name: 'Priority Support', price: Money(150000)),
          ServiceAddOn(name: 'Extra Seats', price: Money(75000)),
        ],
      );
      final invoice = _invoiceFor(contract);

      expect(invoice.lines.length, 3);
      expect(invoice.lines[0].description, 'Basic Plan Subscription');
      expect(invoice.lines[1].description, 'Priority Support');
      expect(invoice.lines[1].unitPrice, const Money(150000));
      expect(invoice.lines[2].description, 'Extra Seats');
      expect(invoice.lines.every((l) => !l.oneTime), isTrue);
    });

    test('a blank, zero-priced add-on is skipped', () {
      const contract = ServiceContract(
        price: Money(500000),
        addOns: [ServiceAddOn(name: '  ', price: Money.zero)],
      );
      final invoice = _invoiceFor(contract);

      expect(invoice.lines.length, 1);
      expect(invoice.lines.single.description, contains('Plan'));
    });

    test('a named add-on with a zero price is kept', () {
      const contract = ServiceContract(
        price: Money(500000),
        addOns: [ServiceAddOn(name: 'Bundled Onboarding', price: Money.zero)],
      );
      final invoice = _invoiceFor(contract);

      expect(invoice.lines.length, 2);
      expect(invoice.lines[1].description, 'Bundled Onboarding');
      expect(invoice.lines[1].amount, Money.zero);
    });

    test('a zero-priced recurring plan contributes no plan line', () {
      const contract = ServiceContract(
        price: Money.zero,
        addOns: [ServiceAddOn(name: 'Support', price: Money(100000))],
      );
      final invoice = _invoiceFor(contract);

      // Only the add-on line — the free plan itself is not billed.
      expect(invoice.lines.length, 1);
      expect(invoice.lines.single.description, 'Support');
    });
  });

  group('Invoice totals', () {
    test('total sums every line; recurring and one-time split correctly', () {
      const contract = ServiceContract(
        price: Money(500000), // recurring plan
        plan: SubscriptionPlan.pro,
        billingCycle: BillingCycle.monthly,
        addOns: [ServiceAddOn(name: 'SLA', price: Money(100000))],
      );
      final invoice = _invoiceFor(contract);

      expect(invoice.total, const Money(600000));
      expect(invoice.recurringTotal, const Money(600000));
      expect(invoice.oneTimeTotal, Money.zero);
      expect(invoice.hasMixedCharges, isFalse);
    });

    test('hasMixedCharges is true when both charge types are present', () {
      // A one-time plan price plus a recurring add-on.
      const contract = ServiceContract(
        price: Money(1200000),
        priceOneTime: true,
        addOns: [ServiceAddOn(name: 'Support', price: Money(200000))],
      );
      final invoice = _invoiceFor(contract);

      expect(invoice.oneTimeTotal, const Money(1200000));
      expect(invoice.recurringTotal, const Money(200000));
      expect(invoice.total, const Money(1400000));
      expect(invoice.hasMixedCharges, isTrue);
    });

    test('an invoice for a customer with no contract is empty', () {
      final invoice = _invoiceFor(null);
      expect(invoice.isEmpty, isTrue);
      expect(invoice.lines, isEmpty);
      expect(invoice.total, Money.zero);
    });

    test('a one-time-only contract with no add-ons still yields a line', () {
      const contract = ServiceContract(price: Money(900000), priceOneTime: true);
      final invoice = _invoiceFor(contract);
      expect(invoice.isEmpty, isFalse);
      expect(invoice.total, const Money(900000));
      expect(invoice.oneTimeTotal, const Money(900000));
    });
  });

  group('Invoice metadata', () {
    const contract = ServiceContract(price: Money(500000));

    test('the number encodes the customer digits and the issue date', () {
      final invoice = _invoiceFor(contract);
      expect(invoice.number, 'INV-00042-20260921');
    });

    test('the issue date is normalised to midnight and due date is +7 days', () {
      final invoice = _invoiceFor(contract);
      expect(invoice.issueDate, DateTime(2026, 9, 21));
      expect(invoice.dueDate, DateTime(2026, 9, 28));
    });

    test('the seller comes from the business; the buyer from the customer', () {
      final invoice = _invoiceFor(contract);
      expect(invoice.seller.name, 'Acme Cloud Pvt Ltd');
      expect(invoice.seller.lines, contains('acme.example'));
      expect(invoice.buyer.name, 'Globex Retail');
      expect(invoice.buyer.lines, contains('ap@globex.example'));
    });

    test('service start and end dates come from the contract term', () {
      final invoice = _invoiceFor(const ServiceContract(
        price: Money(500000),
        purchaseDate: null,
        expiryDate: null,
      ).copyWith(
        purchaseDate: DateTime(2026, 4, 1),
        expiryDate: DateTime(2027, 3, 31),
      ));
      expect(invoice.serviceStart, DateTime(2026, 4, 1));
      expect(invoice.serviceEnd, DateTime(2027, 3, 31));
    });

    test('service dates are null when the contract leaves them unset', () {
      final invoice = _invoiceFor(contract);
      expect(invoice.serviceStart, isNull);
      expect(invoice.serviceEnd, isNull);
    });

    test('the signatory is taken from the issuer and signing time', () {
      final invoice = _invoiceFor(contract);
      expect(invoice.signatoryName, 'Jane Owner');
      expect(invoice.signatoryTitle, 'Owner');
      expect(invoice.signedAt, _now);
    });

    test('with no resolvable business the seller falls back to the app name', () {
      final invoice = Invoice.forCustomer(
        customer: _customerWith(contract),
        contract: contract,
        business: null,
        currency: CurrencyCode.inr,
        issuerName: 'Jane Owner',
        issuerTitle: 'Owner',
        now: _now,
      );
      expect(invoice.seller.name, 'Salesforce Business Manager');
    });

    test('currency flows through from the caller', () {
      final invoice =
          _invoiceFor(contract, business: _business(currency: CurrencyCode.usd));
      expect(invoice.currency, CurrencyCode.usd);
    });
  });

  group('Invoice fingerprint', () {
    const contract = ServiceContract(price: Money(500000));

    test('is a stable 16-char hex string', () {
      final invoice = _invoiceFor(contract);
      expect(invoice.fingerprint, matches(RegExp(r'^[0-9A-F]{16}$')));
    });

    test('is deterministic for the same invoice', () {
      final a = _invoiceFor(contract).fingerprint;
      final b = _invoiceFor(contract).fingerprint;
      expect(a, b);
    });

    test('changes when the billed amount changes', () {
      final cheap = _invoiceFor(const ServiceContract(price: Money(500000)));
      final dear = _invoiceFor(const ServiceContract(price: Money(900000)));
      expect(cheap.fingerprint, isNot(dear.fingerprint));
    });
  });

  group('resolveContractSeller (multi-business selection)', () {
    // A customer tagged to two businesses; the contract picks the second one.
    const bizA = Business(id: 'BIZ-A', name: 'Alpha Traders');
    const bizB = Business(id: 'BIZ-B', name: 'Beta Exports');
    Business? lookup(String id) => {'BIZ-A': bizA, 'BIZ-B': bizB}[id];

    // A customer tagged to both businesses; the contract (passed explicitly to
    // resolveContractSeller) decides the seller.
    Customer multiBiz(ServiceContract? contract) => Customer(
          id: 'CUST-1',
          businessIds: const ['BIZ-A', 'BIZ-B'],
          name: 'Globex',
          contractsByBusiness: contract == null || contract.businessId.isEmpty
              ? const {}
              : {contract.businessId: BusinessContract(active: contract)},
        );

    test("uses the contract's chosen business, not the first tagged one", () {
      const contract = ServiceContract(businessId: 'BIZ-B', price: Money(500000));
      final customer = multiBiz(contract);
      expect(resolveContractSeller(customer, lookup, contract: contract)?.id,
          'BIZ-B');
    });

    test('falls back to the first tagged business when the contract has none',
        () {
      const contract = ServiceContract(price: Money(500000));
      final customer = multiBiz(contract);
      expect(resolveContractSeller(customer, lookup, contract: contract)?.id,
          'BIZ-A');
    });

    test('an explicit fallback is used before the first tagged business', () {
      const contract = ServiceContract(price: Money(500000));
      final customer = multiBiz(contract);
      expect(
        resolveContractSeller(customer, lookup, contract: contract, fallback: bizB)
            ?.id,
        'BIZ-B',
      );
    });

    test("the contract's business wins over an explicit fallback", () {
      const contract = ServiceContract(businessId: 'BIZ-A', price: Money(500000));
      final customer = multiBiz(contract);
      expect(
        resolveContractSeller(customer, lookup, contract: contract, fallback: bizB)
            ?.id,
        'BIZ-A',
      );
    });

    test('an unresolvable contract business falls through to the fallback', () {
      const contract =
          ServiceContract(businessId: 'BIZ-GONE', price: Money(500000));
      final customer = multiBiz(contract);
      expect(
        resolveContractSeller(customer, lookup, contract: contract, fallback: bizB)
            ?.id,
        'BIZ-B',
      );
    });

    test('returns null when nothing resolves', () {
      const customer = Customer(
        id: 'CUST-2',
        businessIds: ['BIZ-X'],
        name: 'Orphan',
      );
      expect(resolveContractSeller(customer, lookup), isNull);
    });
  });
}
