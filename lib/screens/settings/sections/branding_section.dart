import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_presets.dart';
import '../../../core/theme/theme_x.dart';
import '../../../models/app_settings.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../../../widgets/forms/form_dialog.dart';
import '../../../widgets/forms/form_fields.dart';
import '../logo_picker.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';
import '../theme_preview_pane.dart';

/// The organisation's name, colour and logo.
class BrandingSection extends StatefulWidget {
  const BrandingSection({super.key, required this.draft});

  final SettingsDraft draft;

  @override
  State<BrandingSection> createState() => _BrandingSectionState();
}

class _BrandingSectionState extends State<BrandingSection> {
  late final TextEditingController _name;
  late final TextEditingController _short;
  late final TextEditingController _tagline;
  late final TextEditingController _hex;
  bool _picking = false;

  SettingsDraft get _draft => widget.draft;
  BrandingSettings get _b => _draft.settings.branding;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _b.appName);
    _short = TextEditingController(text: _b.shortName);
    _tagline = TextEditingController(text: _b.tagline);
    _hex = TextEditingController(
        text: _b.primaryColor == null ? '' : brandHex(_b.brand));
  }

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    _tagline.dispose();
    _hex.dispose();
    super.dispose();
  }

  void _set(BrandingSettings Function(BrandingSettings b) change) =>
      _draft.update((s) => s.copyWith(branding: change(s.branding)));

  void _onHex(String text) {
    if (text.trim().isEmpty) {
      _set((b) => b.copyWith(primaryColor: () => null));
      return;
    }
    final color = parseBrandHex(text);
    if (color != null) {
      _set((b) => b.copyWith(primaryColor: () => color.toARGB32()));
    }
  }

  void _pickPreset(BrandPreset p) {
    final isDefault = p.color.toARGB32() == AppPalette.defaultBrand.toARGB32();
    _hex.text = isDefault ? '' : brandHex(p.color);
    _set((b) => b.copyWith(
        primaryColor: () => isDefault ? null : p.color.toARGB32()));
  }

  Future<void> _upload() async {
    setState(() => _picking = true);
    try {
      final logo = await LogoPicker.pick();
      if (logo != null) _draft.setLogo(logo.dataUrl, hash: logo.hash);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final settings = _draft.settings;
    final brand = _b.brand;
    final contrast = AppTokens.contrastRatio(Colors.white, brand);
    return Form(
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: SettingsPanel(
        title: 'Branding',
        subtitle: 'The name, colour and logo people see',
        onReset: () => _draft.resetSection(
            (s, d) => s.copyWith(branding: d.branding),
            clearLogo: true),
        children: [
          SettingsCard(
            title: 'Name',
            children: [
              AppTextField(
                label: 'App name',
                controller: _name,
                isRequired: true,
                helper: 'Shown in the sidebar, the sign-in page and the browser tab.',
                inputFormatters: [
                  LengthLimitingTextInputFormatter(BrandingSettings.maxAppName)
                ],
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Give the app a name' : null,
                onChanged: (v) => _set((b) => b.copyWith(appName: v.trim())),
              ),
              const FormGap(),
              SettingsGrid(children: [
                AppTextField(
                  label: 'Short name',
                  controller: _short,
                  helper: 'Used where space is tight. Leave empty for initials.',
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                        BrandingSettings.maxShortName)
                  ],
                  onChanged: (v) => _set((b) => b.copyWith(shortName: v.trim())),
                ),
                AppTextField(
                  label: 'Tagline',
                  controller: _tagline,
                  helper: 'One line under the name on the sign-in page.',
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(BrandingSettings.maxTagline)
                  ],
                  onChanged: (v) => _set((b) => b.copyWith(tagline: v.trim())),
                ),
              ]),
            ],
          ),
          SettingsCard(
            title: 'Brand colour',
            subtitle: 'Buttons, links and highlights use this colour.',
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final p in kBrandPresets)
                    _Swatch(
                      preset: p,
                      selected: p.color.toARGB32() == brand.toARGB32(),
                      onTap: () => _pickPreset(p),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SettingsGrid(children: [
                AppTextField(
                  label: 'Hex colour',
                  controller: _hex,
                  hintText: brandHex(AppPalette.defaultBrand),
                  helper: 'Like #2563EB. Leave empty for the default blue.',
                  inputFormatters: [LengthLimitingTextInputFormatter(7)],
                  validator: (v) => (v ?? '').trim().isEmpty ||
                          parseBrandHex(v!) != null
                      ? null
                      : 'Enter a colour like #2563EB',
                  onChanged: _onHex,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: brand,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.border),
                      ),
                    ),
                  ),
                ),
              ]),
              if (contrast < 4.5) ...[
                const SizedBox(height: AppSpacing.md),
                SettingsNote(
                  'White text on this colour is hard to read (contrast '
                  '${contrast.toStringAsFixed(1)}:1; 4.5:1 is the minimum). '
                  'The app switches to dark text on it, but a darker shade '
                  'looks better.',
                  tone: SettingsNoteTone.warning,
                ),
              ],
            ],
          ),
          SettingsCard(
            title: 'Logo',
            subtitle: 'PNG, JPEG or WebP. It is shrunk to fit within '
                '${LogoPicker.maxSide} px.',
            children: [
              Row(
                children: [
                  _LogoTile(dataUrl: _draft.logo),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _picking ? null : _upload,
                          icon: const Icon(Icons.upload_outlined, size: 18),
                          label: Text(
                              _draft.logo == null ? 'Upload logo' : 'Replace logo'),
                        ),
                        if (_draft.logo != null || _b.hasLogo)
                          TextButton.icon(
                            onPressed: () => _draft.setLogo(null, hash: null),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Remove logo'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SettingSwitch(
                title: 'Show logo on sign-in page',
                value: _b.showLogoOnLogin,
                onChanged: (v) => _set((b) => b.copyWith(showLogoOnLogin: v)),
              ),
            ],
          ),
          SettingsCard(
            title: 'Preview',
            subtitle: 'How the app looks with these choices.',
            children: [ThemePreviewPane(settings: settings)],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.preset, required this.selected, required this.onTap});

  final BrandPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: preset.name,
      child: Tooltip(
        message: preset.name,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: preset.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? t.textPrimary : t.border,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check, size: 18, color: t.onColor(preset.color))
                : null,
          ),
        ),
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({required this.dataUrl});
  final String? dataUrl;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget child = Icon(Icons.image_outlined, color: t.textTertiary);
    final url = dataUrl;
    if (url != null) {
      try {
        final bytes = UriData.parse(url).contentAsBytes();
        child = Image.memory(bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                Icon(Icons.broken_image_outlined, color: t.textTertiary));
      } catch (_) {
        child = Icon(Icons.broken_image_outlined, color: t.textTertiary);
      }
    }
    return Container(
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }
}
