import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:universal_html/html.dart' as html;

import '../../core/app_exception.dart';
import '../../data/repository.dart';
import '../../services/alert_service.dart';

/// A logo ready to save: a small PNG as a data URL, and a short id for it.
class PreparedLogo {
  const PreparedLogo(this.dataUrl, this.hash);

  final String dataUrl;
  final String hash;
}

/// Picking and shrinking the organisation's logo.
class LogoPicker {
  LogoPicker._();

  /// The longest side, in pixels, a saved logo has.
  static const maxSide = 256;

  static const _types = {'image/png', 'image/jpeg', 'image/webp'};

  /// Opens the browser's file picker. Completes with the prepared logo, or
  /// null when nothing usable was chosen; throws an [AppException] with a
  /// friendly message when the file can't be used.
  ///
  /// If the picker is dismissed without choosing a file the future never
  /// completes (browsers expose no cancel event), so don't block the screen
  /// on it.
  static Future<PreparedLogo?> pick() {
    final completer = Completer<PreparedLogo?>();
    final input = html.FileUploadInputElement()
      ..accept = 'image/png,image/jpeg,image/webp'
      ..multiple = false
      ..style.display = 'none';
    html.document.body?.append(input);

    void finish({Object? error, PreparedLogo? logo}) {
      if (!completer.isCompleted) {
        error == null
            ? completer.complete(logo)
            : completer.completeError(error);
      }
      input.remove();
    }

    input.onChange.listen((_) {
      final files = input.files;
      if (files == null || files.isEmpty) {
        finish();
        return;
      }
      final file = files.first;
      if (!_types.contains(file.type)) {
        finish(
            error: const AppException(
                'Please choose a PNG, JPEG or WebP image.'));
        return;
      }
      final reader = html.FileReader();
      reader.onError.listen((_) => finish(
          error: const AppException('That file could not be read.')));
      reader.onLoad.listen((_) async {
        try {
          final result = reader.result;
          final bytes = switch (result) {
            final Uint8List b => b,
            final ByteBuffer b => b.asUint8List(),
            _ => null,
          };
          finish(logo: bytes == null ? null : await prepare(bytes));
        } catch (e) {
          finish(error: e);
        }
      });
      reader.readAsArrayBuffer(file);
    });

    input.click();
    return completer.future;
  }

  /// Shrinks [bytes] (an image) to at most [maxSide] pixels on its long side
  /// and returns it as a PNG data URL.
  static Future<PreparedLogo> prepare(Uint8List bytes) async {
    const unreadable = AppException(
        'That image could not be opened. Try another PNG, JPEG or WebP file.');
    ui.Image image;
    try {
      final probe = await ui.instantiateImageCodec(bytes);
      image = (await probe.getNextFrame()).image;
    } catch (_) {
      throw unreadable;
    }
    final w = image.width;
    final h = image.height;
    image.dispose();
    if (w <= 0 || h <= 0) throw unreadable;

    final long = w >= h ? w : h;
    final scale = long > maxSide ? maxSide / long : 1.0;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: (w * scale).round().clamp(1, maxSide),
      targetHeight: (h * scale).round().clamp(1, maxSide),
    );
    final small = (await codec.getNextFrame()).image;
    final png = await small.toByteData(format: ui.ImageByteFormat.png);
    small.dispose();
    if (png == null) throw unreadable;

    final dataUrl = 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
    if (dataUrl.length > Repository.maxLogoChars) {
      throw const AppException(
          'That logo is too large even after shrinking. Try a simpler image.');
    }
    return PreparedLogo(dataUrl, hashOf(dataUrl));
  }

  /// A short id that changes when the logo does.
  static String hashOf(String dataUrl) =>
      '${AlertService.stableHash(dataUrl)}-${dataUrl.length.toRadixString(16)}';
}
