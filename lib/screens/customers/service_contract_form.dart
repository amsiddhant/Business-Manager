import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/customer.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// Create/edit form for a customer's [ServiceContract], opened when a deal is
/// marked "Successful". Captures the plan sold, billing cadence, base price and
/// any add-on line items, with a live subscription total that updates as the
/// user types.
///
/// On submit it marks the customer's deal [DealStatus.successful] and persists
/// the contract embedded in the customer document (no new collection / rules).
class ServiceContractFormDialog extends StatefulWidget {
  const ServiceContractFormDialog({
    super.key,
    required this.customer,
    required this.repo,
    required this.currency,
    this.isRenewal = false,
  });

  final Customer customer;
  final Repository repo;
  final CurrencyCode currency;

  /// When true the current active contract is archived to history and a new
  /// term is captured (a renewal), rather than editing the active term in
  /// place. The form pre-fills the previous term's plan/price/add-ons for
  /// convenience but starts a fresh purchase/expiry window.
  final bool isRenewal;

  @override
  State<ServiceContractFormDialog> createState() =>
      _ServiceContractFormDialogState();
}

/// A name+price controller pair backing one editable add-on row.
class _AddOnRow {
  _AddOnRow({String name = '', String price = ''})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price);

  final TextEditingController name;
  final TextEditingController price;

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class _ServiceContractFormDialogState
    extends State<ServiceContractFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _price;
  late final TextEditingController _comment;

  late SubscriptionPlan _plan;
  late BillingCycle _cycle;
  bool _priceOneTime = false;
  DateTime? _purchaseDate;
  DateTime? _expiryDate;

  bool _hasAddOns = false;
  final List<_AddOnRow> _addOns = [];

  /// The active contract on the customer, if any.
  ServiceContract? get _active => widget.customer.serviceContract;

  /// Whether this is a first-time capture (no active contract to edit/renew).
  bool get _isNew => _active == null;

  /// True when editing the active term in place (not a first capture, not a
  /// renewal).
  bool get _isEdit => !_isNew && !widget.isRenewal;

  @override
  void initState() {
    super.initState();
    // Seed values from the active contract for edit AND renewal (renewal keeps
    // the same plan/pricing by default but resets the term window below).
    final c = _active;
    _price = TextEditingController(
        text: c == null || c.price.isZero
            ? ''
            : c.price.major.toStringAsFixed(2));
    _comment = TextEditingController(text: _isEdit ? (c?.comment ?? '') : '');
    _plan = c?.plan ?? SubscriptionPlan.basic;
    _cycle = c?.billingCycle ?? BillingCycle.yearly;
    _priceOneTime = c?.priceOneTime ?? false;
    // A renewal starts a fresh term today; an edit keeps the stored dates.
    _purchaseDate = _isEdit ? (c?.purchaseDate ?? DateTime.now()) : DateTime.now();
    _expiryDate = _isEdit ? c?.expiryDate : null;
    if (c != null && c.addOns.isNotEmpty) {
      _hasAddOns = true;
      for (final a in c.addOns) {
        _addOns.add(_AddOnRow(
            name: a.name,
            price: a.price.isZero ? '' : a.price.major.toStringAsFixed(2)));
      }
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _comment.dispose();
    for (final r in _addOns) {
      r.dispose();
    }
    super.dispose();
  }

  // ---- Live total -----------------------------------------------------------

  Money get _basePrice => Money.parse(_price.text);

  Money get _addOnsTotal {
    if (!_hasAddOns) return Money.zero;
    return _addOns.fold(Money.zero, (sum, r) => sum + Money.parse(r.price.text));
  }

  /// The recurring subscription total: add-ons plus the base price, unless the
  /// base price is flagged one-time (then it is excluded).
  Money get _recurringTotal =>
      (_priceOneTime ? Money.zero : _basePrice) + _addOnsTotal;

  /// The one-off charge shown separately when the plan price is one-time.
  Money get _oneTimeTotal => _priceOneTime ? _basePrice : Money.zero;

  void _addAddOn() => setState(() => _addOns.add(_AddOnRow()));

  void _removeAddOn(int index) => setState(() {
        _addOns.removeAt(index).dispose();
      });

  void _toggleAddOns(bool value) => setState(() {
        _hasAddOns = value;
        if (value && _addOns.isEmpty) {
          _addOns.add(_AddOnRow());
        }
      });

  @override
  Widget build(BuildContext context) {
    final String title;
    final String submitLabel;
    if (widget.isRenewal) {
      title = 'Renew Service Contract';
      submitLabel = 'Save Renewal';
    } else if (_isNew) {
      title = 'Service Contract';
      submitLabel = 'Save Contract';
    } else {
      title = 'Edit Service Contract';
      submitLabel = 'Update Contract';
    }

    final priceLabel = _priceOneTime
        ? 'Plan Price (one-time)'
        : 'Plan Price (${_cycle.label.toLowerCase()})';

    return FormDialog(
      title: title,
      submitLabel: submitLabel,
      width: 600,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        // Rebuild the live-total banner as the user edits any price field.
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isRenewal) ...[
              const _RenewalBanner(),
              const FormGap(),
            ],
            _BillingCycleToggle(
              value: _cycle,
              onChanged: (v) => setState(() => _cycle = v),
            ),
            const FormGap(),
            FormRow([
              AppDropdown<SubscriptionPlan>(
                label: 'Plan Name',
                value: _plan,
                isRequired: true,
                items: SubscriptionPlan.values,
                itemLabel: (p) => p.label,
                onChanged: (v) => setState(() => _plan = v ?? _plan),
              ),
              AppMoneyField(
                label: priceLabel,
                controller: _price,
                isRequired: true,
                symbol: widget.currency.symbol,
                validator: (v) => Validators.nonNegativeNumber(v, field: 'Price'),
              ),
            ]),
            const SizedBox(height: AppSpacing.sm),
            _OneTimeToggle(
              value: _priceOneTime,
              cycle: _cycle,
              onChanged: (v) => setState(() => _priceOneTime = v),
            ),
            const FormGap(),
            FormRow([
              AppDateField(
                label: 'Date of Purchase',
                value: _purchaseDate,
                isRequired: true,
                onChanged: (v) => setState(() => _purchaseDate = v),
              ),
              AppDateField(
                label: 'Expiry Date',
                value: _expiryDate,
                firstDate: _purchaseDate,
                onChanged: (v) => setState(() => _expiryDate = v),
              ),
            ]),
            const FormGap(),
            _AddOnsSection(
              enabled: _hasAddOns,
              onToggle: _toggleAddOns,
              rows: _addOns,
              currency: widget.currency,
              onAdd: _addAddOn,
              onRemove: _removeAddOn,
            ),
            const FormGap(),
            AppTextField(
              label: 'Comment',
              controller: _comment,
              maxLines: 3,
              hintText: 'Notes about this contract (optional)',
            ),
            const FormGap(),
            _TotalBanner(
              recurringTotal: _recurringTotal,
              oneTimeTotal: _oneTimeTotal,
              cycle: _cycle,
              currency: widget.currency,
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    if (_purchaseDate == null) {
      showErrorSnack(context, 'Select the date of purchase.');
      return false;
    }
    if (_expiryDate != null && _expiryDate!.isBefore(_purchaseDate!)) {
      showErrorSnack(context, 'Expiry date must be on or after the purchase date.');
      return false;
    }

    final addOns = <ServiceAddOn>[];
    if (_hasAddOns) {
      for (final r in _addOns) {
        final name = r.name.text.trim();
        if (name.isEmpty) continue; // skip blank rows
        addOns.add(ServiceAddOn(name: name, price: Money.parse(r.price.text)));
      }
    }

    final contract = ServiceContract(
      purchaseDate: _purchaseDate,
      expiryDate: _expiryDate,
      price: _basePrice,
      priceOneTime: _priceOneTime,
      plan: _plan,
      billingCycle: _cycle,
      addOns: addOns,
      comment: _comment.text.trim(),
    );

    // A renewal archives the active term into history; an edit/first capture
    // replaces the active term directly.
    final updated = widget.isRenewal
        ? widget.customer.withRenewedContract(contract)
        : widget.customer.copyWith(
            dealStatus: DealStatus.successful,
            serviceContract: contract,
          );

    try {
      await widget.repo.saveCustomer(
        updated,
        isNew: false,
      );
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}

/// A two-option segmented control for the billing cadence (Monthly / Yearly).
class _BillingCycleToggle extends StatelessWidget {
  const _BillingCycleToggle({required this.value, required this.onChanged});

  final BillingCycle value;
  final ValueChanged<BillingCycle> onChanged;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: 'Billing Cycle',
      isRequired: true,
      helper: 'All plan and add-on prices are charged at this cadence.',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          children: [
            for (final c in BillingCycle.values)
              Expanded(
                child: _Segment(
                  label: c.label,
                  selected: c == value,
                  onTap: () => onChanged(c),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm - 2),
          boxShadow: selected ? AppTheme.cardShadow : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The "Add-On services" checkbox and its repeatable {name, price} rows.
class _AddOnsSection extends StatelessWidget {
  const _AddOnsSection({
    required this.enabled,
    required this.onToggle,
    required this.rows,
    required this.currency,
    required this.onAdd,
    required this.onRemove,
  });

  final bool enabled;
  final ValueChanged<bool> onToggle;
  final List<_AddOnRow> rows;
  final CurrencyCode currency;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? AppColors.primarySurface : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
            color: enabled ? AppColors.primaryLight : AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: () => onToggle(!enabled),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Checkbox(
                    value: enabled,
                    onChanged: (v) => onToggle(v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add-On services',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text('Bundle extra paid services onto this contract.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _AddOnRowFields(
                row: rows[i],
                currency: currency,
                onRemove: () => onRemove(i),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add another service'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddOnRowFields extends StatelessWidget {
  const _AddOnRowFields({
    required this.row,
    required this.currency,
    required this.onRemove,
  });

  final _AddOnRow row;
  final CurrencyCode currency;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            label: 'Add-On Name',
            controller: row.name,
            hintText: 'e.g. Priority Support',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: AppMoneyField(
            label: 'Price',
            controller: row.price,
            symbol: currency.symbol,
          ),
        ),
        IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.close, size: 18),
          color: AppColors.textTertiary,
          onPressed: onRemove,
        ),
      ],
    );
  }
}

/// A checkbox that flags the plan price as a one-time charge (excluded from the
/// recurring subscription) rather than a recurring one billed each cycle.
class _OneTimeToggle extends StatelessWidget {
  const _OneTimeToggle({
    required this.value,
    required this.cycle,
    required this.onChanged,
  });

  final bool value;
  final BillingCycle cycle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'One-time charge  ',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: value
                          ? '— billed once, not added to the subscription total.'
                          : '— plan price recurs every ${cycle.label.toLowerCase()}.',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An informational banner shown at the top of the form when renewing, so the
/// user understands the current term will be archived to history.
class _RenewalBanner extends StatelessWidget {
  const _RenewalBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.autorenew, size: 20, color: AppColors.info),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'The current term will be archived to the renewal history and '
              'this new term will become active.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A prominent banner summarising the total recurring subscription value, plus
/// a secondary line for any one-time charge.
class _TotalBanner extends StatelessWidget {
  const _TotalBanner({
    required this.recurringTotal,
    required this.oneTimeTotal,
    required this.cycle,
    required this.currency,
  });

  final Money recurringTotal;
  final Money oneTimeTotal;
  final BillingCycle cycle;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  color: Colors.white70, size: 22),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text('Total Subscription',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
              Text(
                '${MoneyFormatter.format(recurringTotal, currency)} /${cycle.unit}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (oneTimeTotal.isPositive) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 22 + AppSpacing.md),
                const Expanded(
                  child: Text('One-time charge',
                      style:
                          TextStyle(color: Colors.white60, fontSize: 12)),
                ),
                Text(
                  MoneyFormatter.format(oneTimeTotal, currency),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
