import 'package:flutter/material.dart';

import '../widgets/common/page_header.dart';
import '../widgets/common/state_views.dart';

/// A temporary placeholder for modules that are being built. Rendered inside the
/// app shell so navigation and layout can be exercised before each screen lands.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.construction_outlined,
  });

  final String title;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: title, subtitle: subtitle),
        const SizedBox(height: 48),
        EmptyView(
          icon: icon,
          title: '$title is coming together',
          message: 'This module is under construction.',
        ),
      ],
    );
  }
}
