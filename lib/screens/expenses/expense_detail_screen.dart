import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/expense.dart';
import '../../services/profit_calculation_service.dart';
import '../../services/summaries/expense_summaries.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/comment_thread.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/detail_page.dart';
import '../../widgets/layout/kpi_strip.dart';
import 'expenses_screen.dart';

/// A single expense view: amount/frequency breakdown with annualised and
/// prorated figures, the owning business, a banner linking to the source
/// dealer (for mirrored dealer expenses), and a comment thread. Linked
/// entities resolve through the access-scoped [DataController].
class ExpenseDetailScreen extends StatelessWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});

  final String expenseId;

  static const _service = ProfitCalculationService();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    void back() => context.go(Routes.expenses);

    if (data.loading && !data.loaded) {
      return DetailPage.loading(
          title: 'Expense', onBack: back, backLabel: 'Expenses');
    }

    final expense = data.expenseById(expenseId);
    if (expense == null) {
      return DetailPage.notFound(
        title: 'Expense',
        onBack: back,
        backLabel: 'Expenses',
        message: 'This expense may have been removed or is not accessible.',
      );
    }

    final t = context.tokens;
    final business = data.businessById(expense.businessId);
    final dealer = expense.sourceDealerId == null
        ? null
        : data.dealerById(expense.sourceDealerId!);
    final currency = business?.currency ?? CurrencyCode.inr;
    String money(Money m) => MoneyFormatter.format(m, currency);
    // Dealer-mirrored expenses are managed via their dealer, not edited here.
    final canEditExpense = user?.can(Permission.editExpense) ?? false;
    final canEdit = canEditExpense && !expense.isFromDealer;
    final canCreate =
        (user?.can(Permission.createExpense) ?? false) && !expense.isFromDealer;
    final canDelete =
        (user?.can(Permission.deleteExpense) ?? false) && !expense.isFromDealer;
    final canViewDealer = user?.can(Permission.viewDealer) ?? false;
    final prorated = _service.prorationOf(expense);
    final repo = appState.repository;
    void openDealer() =>
        context.go(Routes.dealerDetailPath(expense.sourceDealerId!));

    return DetailPage(
      title: expense.name,
      subtitle: '${expense.id} · ${expense.category.label}',
      icon: Icons.account_balance_wallet_outlined,
      status: StatusBadge.entity(expense.status),
      backLabel: 'Expenses',
      onBack: back,
      meta: [
        if (business != null) DetailMeta(Icons.business_outlined, business.name),
        DetailMeta(Icons.category_outlined, expense.category.label,
            tooltip: 'Category'),
        if (expense.vendor.isNotEmpty)
          DetailMeta(Icons.store_outlined, expense.vendor, tooltip: 'Vendor'),
        if (expense.isFromDealer)
          DetailMeta(
            Icons.handshake_outlined,
            dealer == null ? 'Managed by dealer' : 'Managed by ${dealer.name}',
            tooltip: canViewDealer && dealer != null ? 'Open dealer' : null,
            onTap: canViewDealer && dealer != null ? openDealer : null,
          ),
      ],
      primaryAction: canEdit
          ? FilledButton.icon(
              onPressed: () => ExpensesScreen.openForm(
                  context, expense, expense.businessId),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            )
          : null,
      menu: [
        if (canCreate)
          DetailAction(
            label: 'Duplicate',
            icon: Icons.copy_all_outlined,
            onSelected: () => ExpenseActions.duplicate(context, expense),
          ),
        if (canEdit && expense.status != EntityStatus.inactive)
          DetailAction(
            label: 'Mark inactive',
            icon: Icons.pause_circle_outline,
            onSelected: () =>
                ExpenseActions.setStatus(context, expense, EntityStatus.inactive),
          ),
        if (canEdit && expense.status != EntityStatus.active)
          DetailAction(
            label: 'Mark active',
            icon: Icons.play_circle_outline,
            onSelected: () =>
                ExpenseActions.setStatus(context, expense, EntityStatus.active),
          ),
        if (canDelete)
          DetailAction(
            label: 'Delete expense',
            icon: Icons.delete_outline,
            destructive: true,
            onSelected: () async {
              if (await ExpenseActions.delete(context, expense) &&
                  context.mounted) {
                back();
              }
            },
          ),
      ],
      banner: expense.isFromDealer
          ? _DealerBanner(
              dealerName: dealer?.name,
              onOpen: canViewDealer && dealer != null ? openDealer : null,
            )
          : null,
      kpis: [
        KpiItem(
          label: 'Amount',
          value: money(expense.amount),
          icon: Icons.payments_outlined,
          caption: expense.frequency.isRecurring
              ? 'per ${_unit(expense.frequency)}'
              : 'one-time',
        ),
        KpiItem(
          label: 'Frequency',
          value: expense.frequency.label,
          icon: Icons.repeat,
        ),
        KpiItem(
          label: 'Annualised',
          value: money(expense.annualisedAmount),
          icon: Icons.event_repeat_outlined,
          tooltip: 'Amount × occurrences per year (one-time counts once).',
        ),
        KpiItem(
          label: 'This month',
          value: money(prorated.thisMonth),
          icon: Icons.timelapse_outlined,
          caption: 'Prorated',
          tooltip: 'The part of this expense falling in the current month, '
              'clipped to its start and end dates.',
        ),
        KpiItem(
          label: prorated.financialYear.label,
          value: money(prorated.thisFinancialYear),
          icon: Icons.calendar_today_outlined,
          caption: 'Prorated',
          tooltip: 'The part of this expense falling in the current '
              'financial year.',
        ),
      ],
      activity: DetailActivityColumn(
        activityAt: expense.lastActivityAt,
        comments: expense.comments,
        // A viewer who can comment is one who can edit the expense; read-only
        // viewers still see history.
        canComment: canEditExpense,
        onPost: (comment) async {
          await repo.saveExpense(
            expense.copyWith(comments: [...expense.comments, comment]),
            isNew: false,
          );
        },
      ),
      children: [
        _DetailsCard(
          expense: expense,
          businessName: business?.name,
          dealerName: dealer?.name,
          dealerId: canViewDealer ? dealer?.id : null,
          tone: t.primary,
        ),
      ],
    );
  }

  static String _unit(RecurrenceFrequency f) => switch (f) {
        RecurrenceFrequency.monthly => 'month',
        RecurrenceFrequency.quarterly => 'quarter',
        RecurrenceFrequency.halfYearly => 'half-year',
        RecurrenceFrequency.yearly => 'year',
        RecurrenceFrequency.oneTime => 'time',
      };
}

/// Tells the viewer a dealer-mirrored expense is read-only and links to the
/// dealer that manages it.
class _DealerBanner extends StatelessWidget {
  const _DealerBanner({required this.dealerName, required this.onOpen});

  final String? dealerName;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.infoSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: t.border),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 18, color: t.info),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              dealerName == null
                  ? 'Read-only: this expense is generated from a dealer and '
                      'is managed there.'
                  : 'Read-only: this expense is generated from the dealer '
                      '"$dealerName". Change its cost on the dealer and it '
                      'updates here.',
              style: TextStyle(fontSize: 13, color: t.textSecondary),
            ),
          ),
          if (onOpen != null)
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('View dealer'),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.primary,
                side: BorderSide(color: t.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.expense,
    required this.businessName,
    required this.dealerName,
    required this.dealerId,
    required this.tone,
  });

  final Expense expense;
  final String? businessName;
  final String? dealerName;
  final String? dealerId;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fields = <DetailField>[
      DetailField('Expense ID', expense.id, Icons.badge_outlined),
      DetailField('Category', expense.category.label, Icons.category_outlined),
      DetailField('Business', businessName ?? '—', Icons.business_outlined),
      DetailField('Vendor', expense.vendor, Icons.store_outlined),
      DetailField(
          'Start Date',
          expense.startDate == null ? '—' : AppDate.format(expense.startDate),
          Icons.event_outlined),
      DetailField(
          'End Date',
          expense.endDate == null ? '—' : AppDate.format(expense.endDate),
          Icons.event_available_outlined),
    ];

    Widget note(String title, String body) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: t.surfaceAlt,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.textSecondary)),
              const SizedBox(height: 4),
              Text(body, style: const TextStyle(fontSize: 14, height: 1.4)),
            ],
          ),
        );

    return SectionCard(
      title: 'Expense details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailGrid(fields: fields),
          if (dealerId != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: OutlinedButton.icon(
                onPressed: () => context.go(Routes.dealerDetailPath(dealerId!)),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(dealerName == null
                    ? 'View dealer'
                    : 'View dealer · $dealerName'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tone,
                  side: BorderSide(color: tone),
                ),
              ),
            ),
          if (expense.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            note('Description', expense.description),
          ],
          if (expense.notes.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            note('Notes', expense.notes),
          ],
        ],
      ),
    );
  }
}
