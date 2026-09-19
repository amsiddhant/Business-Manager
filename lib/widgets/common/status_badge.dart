import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Semantic colour intent for a badge.
enum BadgeTone { neutral, success, warning, error, info, primary }

/// A small pill showing a status label with an appropriate colour.
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

  factory StatusBadge.role(UserRole role) => StatusBadge(
        label: role.label,
        tone: switch (role) {
          UserRole.owner => BadgeTone.primary,
          UserRole.admin => BadgeTone.info,
          UserRole.user => BadgeTone.neutral,
        },
      );

  ({Color fg, Color bg}) get _colors {
    switch (tone) {
      case BadgeTone.success:
        return (fg: AppColors.success, bg: AppColors.successSurface);
      case BadgeTone.warning:
        return (fg: AppColors.warning, bg: AppColors.warningSurface);
      case BadgeTone.error:
        return (fg: AppColors.error, bg: AppColors.errorSurface);
      case BadgeTone.info:
        return (fg: AppColors.info, bg: AppColors.infoSurface);
      case BadgeTone.primary:
        return (fg: AppColors.primary, bg: AppColors.primaryLight);
      case BadgeTone.neutral:
        return (fg: AppColors.textSecondary, bg: AppColors.surfaceAlt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c.fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
