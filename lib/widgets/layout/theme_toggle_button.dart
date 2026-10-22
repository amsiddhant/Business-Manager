import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/theme_controller.dart';
import '../../state/user_prefs.dart';

/// Flips between light and dark. Hidden when the organisation fixes the theme.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    final canChoose =
        context.select<ThemeController, bool>((t) => t.canChooseMode);
    if (!canChoose) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: size,
      ),
      onPressed: () => context
          .read<UserPrefs>()
          .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}
