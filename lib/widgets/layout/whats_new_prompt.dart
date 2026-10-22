import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/release_notes.dart';
import '../../core/routing/app_routes.dart';
import '../../state/app_state.dart';

/// After an upgrade, shows one "Updated to version X" message with a link to
/// "What's new". Shown once per version per browser. Renders nothing.
class WhatsNewPrompt extends StatefulWidget {
  const WhatsNewPrompt({super.key});

  @override
  State<WhatsNewPrompt> createState() => _WhatsNewPromptState();
}

class _WhatsNewPromptState extends State<WhatsNewPrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  void _maybeShow() {
    if (!mounted) return;
    final appState = context.read<AppState>();
    if (!appState.hasUnseenRelease) return;
    unawaited(appState.markReleaseSeen());
    final note = kReleaseNotes.first;
    final router = GoRouter.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Updated to version ${note.version}: ${note.title}.'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: "See what's new",
          onPressed: () => router.go(Routes.whatsNew),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
