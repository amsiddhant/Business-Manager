import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/theme_x.dart';
import '../../../state/app_state.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../settings_widgets.dart';

/// Who can sign in, and the tools to keep sign-in healthy.
class AccessSection extends StatefulWidget {
  const AccessSection({super.key});

  @override
  State<AccessSection> createState() => _AccessSectionState();
}

class _AccessSectionState extends State<AccessSection> {
  bool _rebuilding = false;

  Future<void> _rebuild() async {
    final repo = context.read<AppState>().repository;
    setState(() => _rebuilding = true);
    try {
      final count = await repo.rebuildLoginIndex();
      if (mounted) {
        showSuccessSnack(context,
            'Sign-in index rebuilt: $count login ${count == 1 ? 'ID' : 'IDs'}');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final router = GoRouter.maybeOf(context);
    return SettingsPanel(
      title: 'Users and access',
      subtitle: 'Manage people and keep sign-in working',
      children: [
        SettingsCard(
          title: 'Users',
          subtitle: 'Add people, change roles and reset access.',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: router == null ? null : () => router.go(Routes.users),
                icon: const Icon(Icons.group_outlined, size: 18),
                label: const Text('Open users'),
              ),
            ),
          ],
        ),
        SettingsCard(
          title: 'Sign-in index',
          subtitle: 'Lets people sign in with a login ID instead of an email.',
          children: [
            Text(
              'Rebuild it if someone can’t sign in with their login ID even '
              'though their account exists.',
              style: TextStyle(fontSize: 13, color: t.textSecondary),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _rebuilding ? null : _rebuild,
                icon: _rebuilding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.manage_search, size: 18),
                label: const Text('Rebuild sign-in index'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
