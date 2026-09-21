import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../../core/app_exception.dart';
import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../models/app_user.dart';
import '../../models/business.dart';
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

    // Businesses this customer is tagged to that are visible in the current
    // scope (a non-owner may not be able to resolve every tag to a name).
    final businesses = [
      for (final id in customer.businessIds)
        if (data.businessById(id) != null) data.businessById(id)!,
    ];
    final canEdit = user?.can(Permission.editCustomer) ?? false;
    final isMobile = Responsive.isMobile(context);

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileCard(customer: customer, businesses: businesses),
        const SizedBox(height: AppSpacing.lg),
        _TeamAccessCard(customer: customer),
      ],
    );
    final right = _ActivityColumn(customer: customer, canComment: canEdit);

    final subtitle = StringBuffer(customer.id);
    if (businesses.length == 1) {
      subtitle.write(' · ${businesses.first.name}');
    } else if (businesses.length > 1) {
      subtitle.write(' · ${businesses.length} businesses');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: customer.name,
          subtitle: subtitle.toString(),
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

/// Left column: avatar + contact and company details. Every field shows a small
/// copy icon; the social-media value renders as a link button opening in a new
/// tab.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.customer, required this.businesses});

  final Customer customer;
  final List<Business> businesses;

  @override
  Widget build(BuildContext context) {
    final details = <_Detail>[
      _Detail('Customer ID', customer.id, Icons.badge_outlined),
      _Detail('Business Type', customer.businessType, Icons.category_outlined),
      _Detail('Company Size', customer.size.label, Icons.groups_outlined),
      _Detail('Contact No', customer.contactNo, Icons.phone_outlined),
      _Detail('Email', customer.email, Icons.mail_outline),
      _Detail('Location', customer.location, Icons.location_on_outlined),
      _Detail('Deal Status', customer.dealStatus.label, Icons.flag_outlined),
      _Detail('Social Media', customer.socialMedia, Icons.public,
          isLink: true),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(customer.name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                        ),
                        _CopyButton(label: 'name', value: customer.name),
                      ],
                    ),
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
            Row(
              children: [
                const Text('Description',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                _CopyButton(label: 'description', value: customer.description),
              ],
            ),
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
  const _Detail(this.label, this.value, this.icon, {this.isLink = false});
  final String label;
  final String value;
  final IconData icon;

  /// When true the value renders as a link button opening in a new tab.
  final bool isLink;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail});
  final _Detail detail;

  @override
  Widget build(BuildContext context) {
    final value = detail.value.trim();
    final hasValue = value.isNotEmpty;
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
              if (detail.isLink && hasValue && _looksLikeUrl(value))
                _LinkButton(value: value)
              else
                Text(hasValue ? value : '—',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        if (hasValue)
          _CopyButton(label: detail.label.toLowerCase(), value: value),
      ],
    );
  }
}

/// A small icon button that copies [value] to the clipboard and confirms via a
/// snackbar. Present next to every field value in the profile.
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.copy_outlined, size: 15),
      color: AppColors.textTertiary,
      tooltip: 'Copy $label',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) showSuccessSnack(context, 'Copied $label');
      },
    );
  }
}

/// Renders a social-media value as a link button that opens in a new browser
/// tab. Mirrors the product detail screen's URL handling.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _openUrl(value),
        icon: const Icon(Icons.open_in_new, size: 15),
        label: Text(value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

/// Whether [value] can be opened as a real web URL. A fully-qualified URL
/// (has an http/https scheme) or a bare domain (contains a dot, no leading '@')
/// qualifies; handle-style values like "@acme" or "acmehandle" do not — opening
/// them would resolve against the app origin and produce a broken tab.
bool _looksLikeUrl(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  if (v.startsWith(RegExp(r'https?://', caseSensitive: false))) return true;
  return !v.startsWith('@') && v.contains('.');
}

/// Opens [url] in a new browser tab, prepending https:// for bare domains.
/// No-ops for values that are not resolvable URLs (see [_looksLikeUrl]) so a
/// handle never navigates to a bogus same-origin path.
void _openUrl(String url) {
  var normalised = url.trim();
  if (!_looksLikeUrl(normalised)) return;
  if (!normalised.startsWith(RegExp(r'https?://', caseSensitive: false))) {
    normalised = 'https://$normalised';
  }
  html.window.open(normalised, '_blank');
}

/// An expandable tree of the people with access to this customer, grouped by
/// business → Owner / Admins / Users.
///
/// Enumerating user profiles is Owner-only in the Firestore rules
/// (`allow list: if isOwner()`), so a non-owner's roster query is rejected with
/// permission-denied ("rules are not filters"). For non-owner viewers we
/// therefore show the tagged businesses but gate the roster behind an
/// Owner-only note rather than issuing a query that would fail.
class _TeamAccessCard extends StatefulWidget {
  const _TeamAccessCard({required this.customer});

  final Customer customer;

  @override
  State<_TeamAccessCard> createState() => _TeamAccessCardState();
}

class _TeamAccessCardState extends State<_TeamAccessCard> {
  Future<List<AppUser>>? _rosterFuture;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    if (appState.currentUser?.isOwner ?? false) {
      _rosterFuture = appState.repository.fetchUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final isOwnerViewer = appState.currentUser?.isOwner ?? false;

    // Resolve the tagged businesses that are visible in the current scope.
    final businesses = [
      for (final id in widget.customer.businessIds)
        if (data.businessById(id) != null) data.businessById(id)!,
    ];

    return SectionCard(
      title: 'Team Access',
      subtitle: 'Businesses, owners, admins & users with access',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (businesses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('Not tagged to any accessible business.',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          else if (!isOwnerViewer)
            _TeamTree(businesses: businesses, roster: const [], gated: true)
          else
            FutureBuilder<List<AppUser>>(
              future: _rosterFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(ErrorMapper.friendly(snap.error!),
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  );
                }
                return _TeamTree(
                  businesses: businesses,
                  roster: snap.data ?? const [],
                  gated: false,
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The Business → Owner / Admins / Users expansion tree. When [gated] is true
/// (non-owner viewer) the per-business roster is replaced with an Owner-only
/// note, since listing user profiles is not permitted for that caller.
class _TeamTree extends StatelessWidget {
  const _TeamTree({
    required this.businesses,
    required this.roster,
    required this.gated,
  });

  final List<Business> businesses;
  final List<AppUser> roster;
  final bool gated;

  @override
  Widget build(BuildContext context) {
    // Owners have global access regardless of assignment.
    final owners =
        roster.where((u) => u.role == UserRole.owner).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in businesses)
          _BusinessNode(
            business: b,
            owners: owners,
            admins: roster
                .where((u) =>
                    u.role == UserRole.admin &&
                    u.assignedBusinessIds.contains(b.id))
                .toList(),
            users: roster
                .where((u) =>
                    u.role == UserRole.user &&
                    u.assignedBusinessIds.contains(b.id))
                .toList(),
            gated: gated,
          ),
      ],
    );
  }
}

/// A single business branch in the tree with nested Owner / Admins / Users
/// groups.
class _BusinessNode extends StatelessWidget {
  const _BusinessNode({
    required this.business,
    required this.owners,
    required this.admins,
    required this.users,
    required this.gated,
  });

  final Business business;
  final List<AppUser> owners;
  final List<AppUser> admins;
  final List<AppUser> users;
  final bool gated;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Remove the default divider lines ExpansionTile paints when expanded.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.md),
        leading: const Icon(Icons.business_outlined,
            size: 20, color: AppColors.textTertiary),
        title: Text(business.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(business.id,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textTertiary)),
        children: gated
            ? const [
                Padding(
                  padding: EdgeInsets.only(
                      left: AppSpacing.md, bottom: AppSpacing.sm),
                  child: Text(
                    'The team roster (admins & users) is visible to Owners '
                    'only.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                ),
              ]
            : [
                _RoleGroup(
                    label: 'Owner', icon: Icons.shield_outlined, people: owners),
                _RoleGroup(
                    label: 'Admins',
                    icon: Icons.admin_panel_settings_outlined,
                    people: admins),
                _RoleGroup(
                    label: 'Users',
                    icon: Icons.person_outline,
                    people: users),
              ],
      ),
    );
  }
}

/// A role sub-group (Owner / Admins / Users) listing its people, itself an
/// expandable node so the tree can be drilled into level by level.
class _RoleGroup extends StatelessWidget {
  const _RoleGroup({
    required this.label,
    required this.icon,
    required this.people,
  });

  final String label;
  final IconData icon;
  final List<AppUser> people;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.lg),
        dense: true,
        leading: Icon(icon, size: 18, color: AppColors.textTertiary),
        title: Text('$label (${people.length})',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        children: people.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.only(
                      left: AppSpacing.lg, bottom: AppSpacing.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('None',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textTertiary)),
                  ),
                ),
              ]
            : [for (final p in people) _PersonTile(person: p)],
      ),
    );
  }
}

/// A leaf node: one person's avatar, name and email.
class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final AppUser person;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          InitialsAvatar(name: person.name, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(person.name.isEmpty ? person.loginId : person.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                if (person.email.isNotEmpty)
                  Text(person.email,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          StatusBadge.role(person.role),
        ],
      ),
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
