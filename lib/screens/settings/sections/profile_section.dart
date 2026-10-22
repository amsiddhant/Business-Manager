import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../state/app_state.dart';
import '../../../widgets/common/status_badge.dart';
import '../settings_widgets.dart';

/// Who you are signed in as.
class ProfileSection extends StatelessWidget {
  const ProfileSection({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    if (user == null) return const SizedBox.shrink();
    return SettingsPanel(
      title: 'Profile',
      subtitle: 'Your account details',
      children: [
        SettingsCard(
          title: 'Your account',
          trailing: StatusBadge.role(user.role),
          children: [
            _ProfileRow(label: 'Name', value: user.name),
            _ProfileRow(label: 'Login ID', value: user.loginId),
            _ProfileRow(label: 'Email', value: user.email),
          ],
        ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: context.tokens.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
