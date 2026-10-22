import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../models/business.dart';
import '../../../models/customer.dart';
import '../../../state/app_state.dart';
import '../../../widgets/forms/app_form.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../service_contract_form.dart';

/// Prompts the user to choose which of the customer's [businesses] a contract
/// should be captured under, for the ambiguous "All Businesses" case where the
/// customer spans several. Returns the chosen business, or null if dismissed.
Future<Business?> pickContractBusiness(
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
                  Icon(Icons.storefront_outlined,
                      size: 20, color: context.tokens.textSecondary),
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

/// The colour-coded deal-status changer shown in the page header.
///
/// Renders the current status as a coloured pill with a dropdown caret. Picking
/// a new status persists it immediately; picking "Successful" first opens the
/// [ServiceContractFormDialog] and only commits the status if a contract is
/// saved. Disabled (non-interactive pill) when the viewer lacks edit rights.
class DealStatusChanger extends StatefulWidget {
  const DealStatusChanger({
    super.key,
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
  State<DealStatusChanger> createState() => _DealStatusChangerState();
}

class _DealStatusChangerState extends State<DealStatusChanger> {
  bool _busy = false;

  ({Color fg, Color bg}) _colorsFor(DealStatus status) {
    final t = context.tokens;
    switch (status) {
      case DealStatus.successful:
        return (fg: t.success, bg: t.successSurface);
      case DealStatus.inProgress:
        return (fg: t.info, bg: t.infoSurface);
      case DealStatus.pending:
        return (fg: t.warning, bg: t.warningSurface);
      case DealStatus.cancelled:
        return (fg: t.error, bg: t.errorSurface);
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
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => ServiceContractFormDialog(
        customer: widget.customer,
        repo: repo,
        business: business,
      ),
    );
    if (saved == true) {
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
    return pickContractBusiness(context, widget.businesses);
  }

  Future<void> _persistStatus(DealStatus status) async {
    final repo = context.read<AppState>().repository;
    setState(() => _busy = true);
    try {
      await repo.saveCustomer(
        widget.customer.copyWith(dealStatus: status),
        isNew: false,
      );
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
      padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(999),
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
          Icon(Icons.check, size: 16, color: context.tokens.primary),
      ],
    );
  }
}
