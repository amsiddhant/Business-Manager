/// A user-facing application error. The [message] is safe to show directly in
/// the UI; raw backend exceptions should be converted to one of these before
/// they reach a widget.
class AppException implements Exception {
  const AppException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Thrown when the current user lacks permission for an operation. Enforced in
/// the service layer, not just the UI.
class PermissionDeniedException extends AppException {
  const PermissionDeniedException([String? message])
      : super(
          message ?? "You don't have permission to perform this action.",
          code: 'permission-denied',
        );
}

/// Thrown when an entity cannot be found.
class NotFoundException extends AppException {
  const NotFoundException([String? message])
      : super(message ?? 'The requested item could not be found.',
            code: 'not-found');
}

/// Converts arbitrary/backend errors into friendly messages. Firebase auth &
/// firestore error codes are mapped to plain English.
class ErrorMapper {
  ErrorMapper._();

  static String friendly(Object error) {
    if (error is AppException) return error.message;

    final text = error.toString();
    final code = _extractCode(text);
    switch (code) {
      case 'permission-denied':
        return "You don't have permission to perform this action.";
      case 'unavailable':
        return 'The service is temporarily unavailable. Please try again.';
      case 'not-found':
        return 'The requested item could not be found.';
      case 'already-exists':
        return 'That item already exists.';
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled. Contact your administrator.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with that email already exists.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'requires-recent-login':
        return 'Please sign in again to complete this sensitive action.';
      case 'operation-not-allowed':
        return 'Email/Password sign-in is not enabled in Firebase. Open the '
            'Firebase Console → Authentication → Sign-in method and enable the '
            'Email/Password provider, then try again.';
      case 'admin-restricted-operation':
        return 'Creating accounts is restricted in this Firebase project. '
            'Disable "email enumeration protection" / enable sign-up under '
            'Authentication settings, then try again.';
      case 'configuration-not-found':
        return 'Firebase Authentication is not configured for this project. '
            'Enable Authentication in the Firebase Console and try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  static String? _extractCode(String text) {
    // Matches "[service/the-code]" and "(auth/the-code)" style messages.
    final match = RegExp(r'[\[(][\w-]+/([\w-]+)[\])]').firstMatch(text);
    if (match != null) return match.group(1);
    // Bare "code" style.
    final bare = RegExp(r'code:\s*([\w-]+)').firstMatch(text);
    return bare?.group(1);
  }
}
