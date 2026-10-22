import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/release_notes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/layout/app_page.dart';

/// Lists every release, newest first (`/whats-new`).
class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      children: [
        const PageHeader(
          title: "What's new",
          subtitle: 'You are on version $kAppVersion',
        ),
        for (final note in kReleaseNotes) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Version ${note.version} · ${note.title}',
            subtitle: note.date,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in note.highlights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle_outline,
                              size: 16, color: context.tokens.success),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(line)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
