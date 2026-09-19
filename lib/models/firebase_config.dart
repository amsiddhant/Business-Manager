/// Public Firebase web-app configuration values entered by the Owner in the
/// setup wizard.
///
/// IMPORTANT: these are *public* client configuration values (safe to ship to
/// browsers). No service-account keys, admin credentials or secrets are ever
/// stored here — see the wizard docs.
class FirebaseConfig {
  const FirebaseConfig({
    required this.apiKey,
    required this.authDomain,
    required this.projectId,
    required this.storageBucket,
    required this.messagingSenderId,
    required this.appId,
    this.measurementId = '',
    this.databaseURL = '',
  });

  final String apiKey;
  final String authDomain;
  final String projectId;
  final String storageBucket;
  final String messagingSenderId;
  final String appId;
  final String measurementId;

  /// Optional Realtime Database URL. The app persists data in Cloud Firestore,
  /// so this is stored for completeness but not used by the data layer.
  final String databaseURL;

  /// The Firebase project the application ships connected to by default. These
  /// are *public* client configuration values (safe to embed in a web build) —
  /// not secrets. The Owner can point the app at a different project from the
  /// Settings → Firebase wizard.
  static const FirebaseConfig defaultConfig = FirebaseConfig(
    apiKey: 'AIzaSyAps0kxM7ueccZGV6Duj6hOczlcfhIOJ1k',
    authDomain: 'mybusiness-manager-bm.firebaseapp.com',
    projectId: 'mybusiness-manager-bm',
    storageBucket: 'mybusiness-manager-bm.firebasestorage.app',
    messagingSenderId: '1068599926536',
    appId: '1:1068599926536:web:a0272212dbb661478516bd',
    databaseURL: 'https://mybusiness-manager-bm-default-rtdb.firebaseio.com',
  );

  bool get isComplete =>
      apiKey.trim().isNotEmpty &&
      authDomain.trim().isNotEmpty &&
      projectId.trim().isNotEmpty &&
      appId.trim().isNotEmpty &&
      messagingSenderId.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'apiKey': apiKey,
        'authDomain': authDomain,
        'projectId': projectId,
        'storageBucket': storageBucket,
        'messagingSenderId': messagingSenderId,
        'appId': appId,
        'measurementId': measurementId,
        'databaseURL': databaseURL,
      };

  factory FirebaseConfig.fromMap(Map<String, dynamic> map) => FirebaseConfig(
        apiKey: map['apiKey'] as String? ?? '',
        authDomain: map['authDomain'] as String? ?? '',
        projectId: map['projectId'] as String? ?? '',
        storageBucket: map['storageBucket'] as String? ?? '',
        messagingSenderId: map['messagingSenderId'] as String? ?? '',
        appId: map['appId'] as String? ?? '',
        measurementId: map['measurementId'] as String? ?? '',
        databaseURL: map['databaseURL'] as String? ?? '',
      );

  FirebaseConfig copyWith({
    String? apiKey,
    String? authDomain,
    String? projectId,
    String? storageBucket,
    String? messagingSenderId,
    String? appId,
    String? measurementId,
    String? databaseURL,
  }) =>
      FirebaseConfig(
        apiKey: apiKey ?? this.apiKey,
        authDomain: authDomain ?? this.authDomain,
        projectId: projectId ?? this.projectId,
        storageBucket: storageBucket ?? this.storageBucket,
        messagingSenderId: messagingSenderId ?? this.messagingSenderId,
        appId: appId ?? this.appId,
        measurementId: measurementId ?? this.measurementId,
        databaseURL: databaseURL ?? this.databaseURL,
      );
}
