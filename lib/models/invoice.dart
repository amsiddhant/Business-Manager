import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import 'business.dart';
import 'customer.dart';

/// One named party on an invoice (the seller or the buyer): a headline name, an
/// optional subtitle and any number of free-form address / contact lines.
class InvoiceParty {
  const InvoiceParty({
    required this.name,
    this.subtitle = '',
    this.lines = const [],
  });

  final String name;
  final String subtitle;

  /// Address / contact detail lines, already trimmed and non-empty.
  final List<String> lines;
}

/// A single billable row on the invoice. [amount] is [unitPrice] × [quantity].
/// [oneTime] flags a non-recurring charge (e.g. a one-off setup / licence fee)
/// so the totals block can present it apart from the recurring subscription.
class InvoiceLine {
  const InvoiceLine({
    required this.description,
    this.detail = '',
    this.quantity = 1,
    required this.unitPrice,
    this.oneTime = false,
  });

  final String description;
  final String detail;
  final int quantity;
  final Money unitPrice;
  final bool oneTime;

  Money get amount => unitPrice * quantity;
}

/// A fully-computed invoice: parties, billable lines, totals and the signatory
/// details for the digital-signature block. This is a pure value object — it
/// holds no rendering logic (see `InvoiceService` for PDF generation) and no
/// Firebase / widget dependencies, so it is trivially unit-testable.
///
/// Build one with [Invoice.forCustomer], which turns a customer's active
/// [ServiceContract] into line items (the recurring plan + add-ons at the
/// billing cadence, plus any one-time charge).
class Invoice {
  const Invoice({
    required this.number,
    required this.issueDate,
    required this.dueDate,
    required this.currency,
    required this.seller,
    required this.buyer,
    required this.lines,
    this.billingCycle,
    this.serviceStart,
    this.serviceEnd,
    this.termWindow = '',
    this.notes = '',
    required this.signatoryName,
    required this.signatoryTitle,
    required this.signedAt,
  });

  final String number;
  final DateTime issueDate;
  final DateTime dueDate;
  final CurrencyCode currency;
  final InvoiceParty seller;
  final InvoiceParty buyer;
  final List<InvoiceLine> lines;

  /// The recurring billing cadence, when the invoice bills a subscription.
  final BillingCycle? billingCycle;

  /// The service term boundaries, shown as explicit "Service Start / End Date"
  /// rows on the invoice. Null when the contract left them unset.
  final DateTime? serviceStart;
  final DateTime? serviceEnd;

  /// A human-readable term window, e.g. "01-Apr-2026 → 31-Mar-2027".
  final String termWindow;
  final String notes;

  final String signatoryName;
  final String signatoryTitle;
  final DateTime signedAt;

  /// Sum of every line's amount — the invoice grand total.
  Money get total =>
      lines.fold(Money.zero, (sum, l) => sum + l.amount);

  /// Sum of the recurring (non one-time) lines.
  Money get recurringTotal => lines
      .where((l) => !l.oneTime)
      .fold(Money.zero, (sum, l) => sum + l.amount);

  /// Sum of the one-time lines.
  Money get oneTimeTotal => lines
      .where((l) => l.oneTime)
      .fold(Money.zero, (sum, l) => sum + l.amount);

  /// True when both recurring and one-time charges are present, so the totals
  /// block should split them out rather than showing a single figure.
  bool get hasMixedCharges =>
      recurringTotal.isPositive && oneTimeTotal.isPositive;

  /// No billable lines — there is nothing to invoice.
  bool get isEmpty => lines.isEmpty;

  /// A stable, deterministic document fingerprint shown in the signature block.
  /// Not a cryptographic signature — a tamper-evident reference derived from the
  /// invoice's identifying fields via FNV-1a, so the same invoice always yields
  /// the same 16-hex code and any change to the amounts/parties changes it.
  String get fingerprint {
    final src = '$number|${seller.name}|${buyer.name}|${total.minor}|'
        '${issueDate.toIso8601String()}|${lines.length}';
    return '${_fnv1a(src)}${_fnv1a('sbm$src')}';
  }

  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  /// Builds an invoice for [customer]'s active service contract. Line items are
  /// the recurring plan (unless it is a one-time charge) and each add-on at the
  /// billing cadence, plus any one-time plan charge as a separate flagged line.
  ///
  /// [business] (when resolvable) is the seller; [currency] governs formatting;
  /// [issuerName]/[issuerTitle] and [now] populate the signature block. When the
  /// customer has no contract the result is [isEmpty] (no lines) and callers
  /// should decline to render it.
  factory Invoice.forCustomer({
    required Customer customer,
    required Business? business,
    required CurrencyCode currency,
    required String issuerName,
    required String issuerTitle,
    required DateTime now,
  }) {
    final contract = customer.serviceContract;
    final lines = <InvoiceLine>[];

    if (contract != null) {
      if (contract.priceOneTime) {
        if (contract.price.isPositive) {
          lines.add(InvoiceLine(
            description: '${contract.plan.label} Plan',
            detail: 'One-time charge',
            unitPrice: contract.price,
            oneTime: true,
          ));
        }
      } else if (contract.price.isPositive) {
        lines.add(InvoiceLine(
          description: '${contract.plan.label} Plan Subscription',
          detail: '${contract.billingCycle.label} billing',
          unitPrice: contract.price,
        ));
      }
      for (final a in contract.addOns) {
        if (a.name.trim().isEmpty && a.price.isZero) continue;
        lines.add(InvoiceLine(
          description: a.name.trim().isEmpty ? 'Add-on' : a.name.trim(),
          detail: 'Add-on · ${contract.billingCycle.label}',
          unitPrice: a.price,
        ));
      }
    }

    final today = DateTime(now.year, now.month, now.day);
    final digits = customer.id.replaceAll(RegExp(r'[^0-9]'), '');
    final number = 'INV-${digits.isEmpty ? '00000' : digits}-'
        '${today.year.toString().padLeft(4, '0')}'
        '${today.month.toString().padLeft(2, '0')}'
        '${today.day.toString().padLeft(2, '0')}';

    final sellerLines = <String>[
      if (business != null && business.type.trim().isNotEmpty) business.type.trim(),
      if (business != null && business.website.trim().isNotEmpty) business.website.trim(),
      if (business != null && business.country.trim().isNotEmpty) business.country.trim(),
    ];
    final buyerLines = <String>[
      if (customer.contactNo.trim().isNotEmpty) customer.contactNo.trim(),
      if (customer.email.trim().isNotEmpty) customer.email.trim(),
      if (customer.location.trim().isNotEmpty) customer.location.trim(),
    ];

    return Invoice(
      number: number,
      issueDate: today,
      dueDate: today.add(const Duration(days: 7)),
      currency: currency,
      seller: InvoiceParty(
        name: business?.name.trim().isNotEmpty == true
            ? business!.name.trim()
            : 'Salesforce Business Manager',
        subtitle: business != null ? business.id : '',
        lines: sellerLines,
      ),
      buyer: InvoiceParty(
        name: customer.name.trim().isEmpty ? customer.id : customer.name.trim(),
        subtitle: customer.businessType.trim().isEmpty
            ? customer.id
            : '${customer.businessType.trim()} · ${customer.id}',
        lines: buyerLines,
      ),
      lines: lines,
      billingCycle: contract?.billingCycle,
      serviceStart: contract?.purchaseDate,
      serviceEnd: contract?.expiryDate,
      termWindow: contract == null
          ? ''
          : '${AppDate.format(contract.purchaseDate)} → '
              '${AppDate.format(contract.expiryDate)}',
      notes: contract?.comment.trim() ?? '',
      signatoryName: issuerName,
      signatoryTitle: issuerTitle,
      signedAt: now,
    );
  }
}
