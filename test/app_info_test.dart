import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/app_info.dart';
import 'package:salesforce_business_manager/core/release_notes.dart';

void main() {
  test('kAppVersion and kAppBuild match pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(match!.group(1), '$kAppVersion+$kAppBuild');
  });

  test('the newest release note is for the current version', () {
    expect(kReleaseNotes.first.version, kAppVersion);
  });

  test('release notes are unique and each has highlights', () {
    final versions = kReleaseNotes.map((n) => n.version).toList();
    expect(versions.toSet().length, versions.length);
    for (final note in kReleaseNotes) {
      expect(note.highlights, isNotEmpty, reason: note.version);
      expect(note.title.trim(), isNotEmpty, reason: note.version);
    }
  });
}
