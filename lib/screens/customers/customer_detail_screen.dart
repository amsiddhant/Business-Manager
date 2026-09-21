import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../models/customer.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/initials_avatar.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/responsive.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import 'customers_screen.dart';

/// A full-screen customer profile: contact & company details on the left, and a
/// deal-status / last-activity / comment-thread column on the right.
class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Customer'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
    }

    final customer = data.customerById(customerId);
    if (customer == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Customer',
            actions: [
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.customers),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Customers'),
              ),
            ],
          ),
          const SizedBox(height: 48),
          const EmptyView(
            icon: Icons.search_off,
            title: 'Customer not found',
            message:
                'This customer may have been removed or is not accessible.',
          ),
        ],
      );
    }

    final business = data.businessById(customer.businessId);
    final canEdit = user?.can(Permission.editCustomer) ?? false;
    final isMobile = Responsive.isMobile(context);

    final left = _ProfileCard(customer: customer);
    final right = _ActivityColumn(customer: customer, canComment: canEdit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: customer.name,
          subtitle: '${customer.id}'
              '${business == null ? '' : ' · ${business.name}'}',
          actions: [
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.customers),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
            if (canEdit)
              ElevatedButton.icon(
                onPressed: () => _edit(context, customer, data),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (isMobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: AppSpacing.lg),
              right,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: left),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: 340, child: right),
            ],
          ),
      ],
    );
  }

  Future<void> _edit(
      BuildContext context, Customer customer, DataController data) async {
    final repo = context.read<AppState>().repository;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CustomerFormDialog(
        existing: customer,
        repo: repo,
        businesses: data.selectableBusinesses,
      ),
    );
    if (saved == true) {
      await data.refresh();
      if (context.mounted) {
        showSuccessSnack(context, 'Customer updated successfully');
      }
    }
  }
}

/// Left column: avatar + contact and company details.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final details = <_Detail>[
      _Detail('Business Type', customer.businessType, Icons.category_outlined),
      _Detail('Company Size', customer.size.label, Icons.groups_outlined),
      _Detail('Contact No', customer.contactNo, Icons.phone_outlined),
      _Detail('Email', customer.email, Icons.mail_outline),
      _Detail('Location', customer.location, Icons.location_on_outlined),
      _Detail('Social Media', customer.socialMedia, Icons.public),
    ];

    return SectionCard(
      title: 'Profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(name: customer.name, size: 64),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(customer.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      customer.businessType.isEmpty
                          ? customer.id
                          : '${customer.businessType} · ${customer.id}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = Responsive.isMobile(context) ? 1 : 2;
              const gap = AppSpacing.lg;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final d in details)
                    SizedBox(width: tileWidth, child: _DetailRow(detail: d)),
                ],
              );
            },
          ),
          if (customer.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            const Text('Description',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(customer.description,
                style: const TextStyle(height: 1.5)),
          ],
        ],
      ),
    );
  }
}

class _Detail {
  const _Detail(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail});
  final _Detail detail;

  @override
  Widget build(BuildContext context) {
    final value = detail.value.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(detail.icon, size: 18, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(detail.label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Right column: deal status, last activity and the comment thread.
class _ActivityColumn extends StatelessWidget {
  const _ActivityColumn({required this.customer, required this.canComment});

  final Customer customer;
  final bool canComment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Deal Status',
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge.deal(customer.dealStatus),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Last Activity',
          child: Row(
            children: [
              const Icon(Icons.schedule,
                  size: 18, color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppDate.format(customer.lastActivityAt),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _CommentThread(customer: customer, canComment: canComment),
      ],
    );
  }
}

/// The comment thread: a list of past comments plus (when permitted) an input
/// to append a new one, attributed to the current user.
class _CommentThread extends StatefulWidget {
  const _CommentThread({required this.customer, required this.canComment});

  final Customer customer;
  final bool canComment;

  @override
  State<_CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends State<_CommentThread> {
  final _controller = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _posting) return;
    final appState = context.read<AppState>();
    final data = context.read<DataController>();
    final user = appState.currentUser;
    if (user == null) return;

    setState(() => _posting = true);
    final comment = CustomerComment(
      id: 'c${DateTime.now().microsecondsSinceEpoch}',
      authorId: user.uid,
      authorName: user.name,
      text: text,
      createdAt: DateTime.now(),
    );
    try {
      await appState.repository.saveCustomer(
        widget.customer
            .copyWith(comments: [...widget.customer.comments, comment]),
        isNew: false,
      );
      _controller.clear();
      await data.refresh();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = [...widget.customer.comments]..sort((a, b) {
        final da = a.createdAt;
        final db = b.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    return SectionCard(
      title: 'Comment Thread',
      subtitle: '${comments.length} '
          '${comments.length == 1 ? 'comment' : 'comments'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.canComment) ...[
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Add a comment…',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _posting ? null : _post,
                icon: _posting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 16),
                label: const Text('Post'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No comments yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (var i = 0; i < comments.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              _CommentTile(comment: comments[i]),
            ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final CustomerComment comment;

  @override
  Widget build(BuildContext context) {
    final author =
        comment.authorName.isEmpty ? 'Unknown' : comment.authorName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InitialsAvatar(name: author, size: 32),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(author,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  if (comment.createdAt != null)
                    Text(
                      AppDate.short(comment.createdAt!),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(comment.text,
                  style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
