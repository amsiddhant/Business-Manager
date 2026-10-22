import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/money.dart';
import 'chart_kit.dart';

/// Where the period's orders stand: one bar split by status, then each
/// status with its count and share.
class OrderStatusChart extends StatelessWidget {
  const OrderStatusChart({super.key, required this.breakdown});

  final Map<OrderStatus, int> breakdown;

  /// A colour per status, matching the status badges' tones.
  static Color colorOf(AppTokens t, OrderStatus s) => switch (s) {
        OrderStatus.delivered => t.success,
        OrderStatus.shipped => t.info,
        OrderStatus.confirmed => t.chartSeries[5],
        OrderStatus.processing => t.chartSeries[7],
        OrderStatus.pending => t.warning,
        OrderStatus.returned => t.chartSeries[6],
        OrderStatus.cancelled => t.error,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final statuses = [
      for (final s in OrderStatus.values)
        if ((breakdown[s] ?? 0) > 0) s,
    ];
    final total = statuses.fold(0, (sum, s) => sum + breakdown[s]!);
    String share(OrderStatus s) => PercentFormatter.format(
        total == 0 ? 0 : breakdown[s]! / total * 100,
        decimals: 0);

    return ChartReveal(
      id: 'order-status',
      builder: (context, k) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$total',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('orders in the period',
                    style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 18,
              child: Row(
                children: [
                  for (final s in statuses)
                    Expanded(
                      flex: (breakdown[s]! * 1000 * k).round().clamp(1, 1 << 30),
                      child: Tooltip(
                        message: '${s.label}: ${breakdown[s]} (${share(s)})',
                        child: Container(
                          margin: const EdgeInsets.only(right: 2),
                          color: colorOf(t, s),
                        ),
                      ),
                    ),
                  if (k < 1)
                    Expanded(
                      flex: (total * 1000 * (1 - k)).round().clamp(1, 1 << 30),
                      child: const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final columns = c.maxWidth >= 360 ? 2 : 1;
              final width =
                  (c.maxWidth - AppSpacing.md * (columns - 1)) / columns;
              return SingleChildScrollView(
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final s in statuses)
                      SizedBox(
                        width: width,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: t.surfaceAlt,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: colorOf(t, s),
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(s.label,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: t.textSecondary)),
                              ),
                              Text('${breakdown[s]}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: t.textPrimary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  )),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 36,
                                child: Text(share(s),
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: t.textTertiary)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
