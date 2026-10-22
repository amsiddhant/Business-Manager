import 'package:flutter/material.dart';

import 'app_palette.dart';

/// A ready-made brand colour an Owner or Admin can pick in Settings.
class BrandPreset {
  const BrandPreset(this.name, this.color);

  final String name;
  final Color color;
}

/// The swatches offered under Settings › Branding. The first is the app's own
/// brand colour; every other one is dark enough for white text (AA, 4.5:1).
const List<BrandPreset> kBrandPresets = [
  BrandPreset('Default blue', AppPalette.defaultBrand),
  BrandPreset('Indigo', Color(0xFF4F46E5)),
  BrandPreset('Violet', Color(0xFF7C3AED)),
  BrandPreset('Magenta', Color(0xFFBE185D)),
  BrandPreset('Crimson', Color(0xFFB91C1C)),
  BrandPreset('Orange', Color(0xFFC2410C)),
  BrandPreset('Amber', Color(0xFF92400E)),
  BrandPreset('Emerald', Color(0xFF047857)),
  BrandPreset('Teal', Color(0xFF0F766E)),
  BrandPreset('Slate', Color(0xFF334155)),
];

/// `#RRGGBB` for [color] (no alpha).
String brandHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Parses `#RRGGBB`, `RRGGBB` or `#RGB`; null when it isn't a colour.
Color? parseBrandHex(String input) {
  var s = input.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return Color(0xFF000000 | int.parse(s, radix: 16));
}
