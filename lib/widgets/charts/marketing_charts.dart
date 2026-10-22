import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/money.dart';
import '../../services/profit_calculation_service.dart';
import 'share_bars.dart';

/// Advertising spend by platform, largest first, with each one's share.
class PlatformMixChart extends StatelessWidget {
  const PlatformMixChart({
    super.key,
    required this.mix,
    required this.currency,
  });

  final Map<CampaignPlatform, Money> mix;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final e in mix.entries)
        if (e.value.isPositive) e,
    ]..sort((a, b) => b.value.minor.compareTo(a.value.minor));
    final total = entries.fold(Money.zero, (s, e) => s + e.value);
    return ShareBars(
      id: 'platform-mix',
      rows: [
        for (final e in entries)
          ShareBar(
            label: e.key.label,
            value: e.value.major,
            display: MoneyFormatter.compact(e.value, currency),
            caption: total.isZero
                ? null
                : '${PercentFormatter.format(e.value.major / total.major * 100, decimals: 0)} of spend',
          ),
      ],
    );
  }
}

/// Return on ad spend for the campaigns that spent the most, against the 1×
/// break-even line: green earns back more than it costs, red doesn't.
class RoasChart extends StatelessWidget {
  const RoasChart({
    super.key,
    required this.rows,
    required this.currency,
    this.limit = 8,
    this.onTap,
  });

  final List<CampaignPerformance> rows;
  final CurrencyCode currency;
  final int limit;
  final ValueChanged<CampaignPerformance>? onTap;

  /// The campaigns the chart shows: spent something, biggest spend first.
  static List<CampaignPerformance> pick(List<CampaignPerformance> rows,
          {int limit = 8}) =>
      ([
        for (final r in rows)
          if (r.spend.isPositive && r.roas != null) r,
      ]..sort((a, b) => b.spend.minor.compareTo(a.spend.minor)))
          .take(limit)
          .toList();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = pick(rows, limit: limit);
    return ShareBars(
      id: 'roas',
      reference: 1,
      referenceLabel: '1×',
      onTap: onTap == null ? null : (i) => onTap!(shown[i]),
      rows: [
        for (final r in shown)
          ShareBar(
            label: r.campaign.name,
            value: r.roas!,
            display: PercentFormatter.roas(r.roas),
            caption: '${r.campaign.platform.label} · '
                '${MoneyFormatter.compact(r.spend, currency)} spend',
            color: r.roas! >= 1 ? t.success : t.error,
          ),
      ],
    );
  }
}
