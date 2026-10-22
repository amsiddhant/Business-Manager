import 'package:flutter/material.dart';

import '../../../core/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../models/customer.dart';

/// The prominent total-subscription figure shown above the sections once a
/// contract is in scope. A gradient band mirroring the contract form's total.
class SubscriptionBand extends StatelessWidget {
  const SubscriptionBand({
    super.key,
    required this.contract,
    required this.currency,
  });

  final ServiceContract contract;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final remaining = contract.timeRemainingAsOf(DateTime.now());
    final soft = t.textOnPrimary.withValues(alpha: 0.7);
    final softer = t.textOnPrimary.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [t.primary, t.primaryDark]),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        boxShadow: t.cardShadow,
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
                    Icon(Icons.workspace_premium_outlined,
                        color: soft, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${contract.plan.label} · Total Subscription',
                        style: TextStyle(
                            color: soft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${MoneyFormatter.format(contract.total, currency)} '
                  '/${contract.billingCycle.unit}',
                  style: TextStyle(
                      color: t.textOnPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.1),
                ),
                if (contract.billingCycle == BillingCycle.monthly) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${MoneyFormatter.format(contract.annualTotal, currency)} / year',
                    style: TextStyle(color: softer, fontSize: 12),
                  ),
                ],
                if (contract.hasOneTimeCharge) ...[
                  const SizedBox(height: 2),
                  Text(
                    '+ ${MoneyFormatter.format(contract.oneTimeTotal, currency)} one-time',
                    style: TextStyle(color: softer, fontSize: 12),
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

/// A compact "time remaining" chip rendered on the subscription band. Shows
/// the largest units (e.g. "1 yr 2 mo") with a "remaining"/"overdue" caption,
/// and turns red once the term has lapsed.
class _RemainingPill extends StatelessWidget {
  const _RemainingPill({required this.remaining});

  final TimeRemaining remaining;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final expired = remaining.isPast;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: expired
            ? t.error.withValues(alpha: 0.9)
            : t.textOnPrimary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            remaining.isToday ? 'Today' : remaining.shortLabel,
            style: TextStyle(
                color: t.textOnPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.1),
          ),
          const SizedBox(height: 1),
          Text(
            remaining.isToday ? 'expires' : (expired ? 'overdue' : 'remaining'),
            style: TextStyle(
                color: t.textOnPrimary.withValues(alpha: 0.7), fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}
