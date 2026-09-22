import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../../core/app_exception.dart';
import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/app_user.dart';
import '../../models/business.dart';
import '../../models/contact.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../view_models/customer_contacts_view_model.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/initials_avatar.dart';
import '../../widgets/common/search_field.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/responsive.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import 'customers_screen.dart';
import 'invoice_action.dart';
import 'service_contract_form.dart';

/// A full-screen customer profile: contact & company details on the left, and a
/// deal-status / last-activity / comment-thread column on the right.
class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Customer'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
    }

    final customer = data.customerById(customerId);
    if (customer == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Customer',
            actions: [
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.customers),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Customers'),
              ),
            ],
          ),
          const SizedBox(height: 48),
          const EmptyView(
            icon: Icons.search_off,
            title: 'Customer not found',
            message:
                'This customer may have been removed or is not accessible.',
          ),
        ],
      );
    }

    // Businesses this customer is tagged to that are visible in the current
    // scope (a non-owner may not be able to resolve every tag to a name).
    final businesses = [
      for (final id in customer.businessIds)
        if (data.businessById(id) != null) data.businessById(id)!,
    ];
    final canEdit = user?.can(Permission.editCustomer) ?? false;
    final isMobile = Responsive.isMobile(context);

    // Orders placed by this customer. `ordersForCustomer` matches on the order's
    // customerReference over the already access-scoped order set, so a non-owner
    // only ever sees orders for businesses they can access.
    final orders = data.ordersForCustomer(customer.id);
    // A customer can span several businesses; use the first visible business's
    // currency as a fallback (per-contract displays use their own business's).
    final currency =
        businesses.isNotEmpty ? businesses.first.currency : CurrencyCode.inr;

    // The globally-selected business scopes which contracts show: a specific
    // business shows only its contract; "All Businesses" (null) shows every
    // visible business's contract. Non-owners only ever see businesses they are
    // assigned to (businesses is already filtered to what they can resolve), so
    // this never leaks a contract for an inaccessible business.
    final filter = context.watch<FilterController>();
    final scopedId = filter.selectedBusinessId;
    final contractBusinesses = [
      for (final b in businesses)
        if ((scopedId == null || b.id == scopedId) &&
            customer.hasContractFor(b.id))
          b,
    ];
    // The Profile card's headline subscription figure is only unambiguous when
    // exactly one contract is in scope.
    final highlightBusiness =
        contractBusinesses.length == 1 ? contractBusinesses.first : null;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileCard(
          customer: customer,
          businesses: businesses,
          scopedBusinessId: scopedId,
          highlightContract: highlightBusiness == null
              ? null
              : customer.activeContractFor(highlightBusiness.id),
          highlightCurrency: highlightBusiness?.currency ?? currency,
          canEdit: canEdit,
        ),
        for (final b in contractBusinesses) ...[
          const SizedBox(height: AppSpacing.lg),
          _ServiceContractCard(
            customer: customer,
            business: b,
            active: customer.activeContractFor(b.id)!,
            history: customer.historyFor(b.id),
            showBusinessName: contractBusinesses.length > 1 || scopedId == null,
            canEdit: canEdit,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _ContactsCard(customer: customer, canEdit: canEdit),
        const SizedBox(height: AppSpacing.lg),
        _OrdersCard(orders: orders, businesses: businesses),
        const SizedBox(height: AppSpacing.lg),
        _TeamAccessCard(customer: customer),
      ],
    );
    final right = _ActivityColumn(customer: customer, canComment: canEdit);

    final subtitle = StringBuffer(customer.id);
    if (businesses.length == 1) {
      subtitle.write(' · ${businesses.first.name}');
    } else if (businesses.length > 1) {
      subtitle.write(' · ${businesses.length} businesses');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: customer.name,
          subtitle: subtitle.toString(),
          actions: [
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.customers),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
            if (contractBusinesses.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => generateCustomerInvoice(
                  context,
                  customer,
                  businessId: scopedId,
                  business: highlightBusiness ??
                      (businesses.isNotEmpty ? businesses.first : null),
                  currency: highlightBusiness?.currency ?? currency,
                ),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Invoice'),
              ),
            if (canEdit)
              ElevatedButton.icon(
                onPressed: () => _edit(context, customer, data),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (isMobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: AppSpacing.lg),
              right,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: left),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: 340, child: right),
            ],
          ),
      ],
    );
  }

  Future<void> _edit(
      BuildContext context, Customer customer, DataController data) async {
    final repo = context.read<AppState>().repository;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CustomerFormDialog(
        existing: customer,
        repo: repo,
        businesses: data.selectableBusinesses,
      ),
    );
    if (saved == true) {
      await data.refresh();
      if (context.mounted) {
        showSuccessSnack(context, 'Customer updated successfully');
      }
    }
  }
}

/// Prompts the user to choose which of the customer's [businesses] a contract
/// should be captured under, for the ambiguous "All Businesses" case where the
/// customer spans several. Returns the chosen business, or null if dismissed.
Future<Business?> _pickBusiness(
    BuildContext context, List<Business> businesses) {
  return showDialog<Business>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Which business is this contract for?'),
      children: [
        for (final b in businesses)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(b),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.storefront_outlined,
                      size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(b.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

/// Left column: avatar + contact and company details. Every field shows a small
/// copy icon; the social-media value renders as a link button opening in a new
/// tab. The header carries a colour-coded deal-status changer, and — once a
/// deal is won — a prominent subscription total.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.customer,
    required this.businesses,
    required this.scopedBusinessId,
    required this.highlightContract,
    required this.highlightCurrency,
    required this.canEdit,
  });

  final Customer customer;
  final List<Business> businesses;

  /// The globally-selected business (null == All Businesses), used to scope the
  /// deal-status changer's contract capture.
  final String? scopedBusinessId;

  /// The single in-scope contract to feature in the headline band, or null when
  /// zero or several are in scope (then no single figure is unambiguous).
  final ServiceContract? highlightContract;
  final CurrencyCode highlightCurrency;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final details = <_Detail>[
      _Detail('Customer ID', customer.id, Icons.badge_outlined),
      _Detail('Business Type', customer.businessType, Icons.category_outlined),
      _Detail('Company Size', customer.size.label, Icons.groups_outlined),
      _Detail('Contact No', customer.contactNo, Icons.phone_outlined),
      _Detail('Email', customer.email, Icons.mail_outline),
      _Detail('Location', customer.location, Icons.location_on_outlined),
      _Detail('Social Media', customer.socialMedia, Icons.public,
          isLink: true),
    ];

    return SectionCard(
      title: 'Profile',
      trailing: _DealStatusChanger(
        customer: customer,
        businesses: businesses,
        scopedBusinessId: scopedBusinessId,
        enabled: canEdit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(name: customer.name, size: 64),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(customer.name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                        ),
                        _CopyButton(label: 'name', value: customer.name),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer.businessType.isEmpty
                          ? customer.id
                          : '${customer.businessType} · ${customer.id}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (highlightContract != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _SubscriptionHighlight(
              contract: highlightContract!,
              currency: highlightCurrency,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = Responsive.isMobile(context) ? 1 : 2;
              const gap = AppSpacing.lg;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final d in details)
                    SizedBox(width: tileWidth, child: _DetailRow(detail: d)),
                ],
              );
            },
          ),
          if (customer.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Text('Description',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                _CopyButton(label: 'description', value: customer.description),
              ],
            ),
            const SizedBox(height: 4),
            Text(customer.description,
                style: const TextStyle(height: 1.5)),
          ],
        ],
      ),
    );
  }
}

/// The colour-coded deal-status changer shown in the Profile card header.
///
/// Renders the current status as a coloured pill with a dropdown caret. Picking
/// a new status persists it immediately; picking "Successful" first opens the
/// [ServiceContractFormDialog] and only commits the status if a contract is
/// saved. Disabled (non-interactive pill) when the viewer lacks edit rights.
class _DealStatusChanger extends StatefulWidget {
  const _DealStatusChanger({
    required this.customer,
    required this.businesses,
    required this.scopedBusinessId,
    required this.enabled,
  });

  final Customer customer;
  final List<Business> businesses;

  /// The globally-selected business (null == All Businesses). When set, a
  /// "won" deal captures that business's contract directly; when null the user
  /// is asked which of their businesses the contract is for.
  final String? scopedBusinessId;
  final bool enabled;

  @override
  State<_DealStatusChanger> createState() => _DealStatusChangerState();
}

class _DealStatusChangerState extends State<_DealStatusChanger> {
  bool _busy = false;

  ({Color fg, Color bg}) _colorsFor(DealStatus status) {
    switch (status) {
      case DealStatus.successful:
        return (fg: AppColors.success, bg: AppColors.successSurface);
      case DealStatus.inProgress:
        return (fg: AppColors.info, bg: AppColors.infoSurface);
      case DealStatus.pending:
        return (fg: AppColors.warning, bg: AppColors.warningSurface);
      case DealStatus.cancelled:
        return (fg: AppColors.error, bg: AppColors.errorSurface);
    }
  }

  Future<void> _select(DealStatus status) async {
    if (_busy || status == widget.customer.dealStatus) return;
    if (status == DealStatus.successful) {
      await _openContractForm();
      return;
    }
    await _persistStatus(status);
  }

  /// Marks the deal won by capturing a service contract for a specific business.
  /// The status only moves to Successful when the contract is actually saved.
  ///
  /// The target business is the globally-selected one when set; under "All
  /// Businesses" the user is asked which of the customer's businesses the
  /// contract is for (skipped when only one is tagged).
  Future<void> _openContractForm() async {
    final business = await _resolveTargetBusiness();
    if (business == null || !mounted) return;

    final repo = context.read<AppState>().repository;
    final data = context.read<DataController>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ServiceContractFormDialog(
        customer: widget.customer,
        repo: repo,
        business: business,
      ),
    );
    if (saved == true) {
      await data.refresh();
      if (mounted) {
        showSuccessSnack(context, 'Deal won — service contract saved');
      }
    }
  }

  /// Resolves which business the contract is captured under: the selected
  /// business when one is in scope, else the sole tagged business, else a
  /// picker. Returns null when the user cancels or no business is available.
  Future<Business?> _resolveTargetBusiness() async {
    final scopedId = widget.scopedBusinessId;
    if (scopedId != null) {
      for (final b in widget.businesses) {
        if (b.id == scopedId) return b;
      }
    }
    if (widget.businesses.isEmpty) {
      showErrorSnack(context, 'No business available to attach this contract.');
      return null;
    }
    if (widget.businesses.length == 1) return widget.businesses.first;
    return _pickBusiness(context, widget.businesses);
  }

  Future<void> _persistStatus(DealStatus status) async {
    final repo = context.read<AppState>().repository;
    final data = context.read<DataController>();
    setState(() => _busy = true);
    try {
      await repo.saveCustomer(
        widget.customer.copyWith(dealStatus: status),
        isNew: false,
      );
      await data.refresh();
      if (mounted) {
        showSuccessSnack(context, 'Deal status updated to ${status.label}');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.customer.dealStatus;
    final c = _colorsFor(status);
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            status.label,
            style: TextStyle(
                color: c.fg, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (widget.enabled) ...[
            const SizedBox(width: 2),
            _busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.fg),
                    ),
                  )
                : Icon(Icons.arrow_drop_down, color: c.fg, size: 20),
          ],
        ],
      ),
    );

    if (!widget.enabled) return pill;

    return PopupMenuButton<DealStatus>(
      enabled: !_busy,
      tooltip: 'Change deal status',
      position: PopupMenuPosition.under,
      onSelected: _select,
      itemBuilder: (context) => [
        for (final s in DealStatus.values)
          PopupMenuItem<DealStatus>(
            value: s,
            child: _StatusMenuItem(
              status: s,
              colors: _colorsFor(s),
              selected: s == status,
            ),
          ),
      ],
      child: pill,
    );
  }
}

/// One row in the deal-status dropdown menu: a colour dot, the label, and
/// (for the current status) a check.
class _StatusMenuItem extends StatelessWidget {
  const _StatusMenuItem({
    required this.status,
    required this.colors,
    required this.selected,
  });

  final DealStatus status;
  final ({Color fg, Color bg}) colors;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: colors.fg, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            status == DealStatus.successful
                ? '${status.label} — add contract'
                : status.label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        if (selected)
          const Icon(Icons.check, size: 16, color: AppColors.primary),
      ],
    );
  }
}

/// The prominent total-subscription figure shown inside the Profile card once a
/// contract exists. A gradient band mirroring the form's total banner.
class _SubscriptionHighlight extends StatelessWidget {
  const _SubscriptionHighlight({
    required this.contract,
    required this.currency,
  });

  final ServiceContract contract;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final remaining = contract.timeRemainingAsOf(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.workspace_premium_outlined,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '${contract.plan.label} · Total Subscription',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${MoneyFormatter.format(contract.total, currency)} '
                  '/${contract.billingCycle.unit}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.1),
                ),
                if (contract.billingCycle == BillingCycle.monthly) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${MoneyFormatter.format(contract.annualTotal, currency)} / year',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12),
                  ),
                ],
                if (contract.hasOneTimeCharge) ...[
                  const SizedBox(height: 2),
                  Text(
                    '+ ${MoneyFormatter.format(contract.oneTimeTotal, currency)} one-time',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (remaining != null) ...[
            const SizedBox(width: AppSpacing.md),
            _RemainingPill(remaining: remaining),
          ],
        ],
      ),
    );
  }
}

/// A compact "time remaining" chip rendered on the subscription highlight band.
/// Shows the largest units (e.g. "1 yr 2 mo") with a "left"/"ago" caption, and
/// turns translucent-red once the term has lapsed.
class _RemainingPill extends StatelessWidget {
  const _RemainingPill({required this.remaining});

  final TimeRemaining remaining;

  @override
  Widget build(BuildContext context) {
    final expired = remaining.isPast;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: expired
            ? AppColors.error.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            remaining.isToday ? 'Today' : remaining.shortLabel,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.1),
          ),
          const SizedBox(height: 1),
          Text(
            remaining.isToday
                ? 'expires'
                : (expired ? 'overdue' : 'remaining'),
            style: const TextStyle(color: Colors.white70, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

/// The "Service Contract" card shown directly under the Profile card once a
/// deal is won. Presents the plan, billing cadence, dates and add-on line items
/// with a running total, and offers an edit action for permitted viewers.
class _ServiceContractCard extends StatelessWidget {
  const _ServiceContractCard({
    required this.customer,
    required this.business,
    required this.active,
    required this.history,
    required this.showBusinessName,
    required this.canEdit,
  });

  final Customer customer;

  /// The business this contract is for; its currency governs the display and it
  /// is the target the edit/renew form writes back to.
  final Business business;
  final ServiceContract active;
  final List<ServiceContract> history;

  /// Whether to show the business name in the card title, so several cards for
  /// a multi-business customer (or the "All Businesses" view) are distinguished.
  final bool showBusinessName;
  final bool canEdit;

  CurrencyCode get currency => business.currency;

  Future<void> _openForm(BuildContext context, {required bool isRenewal}) async {
    final repo = context.read<AppState>().repository;
    final data = context.read<DataController>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ServiceContractFormDialog(
        customer: customer,
        repo: repo,
        business: business,
        isRenewal: isRenewal,
      ),
    );
    if (saved == true) {
      await data.refresh();
      if (context.mounted) {
        showSuccessSnack(
          context,
          isRenewal ? 'Contract renewed' : 'Service contract updated',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contract = active;
    final now = DateTime.now();
    final expired = contract.isExpiredAsOf(now);
    final remaining = contract.timeRemainingAsOf(now);

    return SectionCard(
      title: showBusinessName
          ? 'Service Contract · ${business.name}'
          : 'Service Contract',
      subtitle: history.isNotEmpty
          ? 'Active term · renewed ${history.length}×'
          : 'Subscription captured when the deal was won',
      trailing: canEdit
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () => _openForm(context, isRenewal: true),
                  icon: const Icon(Icons.autorenew, size: 16),
                  label: const Text('Renew'),
                ),
                const SizedBox(width: 2),
                TextButton.icon(
                  onPressed: () => _openForm(context, isRenewal: false),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Headline chips: plan, billing cadence, contract state.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _ContractChip(
                icon: Icons.workspace_premium_outlined,
                label: contract.plan.label,
                tone: BadgeTone.primary,
              ),
              _ContractChip(
                icon: Icons.autorenew,
                label: contract.billingCycle.label,
                tone: BadgeTone.info,
              ),
              _ContractChip(
                icon: expired
                    ? Icons.error_outline
                    : Icons.verified_outlined,
                label: expired ? 'Expired' : 'Active',
                tone: expired ? BadgeTone.error : BadgeTone.success,
              ),
              if (remaining != null && !remaining.isPast)
                _ContractChip(
                  icon: Icons.hourglass_bottom,
                  label: '${remaining.shortLabel} left',
                  tone: BadgeTone.neutral,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Dates + time remaining.
          Row(
            children: [
              Expanded(
                child: _ContractStat(
                  icon: Icons.event_available_outlined,
                  label: 'Purchased',
                  value: AppDate.format(contract.purchaseDate),
                ),
              ),
              Expanded(
                child: _ContractStat(
                  icon: Icons.event_busy_outlined,
                  label: 'Expires',
                  value: AppDate.format(contract.expiryDate),
                  valueColor: expired ? AppColors.error : null,
                ),
              ),
            ],
          ),
          if (remaining != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ContractStat(
              icon: remaining.isPast
                  ? Icons.warning_amber_rounded
                  : Icons.hourglass_bottom,
              label: remaining.isPast ? 'Overdue by' : 'Time remaining',
              value: remaining.isToday
                  ? 'Expires today'
                  : '${remaining.shortLabel}'
                      '${remaining.isPast ? ' overdue' : ' remaining'}',
              valueColor: remaining.isPast ? AppColors.error : AppColors.primary,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          // Line items: base plan + each add-on, with a total footer.
          _ContractLine(
            label: contract.priceOneTime
                ? '${contract.plan.label} plan (one-time)'
                : '${contract.plan.label} plan',
            value: MoneyFormatter.format(contract.price, currency),
            emphasise: true,
            muted: contract.priceOneTime,
          ),
          for (final a in contract.addOns) ...[
            const SizedBox(height: AppSpacing.sm),
            _ContractLine(
              label: a.name.isEmpty ? 'Add-on' : a.name,
              value: MoneyFormatter.format(a.price, currency),
              leadingIcon: Icons.add_circle_outline,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          _ContractLine(
            label: 'Total per ${contract.billingCycle.unit}',
            value:
                '${MoneyFormatter.format(contract.total, currency)} /${contract.billingCycle.unit}',
            isTotal: true,
          ),
          if (contract.hasOneTimeCharge) ...[
            const SizedBox(height: AppSpacing.sm),
            _ContractLine(
              label: 'One-time charge',
              value: MoneyFormatter.format(contract.oneTimeTotal, currency),
              muted: true,
            ),
          ],
          if (contract.comment.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notes_outlined,
                          size: 15, color: AppColors.textTertiary),
                      SizedBox(width: 6),
                      Text('Comment',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(contract.comment,
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _RenewalHistory(
              history: history,
              currency: currency,
            ),
          ],
        ],
      ),
    );
  }
}

/// A collapsible timeline of superseded contract terms (the renewal log),
/// newest-first. The active term is shown above in the main card; this lists
/// each prior term with its plan, window and recurring total.
class _RenewalHistory extends StatelessWidget {
  const _RenewalHistory({required this.history, required this.currency});

  final List<ServiceContract> history;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        leading: const Icon(Icons.history, size: 20, color: AppColors.textTertiary),
        title: Text('Renewal History (${history.length})',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: const Text('Previous terms, most recent first',
            style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
        children: [
          for (var i = 0; i < history.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _RenewalHistoryEntry(
              contract: history[i],
              currency: currency,
              ordinal: history.length - i,
            ),
          ],
        ],
      ),
    );
  }
}

/// One superseded term in the renewal history.
class _RenewalHistoryEntry extends StatelessWidget {
  const _RenewalHistoryEntry({
    required this.contract,
    required this.currency,
    required this.ordinal,
  });

  final ServiceContract contract;
  final CurrencyCode currency;

  /// 1-based position of this term in the customer's lifetime (term #1 is the
  /// original), used purely as a label.
  final int ordinal;

  @override
  Widget build(BuildContext context) {
    final window =
        '${AppDate.format(contract.purchaseDate)} → ${AppDate.format(contract.expiryDate)}';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text('Term $ordinal',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${contract.plan.label} · ${contract.billingCycle.label}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${MoneyFormatter.format(contract.total, currency)} /${contract.billingCycle.unit}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.date_range_outlined,
                  size: 13, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(window,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          if (contract.hasOneTimeCharge) ...[
            const SizedBox(height: 2),
            Text(
              '+ ${MoneyFormatter.format(contract.oneTimeTotal, currency)} one-time',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
          if (contract.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(contract.comment,
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// A small icon + label chip used for the contract headline (plan / cadence /
/// state), reusing the badge tone palette.
class _ContractChip extends StatelessWidget {
  const _ContractChip({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final BadgeTone tone;

  ({Color fg, Color bg}) get _colors {
    switch (tone) {
      case BadgeTone.success:
        return (fg: AppColors.success, bg: AppColors.successSurface);
      case BadgeTone.error:
        return (fg: AppColors.error, bg: AppColors.errorSurface);
      case BadgeTone.info:
        return (fg: AppColors.info, bg: AppColors.infoSurface);
      case BadgeTone.primary:
        return (fg: AppColors.primary, bg: AppColors.primaryLight);
      case BadgeTone.warning:
        return (fg: AppColors.warning, bg: AppColors.warningSurface);
      case BadgeTone.neutral:
        return (fg: AppColors.textSecondary, bg: AppColors.surfaceAlt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: c.fg),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: c.fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A labelled statistic (icon + caption + value) used for the contract dates.
class _ContractStat extends StatelessWidget {
  const _ContractStat({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor)),
          ],
        ),
      ],
    );
  }
}

/// A single line item / total row within the contract breakdown.
class _ContractLine extends StatelessWidget {
  const _ContractLine({
    required this.label,
    required this.value,
    this.leadingIcon,
    this.emphasise = false,
    this.isTotal = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final IconData? leadingIcon;
  final bool emphasise;
  final bool isTotal;

  /// When true this line is a non-recurring item (e.g. a one-time charge): its
  /// value is rendered in a subdued colour so it reads as excluded from the
  /// recurring subscription total.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final valueColor = isTotal
        ? AppColors.primary
        : (muted ? AppColors.textTertiary : AppColors.textPrimary);
    return Row(
      children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14.5 : 13.5,
              color: isTotal ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: isTotal
                  ? FontWeight.w700
                  : (emphasise ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _Detail {
  const _Detail(this.label, this.value, this.icon, {this.isLink = false});
  final String label;
  final String value;
  final IconData icon;

  /// When true the value renders as a link button opening in a new tab.
  final bool isLink;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail});
  final _Detail detail;

  @override
  Widget build(BuildContext context) {
    final value = detail.value.trim();
    final hasValue = value.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(detail.icon, size: 18, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(detail.label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              if (detail.isLink && hasValue && _looksLikeUrl(value))
                _LinkButton(value: value)
              else
                Text(hasValue ? value : '—',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        if (hasValue)
          _CopyButton(label: detail.label.toLowerCase(), value: value),
      ],
    );
  }
}

/// A small icon button that copies [value] to the clipboard and confirms via a
/// snackbar. Present next to every field value in the profile.
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.copy_outlined, size: 15),
      color: AppColors.textTertiary,
      tooltip: 'Copy $label',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) showSuccessSnack(context, 'Copied $label');
      },
    );
  }
}

/// Renders a social-media value as a link button that opens in a new browser
/// tab. Mirrors the product detail screen's URL handling.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _openUrl(value),
        icon: const Icon(Icons.open_in_new, size: 15),
        label: Text(value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

/// Whether [value] can be opened as a real web URL. A fully-qualified URL
/// (has an http/https scheme) or a bare domain (contains a dot, no leading '@')
/// qualifies; handle-style values like "@acme" or "acmehandle" do not — opening
/// them would resolve against the app origin and produce a broken tab.
bool _looksLikeUrl(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  if (v.startsWith(RegExp(r'https?://', caseSensitive: false))) return true;
  return !v.startsWith('@') && v.contains('.');
}

/// Opens [url] in a new browser tab, prepending https:// for bare domains.
/// No-ops for values that are not resolvable URLs (see [_looksLikeUrl]) so a
/// handle never navigates to a bogus same-origin path.
void _openUrl(String url) {
  var normalised = url.trim();
  if (!_looksLikeUrl(normalised)) return;
  if (!normalised.startsWith(RegExp(r'https?://', caseSensitive: false))) {
    normalised = 'https://$normalised';
  }
  html.window.open(normalised, '_blank');
}

/// An expandable tree of the people with access to this customer, grouped by
/// business → Owner / Admins / Users.
///
/// Enumerating user profiles is Owner-only in the Firestore rules
/// (`allow list: if isOwner()`), so a non-owner's roster query is rejected with
/// permission-denied ("rules are not filters"). For non-owner viewers we
/// therefore show the tagged businesses but gate the roster behind an
/// Owner-only note rather than issuing a query that would fail.
class _TeamAccessCard extends StatefulWidget {
  const _TeamAccessCard({required this.customer});

  final Customer customer;

  @override
  State<_TeamAccessCard> createState() => _TeamAccessCardState();
}

class _TeamAccessCardState extends State<_TeamAccessCard> {
  Future<List<AppUser>>? _rosterFuture;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    if (appState.currentUser?.isOwner ?? false) {
      _rosterFuture = appState.repository.fetchUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final isOwnerViewer = appState.currentUser?.isOwner ?? false;

    // Resolve the tagged businesses that are visible in the current scope.
    final businesses = [
      for (final id in widget.customer.businessIds)
        if (data.businessById(id) != null) data.businessById(id)!,
    ];

    return SectionCard(
      title: 'Team Access',
      subtitle: 'Businesses, owners, admins & users with access',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (businesses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('Not tagged to any accessible business.',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          else if (!isOwnerViewer)
            _TeamTree(businesses: businesses, roster: const [], gated: true)
          else
            FutureBuilder<List<AppUser>>(
              future: _rosterFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(ErrorMapper.friendly(snap.error!),
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  );
                }
                return _TeamTree(
                  businesses: businesses,
                  roster: snap.data ?? const [],
                  gated: false,
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The Business → Owner / Admins / Users expansion tree. When [gated] is true
/// (non-owner viewer) the per-business roster is replaced with an Owner-only
/// note, since listing user profiles is not permitted for that caller.
class _TeamTree extends StatelessWidget {
  const _TeamTree({
    required this.businesses,
    required this.roster,
    required this.gated,
  });

  final List<Business> businesses;
  final List<AppUser> roster;
  final bool gated;

  @override
  Widget build(BuildContext context) {
    // Owners have global access regardless of assignment.
    final owners =
        roster.where((u) => u.role == UserRole.owner).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in businesses)
          _BusinessNode(
            business: b,
            owners: owners,
            admins: roster
                .where((u) =>
                    u.role == UserRole.admin &&
                    u.assignedBusinessIds.contains(b.id))
                .toList(),
            users: roster
                .where((u) =>
                    u.role == UserRole.user &&
                    u.assignedBusinessIds.contains(b.id))
                .toList(),
            gated: gated,
          ),
      ],
    );
  }
}

/// A single business branch in the tree with nested Owner / Admins / Users
/// groups.
class _BusinessNode extends StatelessWidget {
  const _BusinessNode({
    required this.business,
    required this.owners,
    required this.admins,
    required this.users,
    required this.gated,
  });

  final Business business;
  final List<AppUser> owners;
  final List<AppUser> admins;
  final List<AppUser> users;
  final bool gated;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Remove the default divider lines ExpansionTile paints when expanded.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.md),
        leading: const Icon(Icons.business_outlined,
            size: 20, color: AppColors.textTertiary),
        title: Text(business.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(business.id,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textTertiary)),
        children: gated
            ? const [
                Padding(
                  padding: EdgeInsets.only(
                      left: AppSpacing.md, bottom: AppSpacing.sm),
                  child: Text(
                    'The team roster (admins & users) is visible to Owners '
                    'only.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                ),
              ]
            : [
                _RoleGroup(
                    label: 'Owner', icon: Icons.shield_outlined, people: owners),
                _RoleGroup(
                    label: 'Admins',
                    icon: Icons.admin_panel_settings_outlined,
                    people: admins),
                _RoleGroup(
                    label: 'Users',
                    icon: Icons.person_outline,
                    people: users),
              ],
      ),
    );
  }
}

/// A role sub-group (Owner / Admins / Users) listing its people, itself an
/// expandable node so the tree can be drilled into level by level.
class _RoleGroup extends StatelessWidget {
  const _RoleGroup({
    required this.label,
    required this.icon,
    required this.people,
  });

  final String label;
  final IconData icon;
  final List<AppUser> people;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.lg),
        dense: true,
        leading: Icon(icon, size: 18, color: AppColors.textTertiary),
        title: Text('$label (${people.length})',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        children: people.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.only(
                      left: AppSpacing.lg, bottom: AppSpacing.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('None',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textTertiary)),
                  ),
                ),
              ]
            : [for (final p in people) _PersonTile(person: p)],
      ),
    );
  }
}

/// A leaf node: one person's avatar, name and email.
class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final AppUser person;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          InitialsAvatar(name: person.name, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(person.name.isEmpty ? person.loginId : person.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                if (person.email.isNotEmpty)
                  Text(person.email,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          StatusBadge.role(person.role),
        ],
      ),
    );
  }
}

/// The customer-side Contacts section: the people on the customer's side (CEO,
/// Tech Lead, CSM, …) with add / edit / delete. Sits directly above the Orders
/// card. Each contact's display picture is auto-generated from their name via
/// [InitialsAvatar]. Mutations route through [CustomerContactsViewModel], which
/// persists the change as a customer-document save (reusing the customer's
/// permission gate and audit trail) and then refreshes the [DataController].
///
/// Add/edit/delete affordances are shown only when [canEdit]
/// ([Permission.editCustomer]); the underlying repository re-checks on save.
class _ContactsCard extends StatefulWidget {
  const _ContactsCard({required this.customer, required this.canEdit});

  final Customer customer;
  final bool canEdit;

  @override
  State<_ContactsCard> createState() => _ContactsCardState();
}

class _ContactsCardState extends State<_ContactsCard> {
  /// Live search query. Matched (case-insensitively) against name, designation,
  /// email and number. Debounced by [SearchField].
  String _query = '';

  Customer get _customer => widget.customer;
  bool get _canEdit => widget.canEdit;

  /// Contacts matching the current [_query]. Empty query returns all.
  List<Contact> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _customer.contacts;
    return _customer.contacts.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.designation.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q) ||
          c.number.toLowerCase().contains(q);
    }).toList();
  }

  /// Opens the add/edit form. Persistence happens inside [ContactFormDialog]
  /// (the canonical [FormDialog] pattern), so the dialog resolves to `true` on a
  /// successful save; we then refresh and confirm. [existing] null means add.
  Future<void> _openForm({Contact? existing}) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ContactFormDialog(
          customer: _customer, repo: repo, existing: existing),
    );
    if (saved == true) {
      await data.refresh();
      if (mounted) {
        showSuccessSnack(
            context, existing == null ? 'Contact added' : 'Contact updated');
      }
    }
  }

  Future<void> _delete(Contact contact) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final label = contact.name.trim().isEmpty ? 'this contact' : contact.name;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete contact?',
      message: 'Remove $label from this customer? '
          'This action cannot be easily undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await CustomerContactsViewModel(repo).remove(_customer, contact.id);
      await data.refresh();
      if (mounted) showSuccessSnack(context, 'Contact deleted');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// Opens the read-only view modal and routes any edit/delete action it emits.
  Future<void> _view(Contact contact) async {
    final action = await showDialog<_ContactAction>(
      context: context,
      builder: (_) => ContactViewDialog(contact: contact, canEdit: _canEdit),
    );
    if (!mounted) return;
    switch (action) {
      case _ContactAction.edit:
        await _openForm(existing: contact);
      case _ContactAction.delete:
        await _delete(contact);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _customer.contacts.length;
    final filtered = _filtered;
    return SectionCard(
      title: 'Contacts',
      subtitle: '$total ${total == 1 ? 'contact' : 'contacts'} '
          'on the customer side',
      trailing: _canEdit
          ? TextButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Add Contact'),
            )
          : null,
      child: total == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                _canEdit
                    ? 'No contacts yet. Add the people on the customer side '
                        '(e.g. CEO, Tech Lead, CSM).'
                    : 'No contacts recorded for this customer.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live searchbar — shown once there is more than one contact to
                // sift through.
                if (total > 1) ...[
                  SearchField(
                    hintText: 'Search name, designation, email or number…',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text('No contacts match “${_query.trim()}”.',
                        style:
                            const TextStyle(color: AppColors.textSecondary)),
                  )
                else
                  for (var i = 0; i < filtered.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      const Divider(height: 1),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    _ContactTile(
                      contact: filtered[i],
                      onTap: () => _view(filtered[i]),
                    ),
                  ],
              ],
            ),
    );
  }
}

/// The action a [ContactViewDialog] resolves to when dismissed.
enum _ContactAction { edit, delete }

/// One contact row in the list: an auto-generated initials avatar, the name and
/// designation only. Tapping opens the read-only [ContactViewDialog] where the
/// full details (with copy buttons) and edit/delete actions live.
class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onTap});

  final Contact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = contact.name.trim().isEmpty ? 'Unnamed contact' : contact.name;
    final designation = contact.designation.trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Row(
          children: [
            InitialsAvatar(name: name, size: 44),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  if (designation.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(designation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// A read-only modal showing every field of a [Contact], each with a copy
/// button (reusing [DetailFieldTile]), headed by the auto-generated avatar. When
/// [canEdit] is true it offers Edit / Delete in the footer; selecting one pops
/// the corresponding [_ContactAction] for the caller to handle (it does not
/// mutate anything itself, keeping persistence in one place).
class ContactViewDialog extends StatelessWidget {
  const ContactViewDialog({
    super.key,
    required this.contact,
    required this.canEdit,
  });

  final Contact contact;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final name = contact.name.trim().isEmpty ? 'Unnamed contact' : contact.name;
    final designation = contact.designation.trim();
    final fields = <DetailField>[
      DetailField('Name', contact.name, Icons.person_outline),
      DetailField('Designation', contact.designation, Icons.badge_outlined),
      DetailField('Email', contact.email, Icons.mail_outline),
      DetailField('Number', contact.number, Icons.phone_outlined),
      DetailField('Description', contact.description, Icons.notes_outlined),
    ];

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: avatar + name/designation + close.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
          child: Row(
            children: [
              InitialsAvatar(name: name, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    if (designation.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(designation,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Body: all fields, each with a copy button.
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.lg),
                  DetailFieldTile(field: fields[i]),
                ],
                if (contact.createdAt != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  DetailFieldTile(
                    field: DetailField('Added',
                        AppDate.format(contact.createdAt), Icons.schedule),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (canEdit) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_ContactAction.delete),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.error),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_ContactAction.edit),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: content,
      ),
    );
  }
}

/// Add/edit form for a customer-side [Contact]. Captures the five fields — Name
/// (required), Email (optional, validated), Designation, Number and Description.
///
/// Follows the canonical [FormDialog] contract used across the app (see
/// [CustomerFormDialog]): it persists the change itself in [_submit] via
/// [CustomerContactsViewModel] and returns `true`/`false`, letting [FormDialog]
/// perform the single dialog pop. It must NOT call [Navigator.pop] itself — doing
/// so plus returning `true` would pop twice and tear down the page beneath.
/// The caller refreshes the [DataController] and shows the success snackbar when
/// the dialog resolves to `true`.
class ContactFormDialog extends StatefulWidget {
  const ContactFormDialog({
    super.key,
    required this.customer,
    required this.repo,
    this.existing,
  });

  /// The customer the contact belongs to (the save target).
  final Customer customer;
  final Repository repo;

  /// The contact being edited, or null when adding a new one.
  final Contact? existing;

  @override
  State<ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<ContactFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _designation;
  late final TextEditingController _number;
  late final TextEditingController _description;

  Contact? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final c = _existing;
    _name = TextEditingController(text: c?.name ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _designation = TextEditingController(text: c?.designation ?? '');
    _number = TextEditingController(text: c?.number ?? '');
    _description = TextEditingController(text: c?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _designation.dispose();
    _number.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    return FormDialog(
      title: isNew ? 'Add Contact' : 'Edit Contact',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Name',
              controller: _name,
              isRequired: true,
              hintText: 'e.g. Jane Cooper',
              validator: (v) => Validators.required(v, field: 'Name'),
            ),
            const FormGap(),
            AppTextField(
              label: 'Designation',
              controller: _designation,
              hintText: 'e.g. CEO, Tech Lead, CSM',
            ),
            const FormGap(),
            FormRow([
              AppTextField(
                label: 'Email',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? null : Validators.email(v),
              ),
              AppTextField(
                label: 'Number',
                controller: _number,
                keyboardType: TextInputType.phone,
              ),
            ]),
            const FormGap(),
            AppTextField(
              label: 'Description',
              controller: _description,
              maxLines: 3,
              hintText: 'Role, responsibilities or notes',
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    final vm = CustomerContactsViewModel(widget.repo);
    try {
      final existing = _existing;
      if (existing == null) {
        // Add: buildDraft mints the id/createdAt and trims the fields.
        final draft = vm.buildDraft(
          name: _name.text,
          email: _email.text,
          designation: _designation.text,
          number: _number.text,
          description: _description.text,
        );
        await vm.add(widget.customer, draft);
      } else {
        // Edit: keep the id/createdAt, apply the (trimmed) field values.
        final updated = existing.copyWith(
          name: _name.text.trim(),
          email: _email.text.trim(),
          designation: _designation.text.trim(),
          number: _number.text.trim(),
          description: _description.text.trim(),
        );
        await vm.update(widget.customer, updated);
      }
      // Return true so FormDialog performs the single pop; do NOT pop here.
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}

/// Lists the orders placed by this customer, newest-first, with a row tap
/// through to each order's detail view.
///
/// A customer may be tagged to several businesses, so each row resolves its own
/// business currency rather than assuming one; a Business column is shown only
/// when the customer spans more than one business. The [orders] passed in are
/// already access-scoped (see [DataController.ordersForCustomer]).
class _OrdersCard extends StatefulWidget {
  const _OrdersCard({required this.orders, required this.businesses});

  final List<Order> orders;
  final List<Business> businesses;

  @override
  State<_OrdersCard> createState() => _OrdersCardState();
}

class _OrdersCardState extends State<_OrdersCard> {
  /// Live search query. Matched (case-insensitively) against order id, product,
  /// status label and formatted date via [AppDataTable]'s [searchableText].
  /// Debounced by [SearchField].
  String _orderSearch = '';

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Order o) =>
      o.orderDate ?? o.audit.createdAt ?? _epoch;

  CurrencyCode _currencyOf(Order o) {
    for (final b in widget.businesses) {
      if (b.id == o.businessId) return b.currency;
    }
    return CurrencyCode.inr;
  }

  String _businessName(String id) {
    for (final b in widget.businesses) {
      if (b.id == id) return b.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.orders;
    final businesses = widget.businesses;
    final multiBusiness = businesses.length > 1;
    final sorted = [...orders]
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    return SectionCard(
      title: 'Orders',
      subtitle: '${orders.length} '
          '${orders.length == 1 ? 'order' : 'orders'} placed',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live searchbar — shown once there is more than one order to sift
          // through.
          if (orders.length > 1) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
              child: SearchField(
                hintText: 'Search orders by ID, product or status…',
                onChanged: (v) => setState(() => _orderSearch = v),
              ),
            ),
          ],
          AppDataTable<Order>(
            rows: sorted,
            rowsPerPage: 10,
            searchText: _orderSearch,
            onRowTap: (o) => context.go(Routes.orderDetailPath(o.id)),
            searchableText: (o) => '${o.id} ${o.productName} '
                '${o.status.label} ${AppDate.short(_dateOf(o))} '
                '${multiBusiness ? _businessName(o.businessId) : ''}',
            emptyTitle: 'No orders',
            emptyMessage: 'Orders placed by this customer will appear here.',
            columns: [
          AppColumn(
            label: 'Order ID',
            cell: (o) => Text(o.id,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            sortValue: (o) => o.id,
          ),
          AppColumn(
            label: 'Product',
            cell: (o) => Text(
              o.productName.isEmpty ? '—' : o.productName,
              overflow: TextOverflow.ellipsis,
            ),
            sortValue: (o) => o.productName.toLowerCase(),
          ),
          if (multiBusiness)
            AppColumn(
              label: 'Business',
              cell: (o) => Text(_businessName(o.businessId),
                  overflow: TextOverflow.ellipsis),
              sortValue: (o) => _businessName(o.businessId).toLowerCase(),
            ),
          AppColumn(
            label: 'Date',
            cell: (o) => Text(AppDate.short(_dateOf(o))),
            sortValue: (o) => _dateOf(o).millisecondsSinceEpoch,
          ),
          AppColumn(
            label: 'Qty',
            numeric: true,
            cell: (o) => Text('${o.quantity}'),
            sortValue: (o) => o.quantity,
          ),
          AppColumn(
            label: 'Revenue',
            numeric: true,
            cell: (o) =>
                CurrencyText(o.recognisedRevenue, currency: _currencyOf(o)),
            sortValue: (o) => o.recognisedRevenue.minor,
          ),
          AppColumn(
            label: 'Profit',
            numeric: true,
            cell: (o) => CurrencyText(o.recognisedGrossProfit,
                currency: _currencyOf(o)),
            sortValue: (o) => o.recognisedGrossProfit.minor,
          ),
          AppColumn(
            label: 'Status',
            cell: (o) => StatusBadge.order(o.status),
            sortValue: (o) => o.status.label,
          ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Right column: deal status, last activity and the comment thread.
class _ActivityColumn extends StatelessWidget {
  const _ActivityColumn({required this.customer, required this.canComment});

  final Customer customer;
  final bool canComment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Last Activity',
          child: Row(
            children: [
              const Icon(Icons.schedule,
                  size: 18, color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppDate.format(customer.lastActivityAt),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _CommentThread(customer: customer, canComment: canComment),
      ],
    );
  }
}

/// The comment thread: a list of past comments plus (when permitted) an input
/// to append a new one, attributed to the current user.
class _CommentThread extends StatefulWidget {
  const _CommentThread({required this.customer, required this.canComment});

  final Customer customer;
  final bool canComment;

  @override
  State<_CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends State<_CommentThread> {
  final _controller = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _posting) return;
    final appState = context.read<AppState>();
    final data = context.read<DataController>();
    final user = appState.currentUser;
    if (user == null) return;

    setState(() => _posting = true);
    final comment = CustomerComment(
      id: 'c${DateTime.now().microsecondsSinceEpoch}',
      authorId: user.uid,
      authorName: user.name,
      text: text,
      createdAt: DateTime.now(),
    );
    try {
      await appState.repository.saveCustomer(
        widget.customer
            .copyWith(comments: [...widget.customer.comments, comment]),
        isNew: false,
      );
      _controller.clear();
      await data.refresh();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = [...widget.customer.comments]..sort((a, b) {
        final da = a.createdAt;
        final db = b.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    return SectionCard(
      title: 'Comment Thread',
      subtitle: '${comments.length} '
          '${comments.length == 1 ? 'comment' : 'comments'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.canComment) ...[
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Add a comment…',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _posting ? null : _post,
                icon: _posting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 16),
                label: const Text('Post'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No comments yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (var i = 0; i < comments.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              _CommentTile(comment: comments[i]),
            ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final CustomerComment comment;

  @override
  Widget build(BuildContext context) {
    final author =
        comment.authorName.isEmpty ? 'Unknown' : comment.authorName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InitialsAvatar(name: author, size: 32),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(author,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  if (comment.createdAt != null)
                    Text(
                      AppDate.short(comment.createdAt!),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(comment.text,
                  style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
