import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../models/business.dart';
import '../../../models/customer.dart';
import '../../../state/app_state.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/status_badge.dart';
import '../../../widgets/forms/app_form.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../service_contract_form.dart';
import 'renewal_history.dart';

/// The "Service Contract" card for one business, shown once a deal is won.
/// Presents the plan, billing cadence, dates and add-on line items with a
/// running total, offers Renew / Edit to permitted viewers, and carries the
/// business's renewal history.
class ServiceContractCard extends StatelessWidget {
  const ServiceContractCard({
    super.key,
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
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => ServiceContractFormDialog(
        customer: customer,
        repo: repo,
        business: business,
        isRenewal: isRenewal,
      ),
    );
    if (saved == true) {
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
    final t = context.tokens;
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
                  style: TextButton.styleFrom(foregroundColor: t.textSecondary),
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
                icon: expired ? Icons.error_outline : Icons.verified_outlined,
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
          // Dates + time remaining, as tinted tiles.
          LayoutBuilder(builder: (context, c) {
            final tiles = [
              _ContractStat(
                icon: Icons.event_available_outlined,
                label: 'Purchased',
                value: AppDate.format(contract.purchaseDate),
              ),
              _ContractStat(
                icon: Icons.event_busy_outlined,
                label: 'Expires',
                value: AppDate.format(contract.expiryDate),
                valueColor: expired ? t.error : null,
              ),
              if (remaining != null)
                _ContractStat(
                  icon: remaining.isPast
                      ? Icons.warning_amber_rounded
                      : Icons.hourglass_bottom,
                  label: remaining.isPast ? 'Overdue by' : 'Time remaining',
                  value: remaining.isToday
                      ? 'Expires today'
                      : remaining.shortLabel +
                          (remaining.isPast ? ' overdue' : ' remaining'),
                  valueColor: remaining.isPast ? t.error : t.primary,
                ),
            ];
            final narrow = c.maxWidth < 520;
            return narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.sm),
                        tiles[i],
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.sm),
                        Expanded(child: tiles[i]),
                      ],
                    ],
                  );
          }),
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
            value: '${MoneyFormatter.format(contract.total, currency)} '
                '/${contract.billingCycle.unit}',
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
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notes_outlined,
                          size: 15, color: t.textTertiary),
                      const SizedBox(width: 6),
                      Text('Comment',
                          style:
                              TextStyle(fontSize: 12, color: t.textSecondary)),
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
            RenewalHistory(history: history, currency: currency),
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

  ({Color fg, Color bg}) _colors(AppTokens t) {
    switch (tone) {
      case BadgeTone.success:
        return (fg: t.success, bg: t.successSurface);
      case BadgeTone.error:
        return (fg: t.error, bg: t.errorSurface);
      case BadgeTone.info:
        return (fg: t.info, bg: t.infoSurface);
      case BadgeTone.primary:
        return (fg: t.primary, bg: t.primaryLight);
      case BadgeTone.warning:
        return (fg: t.warning, bg: t.warningSurface);
      case BadgeTone.neutral:
        return (fg: t.textSecondary, bg: t.surfaceAlt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors(context.tokens);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(999),
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
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: t.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: t.textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: valueColor)),
              ],
            ),
          ),
        ],
      ),
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
    final t = context.tokens;
    final valueColor =
        isTotal ? t.primary : (muted ? t.textTertiary : t.textPrimary);
    return Row(
      children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: 16, color: t.textTertiary),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14.5 : 13.5,
              color: isTotal ? t.textPrimary : t.textSecondary,
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
