import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/expense.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/comment_thread.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import 'expenses_screen.dart';

/// A single expense view: amount/frequency breakdown, the owning business, an
/// optional link to the source dealer (for mirrored dealer expenses), and a
/// comment thread. Linked entities resolve through the access-scoped
/// [DataController].
class ExpenseDetailScreen extends StatelessWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});

  final String expenseId;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Expense'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
    }

    final expense = data.expenseById(expenseId);
    if (expense == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Expense',
            actions: [
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.expenses),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Expenses'),
              ),
            ],
          ),
          const SizedBox(height: 48),
          const EmptyView(
            icon: Icons.search_off,
            title: 'Expense not found',
            message:
                'This expense may have been removed or is not accessible.',
          ),
        ],
      );
    }

    final business = data.businessById(expense.businessId);
    final dealer = expense.sourceDealerId == null
        ? null
        : data.dealerById(expense.sourceDealerId!);
    final currency = business?.currency ?? CurrencyCode.inr;
    // Dealer-mirrored expenses are managed via their dealer, not edited here.
    final canEditExpense = user?.can(Permission.editExpense) ?? false;
    final canEdit = canEditExpense && !expense.isFromDealer;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(
          expense: expense,
          currency: currency,
          businessName: business?.name,
          dealerName: dealer?.name,
          dealerId: dealer?.id,
        ),
      ],
    );

    final repo = appState.repository;
    // A viewer who can comment is one who can edit the expense; read-only
    // viewers still see history.
    final canComment = canEditExpense;
    final right = DetailActivityColumn(
      activityAt: expense.lastActivityAt,
      comments: expense.comments,
      canComment: canComment,
      onPost: (comment) async {
        await repo.saveExpense(
          expense.copyWith(comments: [...expense.comments, comment]),
          isNew: false,
        );
        await data.refresh();
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: expense.name,
          subtitle: '${expense.id} · ${expense.category.label}',
          actions: [
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.expenses),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
            if (canEdit)
              ElevatedButton.icon(
                onPressed: () => ExpensesScreen.openForm(
                    context, expense, expense.businessId),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        DetailTwoColumn(left: left, right: right),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.expense,
    required this.currency,
    required this.businessName,
    required this.dealerName,
    required this.dealerId,
  });

  final Expense expense;
  final CurrencyCode currency;
  final String? businessName;
  final String? dealerName;
  final String? dealerId;

  @override
  Widget build(BuildContext context) {
    final metrics = <_Metric>[
      _Metric('Amount', MoneyFormatter.format(expense.amount, currency)),
      _Metric('Frequency', expense.frequency.label),
      _Metric('Annualised',
          MoneyFormatter.format(expense.annualisedAmount, currency)),
    ];

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

    return SectionCard(
      title: 'Expense Summary',
      trailing: StatusBadge.entity(expense.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (expense.isFromDealer)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(
                      child: Text(
                        'This expense is generated from a dealer and is '
                        'managed via that dealer.',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              const columns = 3;
              const gap = AppSpacing.md;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final m in metrics)
                    SizedBox(width: tileWidth, child: _MetricTile(metric: m)),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          DetailGrid(fields: fields),
          if (dealerId != null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.go(Routes.dealerDetailPath(dealerId!)),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View dealer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
          if (expense.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Text('Description',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(expense.description,
                style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
          if (expense.notes.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('Notes',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(expense.notes,
                style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(metric.label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(metric.value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
