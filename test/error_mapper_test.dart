import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/app_exception.dart';

void main() {
  group('ErrorMapper.friendly', () {
    test('passes through an AppException message verbatim', () {
      const e = AppException('Custom message', code: 'x');
      expect(ErrorMapper.friendly(e), 'Custom message');
    });

    test('maps auth codes embedded in "[auth/code]" style strings', () {
      expect(
        ErrorMapper.friendly(Exception('[firebase_auth/email-already-in-use]')),
        'An account with that email already exists.',
      );
    });

    // Issue #4: creating Admin/User accounts failed with an opaque message when
    // the Firebase project had Email/Password sign-in disabled. These codes now
    // map to actionable guidance instead of "Something went wrong".
    test('operation-not-allowed guides the owner to enable the provider', () {
      final msg =
          ErrorMapper.friendly(Exception('[auth/operation-not-allowed]'));
      expect(msg, contains('Email/Password'));
      expect(msg, contains('Sign-in method'));
    });

    test('admin-restricted-operation is explained', () {
      final msg = ErrorMapper.friendly(
          Exception('[auth/admin-restricted-operation]'));
      expect(msg, contains('restricted'));
    });

    test('configuration-not-found is explained', () {
      final msg =
          ErrorMapper.friendly(Exception('[auth/configuration-not-found]'));
      expect(msg, contains('Authentication'));
    });

    test('unknown codes fall back to the generic message', () {
      expect(
        ErrorMapper.friendly(Exception('[auth/some-new-code]')),
        'Something went wrong. Please try again.',
      );
    });
  });
}
