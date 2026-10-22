import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/validators.dart';
import '../../../data/repository.dart';
import '../../../models/contact.dart';
import '../../../models/customer.dart';
import '../../../state/app_state.dart';
import '../../../view_models/customer_contacts_view_model.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../../../widgets/common/detail_widgets.dart';
import '../../../widgets/common/initials_avatar.dart';
import '../../../widgets/common/search_field.dart';
import '../../../widgets/forms/app_form.dart';
import '../../../widgets/forms/form_dialog.dart';
import '../../../widgets/forms/form_fields.dart';
import '../../../widgets/forms/form_section.dart';

/// The customer-side Contacts section: the people on the customer's side (CEO,
/// Tech Lead, CSM, …) with add / edit / delete. Each contact's display picture
/// is auto-generated from their name via [InitialsAvatar]. Mutations route
/// through [CustomerContactsViewModel], which persists the change as a
/// customer-document save (reusing the customer's permission gate and audit
/// trail).
///
/// Add/edit/delete affordances are shown only when [canEdit]
/// (`Permission.editCustomer`); the underlying repository re-checks on save.
class ContactsCard extends StatefulWidget {
  const ContactsCard({super.key, required this.customer, required this.canEdit});

  final Customer customer;
  final bool canEdit;

  @override
  State<ContactsCard> createState() => _ContactsCardState();
}

class _ContactsCardState extends State<ContactsCard> {
  /// Live search query. Matched (case-insensitively) against name, designation,
  /// email and number. Debounced by [SearchField].
  String _query = '';

  Customer get _customer => widget.customer;
  bool get _canEdit => widget.canEdit;

  /// Contacts matching the current [_query]. Empty query returns all.
  List<Contact> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _customer.contacts;
    return _customer.contacts.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.designation.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q) ||
          c.number.toLowerCase().contains(q);
    }).toList();
  }

  /// Opens the add/edit form. Persistence happens inside [ContactFormDialog]
  /// (the canonical [FormDialog] pattern), so the dialog resolves to `true` on a
  /// successful save; we then confirm. [existing] null means add.
  Future<void> _openForm({Contact? existing}) async {
    final repo = context.read<AppState>().repository;
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => ContactFormDialog(
          customer: _customer, repo: repo, existing: existing),
    );
    if (saved == true) {
      if (mounted) {
        showSuccessSnack(
            context, existing == null ? 'Contact added' : 'Contact updated');
      }
    }
  }

  Future<void> _delete(Contact contact) async {
    final repo = context.read<AppState>().repository;
    final label = contact.name.trim().isEmpty ? 'this contact' : contact.name;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete contact?',
      message: 'Remove $label from this customer? '
          'This action cannot be easily undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await CustomerContactsViewModel(repo).remove(_customer, contact.id);
      if (mounted) showSuccessSnack(context, 'Contact deleted');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// Opens the read-only view modal and routes any edit/delete action it emits.
  Future<void> _view(Contact contact) async {
    final action = await showDialog<_ContactAction>(
      context: context,
      builder: (_) => ContactViewDialog(contact: contact, canEdit: _canEdit),
    );
    if (!mounted) return;
    switch (action) {
      case _ContactAction.edit:
        await _openForm(existing: contact);
      case _ContactAction.delete:
        await _delete(contact);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final total = _customer.contacts.length;
    final filtered = _filtered;
    return SectionCard(
      title: 'Contacts',
      subtitle: '$total ${total == 1 ? 'contact' : 'contacts'} '
          'on the customer side',
      trailing: _canEdit
          ? TextButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Add Contact'),
            )
          : null,
      child: total == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.groups_outlined, size: 22, color: t.textTertiary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _canEdit
                          ? 'No contacts yet. Add the people on the customer '
                              'side (e.g. CEO, Tech Lead, CSM).'
                          : 'No contacts recorded for this customer.',
                      style: TextStyle(color: t.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live searchbar — shown once there is more than one contact to
                // sift through.
                if (total > 1) ...[
                  SearchField(
                    hintText: 'Search name, designation, email or number…',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text('No contacts match “${_query.trim()}”.',
                        style: TextStyle(color: t.textSecondary)),
                  )
                else
                  for (var i = 0; i < filtered.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      const Divider(height: 1),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    _ContactTile(
                      contact: filtered[i],
                      onTap: () => _view(filtered[i]),
                    ),
                  ],
              ],
            ),
    );
  }
}

/// The action a [ContactViewDialog] resolves to when dismissed.
enum _ContactAction { edit, delete }

/// One contact row in the list: an auto-generated initials avatar, the name and
/// designation, plus an email / number hint. Tapping opens the read-only
/// [ContactViewDialog] where the full details (with copy buttons) and
/// edit/delete actions live.
class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onTap});

  final Contact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = contact.name.trim().isEmpty ? 'Unnamed contact' : contact.name;
    final designation = contact.designation.trim();
    final reach = [contact.email.trim(), contact.number.trim()]
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Row(
          children: [
            InitialsAvatar(name: name, size: 44),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  if (designation.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(designation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: t.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                  if (reach.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(reach,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: t.textSecondary)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: t.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// A read-only modal showing every field of a [Contact], each with a copy
/// button (reusing [DetailFieldTile]), headed by the auto-generated avatar. When
/// [canEdit] is true it offers Edit / Delete in the footer; selecting one pops
/// the corresponding action for the caller to handle (it does not mutate
/// anything itself, keeping persistence in one place).
class ContactViewDialog extends StatelessWidget {
  const ContactViewDialog({
    super.key,
    required this.contact,
    required this.canEdit,
  });

  final Contact contact;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = contact.name.trim().isEmpty ? 'Unnamed contact' : contact.name;
    final designation = contact.designation.trim();
    final fields = <DetailField>[
      DetailField('Name', contact.name, Icons.person_outline),
      DetailField('Designation', contact.designation, Icons.badge_outlined),
      DetailField('Email', contact.email, Icons.mail_outline),
      DetailField('Number', contact.number, Icons.phone_outlined),
      DetailField('Description', contact.description, Icons.notes_outlined),
    ];

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: avatar + name/designation + close.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
          child: Row(
            children: [
              InitialsAvatar(name: name, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    if (designation.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(designation,
                          style: TextStyle(
                              fontSize: 13,
                              color: t.primary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: t.textSecondary),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Body: all fields, each with a copy button.
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.lg),
                  DetailFieldTile(field: fields[i]),
                ],
                if (contact.createdAt != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  DetailFieldTile(
                    field: DetailField('Added',
                        AppDate.format(contact.createdAt), Icons.schedule),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (canEdit) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_ContactAction.delete),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: t.error),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_ContactAction.edit),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: content,
      ),
    );
  }
}

/// Add/edit form for a customer-side [Contact]. Captures the five fields — Name
/// (required), Email (optional, validated), Designation, Number and Description.
///
/// Follows the canonical [FormDialog] contract used across the app: it persists
/// the change itself in `_submit` via [CustomerContactsViewModel] and returns
/// `true`/`false`, letting [FormDialog] perform the single dialog pop. It must
/// NOT call [Navigator.pop] itself — doing so plus returning `true` would pop
/// twice and tear down the page beneath.
class ContactFormDialog extends StatefulWidget {
  const ContactFormDialog({
    super.key,
    required this.customer,
    required this.repo,
    this.existing,
  });

  /// The customer the contact belongs to (the save target).
  final Customer customer;
  final Repository repo;

  /// The contact being edited, or null when adding a new one.
  final Contact? existing;

  @override
  State<ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<ContactFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _designation;
  late final TextEditingController _number;
  late final TextEditingController _description;

  Contact? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final c = _existing;
    _name = TextEditingController(text: c?.name ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _designation = TextEditingController(text: c?.designation ?? '');
    _number = TextEditingController(text: c?.number ?? '');
    _description = TextEditingController(text: c?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _designation.dispose();
    _number.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    return FormDialog(
      title: isNew ? 'Add Contact' : 'Edit Contact',
      icon: Icons.contact_phone_outlined,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormSection(
              title: 'Person',
              icon: Icons.person_outline,
              first: true,
              children: [
                AppTextField(
                  label: 'Name',
                  controller: _name,
                  isRequired: true,
                  hintText: 'e.g. Jane Cooper',
                  validator: (v) => Validators.required(v, field: 'Name'),
                ),
                const FormGap(),
                AppTextField(
                  label: 'Designation',
                  controller: _designation,
                  hintText: 'e.g. CEO, Tech Lead, CSM',
                ),
                const FormGap(),
                AppTextField(
                  label: 'Description',
                  controller: _description,
                  maxLines: 3,
                  hintText: 'Role, responsibilities or notes',
                ),
              ],
            ),
            FormSection(
              title: 'Reach them',
              icon: Icons.alternate_email,
              children: [
                FormRow([
                  AppTextField(
                    label: 'Email',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? null
                        : Validators.email(v),
                  ),
                  AppTextField(
                    label: 'Number',
                    controller: _number,
                    keyboardType: TextInputType.phone,
                  ),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    final vm = CustomerContactsViewModel(widget.repo);
    try {
      final existing = _existing;
      if (existing == null) {
        // Add: buildDraft mints the id/createdAt and trims the fields.
        final draft = vm.buildDraft(
          name: _name.text,
          email: _email.text,
          designation: _designation.text,
          number: _number.text,
          description: _description.text,
        );
        await vm.add(widget.customer, draft);
      } else {
        // Edit: keep the id/createdAt, apply the (trimmed) field values.
        final updated = existing.copyWith(
          name: _name.text.trim(),
          email: _email.text.trim(),
          designation: _designation.text.trim(),
          number: _number.text.trim(),
          description: _description.text.trim(),
        );
        await vm.update(widget.customer, updated);
      }
      // Return true so FormDialog performs the single pop; do NOT pop here.
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}
