import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';

/// The organisation's logo, when it has one (Settings, Branding).
///
/// Shows nothing when there's no logo (or none can be decoded) — callers
/// decide what to show instead with [OrgLogo.of].
class OrgLogo extends StatelessWidget {
  const OrgLogo({
    super.key,
    required this.size,
    this.maxWidth,
    this.fit = BoxFit.contain,
  });

  /// Height of the logo box.
  final double size;

  /// Width limit; defaults to [size] (square).
  final double? maxWidth;
  final BoxFit fit;

  /// The logo's data URL, or null. Rebuilds when it changes. Falls back to
  /// null when no [SettingsController] is provided.
  static String? dataUrlOf(BuildContext context) {
    try {
      return context.select<SettingsController, String?>((c) => c.logo);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Whether a decodable logo is set.
  static bool has(BuildContext context) => decode(dataUrlOf(context)) != null;

  static String? _lastUrl;
  static Uint8List? _lastBytes;

  /// The image bytes of a `data:` URL (cached for the last one), or null.
  static Uint8List? decode(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    if (identical(dataUrl, _lastUrl) || dataUrl == _lastUrl) return _lastBytes;
    Uint8List? bytes;
    try {
      bytes = UriData.parse(dataUrl).contentAsBytes();
    } on FormatException {
      bytes = null;
    } on ArgumentError {
      bytes = null;
    }
    _lastUrl = dataUrl;
    _lastBytes = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = decode(dataUrlOf(context));
    if (bytes == null) return const SizedBox.shrink();
    return SizedBox(
      height: size,
      width: maxWidth ?? size,
      child: Image.memory(
        bytes,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
