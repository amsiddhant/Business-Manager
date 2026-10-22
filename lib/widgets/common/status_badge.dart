import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/theme_x.dart';

/// Semantic colour intent for a badge.
enum BadgeTone { neutral, success, warning, error, info, primary }

/// A soft pill with a coloured dot showing a status label.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.tone = BadgeTone.neutral});

  final String label;
  final BadgeTone tone;

  factory StatusBadge.entity(EntityStatus status) {
    switch (status) {
      case EntityStatus.active:
        return StatusBadge(label: status.label, tone: BadgeTone.success);
      case EntityStatus.inactive:
        return StatusBadge(label: status.label, tone: BadgeTone.neutral);
      case EntityStatus.archived:
        return StatusBadge(label: status.label, tone: BadgeTone.warning);
    }
  }

  factory StatusBadge.account(AccountStatus status) => StatusBadge(
        label: status.label,
        tone: status == AccountStatus.active
            ? BadgeTone.success
            : BadgeTone.error,
      );

  factory StatusBadge.order(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return StatusBadge(label: status.label, tone: BadgeTone.success);
      case OrderStatus.shipped:
      case OrderStatus.confirmed:
      case OrderStatus.processing:
        return StatusBadge(label: status.label, tone: BadgeTone.info);
      case OrderStatus.pending:
        return StatusBadge(label: status.label, tone: BadgeTone.warning);
      case OrderStatus.cancelled:
      case OrderStatus.returned:
        return StatusBadge(label: status.label, tone: BadgeTone.error);
    }
  }

  factory StatusBadge.campaign(CampaignStatus status) {
    switch (status) {
      case CampaignStatus.active:
        return StatusBadge(label: status.label, tone: BadgeTone.success);
      case CampaignStatus.completed:
        return StatusBadge(label: status.label, tone: BadgeTone.info);
      case CampaignStatus.paused:
        return StatusBadge(label: status.label, tone: BadgeTone.warning);
      case CampaignStatus.draft:
        return StatusBadge(label: status.label, tone: BadgeTone.neutral);
      case CampaignStatus.cancelled:
        return StatusBadge(label: status.label, tone: BadgeTone.error);
    }
  }

  factory StatusBadge.deal(DealStatus status) {
    switch (status) {
      case DealStatus.successful:
        return StatusBadge(label: status.label, tone: BadgeTone.success);
      case DealStatus.inProgress:
        return StatusBadge(label: status.label, tone: BadgeTone.info);
      case DealStatus.pending:
        return StatusBadge(label: status.label, tone: BadgeTone.warning);
      case DealStatus.cancelled:
        return StatusBadge(label: status.label, tone: BadgeTone.error);
    }
  }

  factory StatusBadge.role(UserRole role) => StatusBadge(
        label: role.label,
        tone: switch (role) {
          UserRole.owner => BadgeTone.primary,
          UserRole.admin => BadgeTone.info,
          UserRole.user => BadgeTone.neutral,
        },
      );

  ({Color fg, Color bg}) _colors(AppTokens t) {
    switch (tone) {
      case BadgeTone.success:
        return (fg: t.success, bg: t.successSurface);
      case BadgeTone.warning:
        return (fg: t.warning, bg: t.warningSurface);
      case BadgeTone.error:
        return (fg: t.error, bg: t.errorSurface);
      case BadgeTone.info:
        return (fg: t.info, bg: t.infoSurface);
      case BadgeTone.primary:
        return (fg: t.primary, bg: t.primaryLight);
      case BadgeTone.neutral:
        return (fg: t.textSecondary, bg: t.surfaceAlt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors(context.tokens);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
      decoration: ShapeDecoration(
        color: c.bg,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
