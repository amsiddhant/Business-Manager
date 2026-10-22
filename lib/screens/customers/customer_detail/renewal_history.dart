import 'package:flutter/material.dart';

import '../../../core/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../models/customer.dart';

/// A collapsible timeline of superseded contract terms (the renewal log),
/// newest-first. The active term is shown above in the main card; this lists
/// each prior term with its plan, window and recurring total.
class RenewalHistory extends StatelessWidget {
  const RenewalHistory({
    super.key,
    required this.history,
    required this.currency,
  });

  final List<ServiceContract> history;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          leading: Icon(Icons.history, size: 20, color: t.textTertiary),
          title: Text('Renewal History (${history.length})',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text('Previous terms, most recent first',
              style: TextStyle(fontSize: 11.5, color: t.textTertiary)),
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
    final t = context.tokens;
    final window = '${AppDate.format(contract.purchaseDate)} → '
        '${AppDate.format(contract.expiryDate)}';
    return Container(
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: t.primaryLight,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text('Term $ordinal',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.primary)),
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
                '${MoneyFormatter.format(contract.total, currency)} '
                '/${contract.billingCycle.unit}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.primary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.date_range_outlined, size: 13, color: t.textTertiary),
              const SizedBox(width: 4),
              Text(window,
                  style: TextStyle(fontSize: 12, color: t.textSecondary)),
            ],
          ),
          if (contract.hasOneTimeCharge) ...[
            const SizedBox(height: 2),
            Text(
              '+ ${MoneyFormatter.format(contract.oneTimeTotal, currency)} one-time',
              style: TextStyle(fontSize: 12, color: t.textTertiary),
            ),
          ],
          if (contract.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(contract.comment,
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: t.textSecondary)),
          ],
        ],
      ),
    );
  }
}
