import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/customer.dart';

void main() {
  group('ServiceContract totals', () {
    test('total sums the base plan price and every add-on', () {
      const contract = ServiceContract(
        price: Money(500000), // ₹5,000
        addOns: [
          ServiceAddOn(name: 'Priority Support', price: Money(150000)),
          ServiceAddOn(name: 'Extra Seats', price: Money(75000)),
        ],
      );
      expect(contract.addOnsTotal, const Money(225000));
      expect(contract.total, const Money(725000)); // 5,000 + 1,500 + 750
    });

    test('total equals the base price when there are no add-ons', () {
      const contract = ServiceContract(price: Money(1200000));
      expect(contract.addOnsTotal, Money.zero);
      expect(contract.total, const Money(1200000));
    });

    test('a monthly contract annualises to 12× the cycle total', () {
      const contract = ServiceContract(
        price: Money(100000), // ₹1,000 / month
        billingCycle: BillingCycle.monthly,
        addOns: [ServiceAddOn(name: 'CRM', price: Money(50000))],
      );
      expect(contract.total, const Money(150000)); // ₹1,500 / month
      expect(contract.annualTotal, const Money(1800000)); // × 12 = ₹18,000
    });

    test('a yearly contract annualises to itself', () {
      const contract = ServiceContract(
        price: Money(1200000),
        billingCycle: BillingCycle.yearly,
      );
      expect(contract.annualTotal, const Money(1200000));
    });

    test('blank add-on prices contribute zero', () {
      const contract = ServiceContract(
        price: Money(500000),
        addOns: [ServiceAddOn(name: 'Freebie')],
      );
      expect(contract.total, const Money(500000));
    });
  });

  group('ServiceContract serialization', () {
    test('round-trips through toMap/fromMap', () {
      final contract = ServiceContract(
        businessId: 'BIZ-7',
        purchaseDate: DateTime(2026, 4, 1),
        expiryDate: DateTime(2027, 3, 31),
        price: Money.fromMajor(9999),
        plan: SubscriptionPlan.legend,
        billingCycle: BillingCycle.monthly,
        addOns: const [
          ServiceAddOn(name: 'Support', price: Money(120000)),
          ServiceAddOn(name: 'Onboarding', price: Money(300000)),
        ],
        comment: 'Signed by the CFO.',
      );
      final restored = ServiceContract.fromMap(contract.toMap());

      expect(restored.businessId, 'BIZ-7');
      expect(restored.purchaseDate, DateTime(2026, 4, 1));
      expect(restored.expiryDate, DateTime(2027, 3, 31));
      expect(restored.price, contract.price);
      expect(restored.plan, SubscriptionPlan.legend);
      expect(restored.billingCycle, BillingCycle.monthly);
      expect(restored.addOns.length, 2);
      expect(restored.addOns.first.name, 'Support');
      expect(restored.addOns.first.price, const Money(120000));
      expect(restored.comment, 'Signed by the CFO.');
      expect(restored.total, contract.total);
    });

    test('a blank businessId is omitted from the map and reads back empty', () {
      const contract = ServiceContract(price: Money(500000));
      expect(contract.toMap().containsKey('businessId'), isFalse);
      expect(ServiceContract.fromMap(contract.toMap()).businessId, '');
    });

    test('copyWith overrides the businessId', () {
      const contract = ServiceContract(businessId: 'BIZ-1', price: Money(500000));
      expect(contract.copyWith(businessId: 'BIZ-2').businessId, 'BIZ-2');
      expect(contract.copyWith().businessId, 'BIZ-1');
    });

    test('missing/unknown wire values degrade gracefully', () {
      final restored = ServiceContract.fromMap(const {});
      expect(restored.plan, SubscriptionPlan.basic);
      expect(restored.billingCycle, BillingCycle.yearly);
      expect(restored.price, Money.zero);
      expect(restored.addOns, isEmpty);
      expect(restored.purchaseDate, isNull);
    });

    test('BillingCycle.fromWire falls back to yearly for unknown values', () {
      expect(BillingCycle.fromWire('WEEKLY'), BillingCycle.yearly);
      expect(BillingCycle.fromWire('MONTHLY'), BillingCycle.monthly);
    });

    test('SubscriptionPlan.fromWire falls back to basic for unknown values', () {
      expect(SubscriptionPlan.fromWire('PLATINUM'), SubscriptionPlan.basic);
      expect(SubscriptionPlan.fromWire('PRO'), SubscriptionPlan.pro);
    });
  });

  group('Customer service-contract embedding', () {
    test('a customer with no contract omits it from the map and reads empty',
        () {
      const customer = Customer(
        id: 'CUST-00001',
        businessIds: ['BIZ-1'],
        name: 'Acme',
      );
      expect(customer.hasServiceContract, isFalse);
      expect(customer.toMap().containsKey('contractsByBusiness'), isFalse);
      final restored = Customer.fromMap(customer.toMap());
      expect(restored.hasServiceContract, isFalse);
      expect(restored.activeContractFor('BIZ-1'), isNull);
    });

    test('a customer round-trips its per-business contract', () {
      const customer = Customer(
        id: 'CUST-00001',
        businessIds: ['BIZ-1'],
        name: 'Acme',
        dealStatus: DealStatus.successful,
        contractsByBusiness: {
          'BIZ-1': BusinessContract(
            active: ServiceContract(
              businessId: 'BIZ-1',
              price: Money(500000),
              plan: SubscriptionPlan.pro,
              billingCycle: BillingCycle.monthly,
              addOns: [ServiceAddOn(name: 'SLA', price: Money(100000))],
            ),
          ),
        },
      );
      final restored = Customer.fromMap(customer.toMap());
      expect(restored.hasServiceContract, isTrue);
      expect(restored.hasContractFor('BIZ-1'), isTrue);
      expect(restored.activeContractFor('BIZ-1')!.plan, SubscriptionPlan.pro);
      expect(restored.activeContractFor('BIZ-1')!.total, const Money(600000));
      expect(restored.dealStatus, DealStatus.successful);
    });

    test('contracts are kept independent per business', () {
      const customer = Customer(
        id: 'CUST-00002',
        businessIds: ['BIZ-1', 'BIZ-2'],
        name: 'Globex',
        contractsByBusiness: {
          'BIZ-1': BusinessContract(
              active: ServiceContract(
                  businessId: 'BIZ-1', price: Money(500000))),
          'BIZ-2': BusinessContract(
              active: ServiceContract(
                  businessId: 'BIZ-2',
                  price: Money(900000),
                  plan: SubscriptionPlan.legend)),
        },
      );
      final restored = Customer.fromMap(customer.toMap());
      expect(restored.activeContractFor('BIZ-1')!.price, const Money(500000));
      expect(restored.activeContractFor('BIZ-2')!.price, const Money(900000));
      expect(restored.activeContractFor('BIZ-2')!.plan, SubscriptionPlan.legend);
      expect(restored.allActiveContracts.length, 2);
    });

    test('scoping an edit to one business leaves the other untouched', () {
      const customer = Customer(
        id: 'CUST-00003',
        businessIds: ['BIZ-1', 'BIZ-2'],
        name: 'Initech',
        contractsByBusiness: {
          'BIZ-1': BusinessContract(
              active: ServiceContract(
                  businessId: 'BIZ-1', price: Money(500000))),
          'BIZ-2': BusinessContract(
              active: ServiceContract(
                  businessId: 'BIZ-2', price: Money(900000))),
        },
      );
      final edited = customer.withContract(const ServiceContract(
          businessId: 'BIZ-1',
          price: Money(600000),
          plan: SubscriptionPlan.pro));
      expect(edited.activeContractFor('BIZ-1')!.price, const Money(600000));
      expect(edited.activeContractFor('BIZ-1')!.plan, SubscriptionPlan.pro);
      // BIZ-2 is left exactly as it was.
      expect(edited.activeContractFor('BIZ-2')!.price, const Money(900000));
    });

    group('legacy single-contract migration', () {
      test('migrates a legacy serviceContract under its own businessId', () {
        const legacyContract = ServiceContract(
          businessId: 'BIZ-2',
          price: Money(500000),
          plan: SubscriptionPlan.pro,
        );
        final legacyMap = <String, dynamic>{
          'id': 'CUST-1',
          'businessIds': ['BIZ-1', 'BIZ-2'],
          'name': 'Acme',
          'serviceContract': legacyContract.toMap(),
        };
        final restored = Customer.fromMap(legacyMap);
        expect(restored.hasContractFor('BIZ-2'), isTrue);
        expect(restored.hasContractFor('BIZ-1'), isFalse);
        expect(restored.activeContractFor('BIZ-2')!.plan, SubscriptionPlan.pro);
      });

      test('falls back to the first tagged business for a blank businessId', () {
        const legacyContract = ServiceContract(price: Money(500000));
        final legacyMap = <String, dynamic>{
          'id': 'CUST-1',
          'businessIds': ['BIZ-9', 'BIZ-2'],
          'name': 'Acme',
          'serviceContract': legacyContract.toMap(),
        };
        final restored = Customer.fromMap(legacyMap);
        expect(restored.hasContractFor('BIZ-9'), isTrue);
        expect(restored.activeContractFor('BIZ-9')!.price, const Money(500000));
      });

      test('carries the legacy contractHistory into the migrated entry', () {
        const active = ServiceContract(businessId: 'BIZ-1', price: Money(700000));
        const prior = ServiceContract(businessId: 'BIZ-1', price: Money(500000));
        final legacyMap = <String, dynamic>{
          'id': 'CUST-1',
          'businessIds': ['BIZ-1'],
          'name': 'Acme',
          'serviceContract': active.toMap(),
          'contractHistory': [prior.toMap()],
        };
        final restored = Customer.fromMap(legacyMap);
        expect(restored.activeContractFor('BIZ-1')!.price, const Money(700000));
        expect(restored.historyFor('BIZ-1').length, 1);
        expect(restored.historyFor('BIZ-1').first.price, const Money(500000));
        expect(restored.contractTermCount, 2);
      });

      test('drops a legacy contract that can be tied to no business', () {
        const legacyContract = ServiceContract(price: Money(500000));
        final legacyMap = <String, dynamic>{
          'id': 'CUST-1',
          'businessIds': <String>[],
          'name': 'Orphan',
          'serviceContract': legacyContract.toMap(),
        };
        final restored = Customer.fromMap(legacyMap);
        expect(restored.hasServiceContract, isFalse);
      });
    });
  });

  group('ServiceContract one-time plan price', () {
    test('a one-time plan price is excluded from the recurring total', () {
      const contract = ServiceContract(
        price: Money(1200000), // ₹12,000 one-time setup
        priceOneTime: true,
        addOns: [ServiceAddOn(name: 'Support', price: Money(200000))],
      );
      // Recurring total is add-ons only; the plan price is surfaced separately.
      expect(contract.recurringPrice, Money.zero);
      expect(contract.total, const Money(200000));
      expect(contract.oneTimeTotal, const Money(1200000));
      expect(contract.hasOneTimeCharge, isTrue);
    });

    test('a recurring plan price is included in the total (default)', () {
      const contract = ServiceContract(
        price: Money(500000),
        addOns: [ServiceAddOn(name: 'Support', price: Money(100000))],
      );
      expect(contract.priceOneTime, isFalse);
      expect(contract.total, const Money(600000));
      expect(contract.oneTimeTotal, Money.zero);
      expect(contract.hasOneTimeCharge, isFalse);
    });

    test('a one-time-only contract with no add-ons has a zero recurring total',
        () {
      const contract = ServiceContract(price: Money(900000), priceOneTime: true);
      expect(contract.total, Money.zero);
      expect(contract.annualTotal, Money.zero);
      expect(contract.oneTimeTotal, const Money(900000));
    });

    test('hasOneTimeCharge is false when the one-time price is zero', () {
      const contract = ServiceContract(price: Money.zero, priceOneTime: true);
      expect(contract.hasOneTimeCharge, isFalse);
    });

    test('the one-time flag survives a serialization round-trip', () {
      const contract = ServiceContract(price: Money(750000), priceOneTime: true);
      final restored = ServiceContract.fromMap(contract.toMap());
      expect(restored.priceOneTime, isTrue);
      expect(restored.total, Money.zero);
      expect(restored.oneTimeTotal, const Money(750000));
    });

    test('priceOneTime defaults to false for legacy contracts', () {
      final restored = ServiceContract.fromMap(const {'priceMinor': 500000});
      expect(restored.priceOneTime, isFalse);
      expect(restored.total, const Money(500000));
    });
  });

  group('ServiceContract time remaining', () {
    test('returns null when the contract has no expiry date', () {
      const contract = ServiceContract(price: Money(500000));
      expect(contract.timeRemainingAsOf(DateTime(2026, 9, 21)), isNull);
    });

    test('reports future time as remaining, not past', () {
      final contract = ServiceContract(
        purchaseDate: DateTime(2026, 9, 21),
        expiryDate: DateTime(2027, 11, 24),
      );
      final r = contract.timeRemainingAsOf(DateTime(2026, 9, 21))!;
      expect(r.isPast, isFalse);
      expect(r.years, 1);
      expect(r.months, 2);
      expect(r.days, 3);
    });

    test('reports a lapsed contract as past', () {
      final contract = ServiceContract(expiryDate: DateTime(2026, 9, 1));
      final r = contract.timeRemainingAsOf(DateTime(2026, 9, 21))!;
      expect(r.isPast, isTrue);
      expect(r.totalDays, 20);
    });

    test('isExpiredAsOf reflects the expiry boundary', () {
      final contract = ServiceContract(expiryDate: DateTime(2026, 9, 20));
      expect(contract.isExpiredAsOf(DateTime(2026, 9, 21)), isTrue);
      expect(contract.isExpiredAsOf(DateTime(2026, 9, 19)), isFalse);
    });
  });

  group('TimeRemaining', () {
    test('borrows days across month boundaries correctly', () {
      // 15 Jan -> 10 Mar: 1 month + (days from 15 Feb to 10 Mar). Feb 2026 has
      // 28 days, so borrowing gives 28 - 15 + 10 = 23 days.
      final r = TimeRemaining.between(DateTime(2026, 1, 15), DateTime(2026, 3, 10));
      expect(r.isPast, isFalse);
      expect(r.years, 0);
      expect(r.months, 1);
      expect(r.days, 23);
    });

    test('same day is "today" with zero total days', () {
      final r = TimeRemaining.between(DateTime(2026, 9, 21), DateTime(2026, 9, 21));
      expect(r.isToday, isTrue);
      expect(r.totalDays, 0);
    });

    test('shortLabel prefers the two largest units', () {
      final r = TimeRemaining.between(DateTime(2026, 1, 1), DateTime(2027, 3, 1));
      expect(r.shortLabel, '1 yr 2 mo');
    });

    test('shortLabel falls back to days for sub-month spans', () {
      final r = TimeRemaining.between(DateTime(2026, 9, 1), DateTime(2026, 9, 24));
      expect(r.shortLabel, '23 days');
    });

    test('label phrases past vs future differently', () {
      final future =
          TimeRemaining.between(DateTime(2026, 9, 1), DateTime(2026, 9, 24));
      final past =
          TimeRemaining.between(DateTime(2026, 9, 24), DateTime(2026, 9, 1));
      expect(future.label, '23 days remaining');
      expect(past.label, 'Expired 23 days ago');
    });
  });

  group('Customer contract renewal', () {
    const original = ServiceContract(
      businessId: 'BIZ-1',
      price: Money(500000),
      plan: SubscriptionPlan.basic,
      billingCycle: BillingCycle.yearly,
    );
    const renewal = ServiceContract(
      businessId: 'BIZ-1',
      price: Money(700000),
      plan: SubscriptionPlan.pro,
      billingCycle: BillingCycle.yearly,
    );

    test('withRenewedContract archives the active term and activates the new one',
        () {
      const customer = Customer(
        id: 'CUST-1',
        businessIds: ['BIZ-1'],
        name: 'Acme',
        dealStatus: DealStatus.successful,
        contractsByBusiness: {'BIZ-1': BusinessContract(active: original)},
      );
      final renewed = customer.withRenewedContract(renewal);

      expect(renewed.activeContractFor('BIZ-1')!.plan, SubscriptionPlan.pro);
      expect(renewed.historyFor('BIZ-1').length, 1);
      expect(renewed.historyFor('BIZ-1').first.plan, SubscriptionPlan.basic);
      expect(renewed.contractTermCount, 2);
      expect(renewed.dealStatus, DealStatus.successful);
    });

    test('renewing again pushes the previous active term to the front', () {
      const secondRenewal = ServiceContract(
        businessId: 'BIZ-1',
        price: Money(900000),
        plan: SubscriptionPlan.legend,
      );
      const customer = Customer(
        id: 'CUST-1',
        businessIds: ['BIZ-1'],
        name: 'Acme',
        contractsByBusiness: {'BIZ-1': BusinessContract(active: original)},
      );
      final renewed = customer
          .withRenewedContract(renewal)
          .withRenewedContract(secondRenewal);

      expect(renewed.activeContractFor('BIZ-1')!.plan, SubscriptionPlan.legend);
      expect(renewed.historyFor('BIZ-1').map((c) => c.plan).toList(),
          [SubscriptionPlan.pro, SubscriptionPlan.basic]);
      expect(renewed.contractTermCount, 3);
    });

    test('renewing with no active contract simply sets it (no history)', () {
      const customer =
          Customer(id: 'CUST-1', businessIds: ['BIZ-1'], name: 'Acme');
      final renewed = customer.withRenewedContract(renewal);
      expect(renewed.activeContractFor('BIZ-1')!.plan, SubscriptionPlan.pro);
      expect(renewed.hasContractHistory, isFalse);
      expect(renewed.contractTermCount, 1);
    });

    test('renewing one business does not disturb another business term', () {
      const customer = Customer(
        id: 'CUST-1',
        businessIds: ['BIZ-1', 'BIZ-2'],
        name: 'Acme',
        contractsByBusiness: {
          'BIZ-1': BusinessContract(active: original),
          'BIZ-2': BusinessContract(
              active: ServiceContract(
                  businessId: 'BIZ-2', price: Money(300000))),
        },
      );
      final renewed = customer.withRenewedContract(renewal);
      // BIZ-1 renewed with history; BIZ-2 unchanged and history-free.
      expect(renewed.activeContractFor('BIZ-1')!.plan, SubscriptionPlan.pro);
      expect(renewed.historyFor('BIZ-1').length, 1);
      expect(renewed.activeContractFor('BIZ-2')!.price, const Money(300000));
      expect(renewed.historyFor('BIZ-2'), isEmpty);
    });

    test('contract history round-trips through the customer map', () {
      const customer = Customer(
        id: 'CUST-1',
        businessIds: ['BIZ-1'],
        name: 'Acme',
        contractsByBusiness: {
          'BIZ-1': BusinessContract(active: renewal, history: [original]),
        },
      );
      final restored = Customer.fromMap(customer.toMap());
      expect(restored.hasContractHistory, isTrue);
      expect(restored.historyFor('BIZ-1').length, 1);
      expect(restored.historyFor('BIZ-1').first.plan, SubscriptionPlan.basic);
      expect(restored.activeContractFor('BIZ-1')!.plan, SubscriptionPlan.pro);
      expect(restored.contractTermCount, 2);
    });

    test('an empty history is omitted from the serialized map', () {
      const customer = Customer(
        id: 'CUST-1',
        businessIds: ['BIZ-1'],
        name: 'Acme',
        contractsByBusiness: {'BIZ-1': BusinessContract(active: original)},
      );
      final map = customer.toMap();
      final byBiz = map['contractsByBusiness'] as Map<String, dynamic>;
      final biz1 = byBiz['BIZ-1'] as Map<String, dynamic>;
      expect(biz1.containsKey('history'), isFalse);
    });
  });
}
