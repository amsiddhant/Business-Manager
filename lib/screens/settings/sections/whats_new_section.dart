import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_info.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/theme_x.dart';
import '../settings_widgets.dart';

/// The version you are on, and a way to its release notes.
class WhatsNewSection extends StatelessWidget {
  const WhatsNewSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final router = GoRouter.maybeOf(context);
    return SettingsPanel(
      title: 'What’s new',
      subtitle: 'See what changed in each update',
      children: [
        SettingsCard(
          title: 'Version $kAppVersion',
          subtitle: 'Build $kAppBuild',
          children: [
            Text('Release notes list every change, newest first.',
                style: TextStyle(fontSize: 13, color: t.textSecondary)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: router == null
                    ? null
                    : () => router.go(Routes.whatsNew),
                icon: const Icon(Icons.new_releases_outlined, size: 18),
                label: const Text('Open release notes'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
