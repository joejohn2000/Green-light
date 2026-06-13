import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

final sl = GetIt.instance;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = AppStorage();
  await storage.init();
  sl.registerSingleton<AppStorage>(storage);
  sl.registerSingleton<AppThemeController>(AppThemeController(storage));
  sl.registerLazySingleton<ApiClient>(() => ApiClient(storage));
  sl.registerLazySingleton<AuthRepository>(() => AuthRepository(sl()));
  sl.registerLazySingleton<ConsentRepository>(() => ConsentRepository(sl()));
  sl.registerLazySingleton<LocalConsentStore>(() => LocalConsentStore(storage));
  sl.registerSingleton<AppSession>(AppSession(storage));
  runApp(const GreenLightApp());
}

class GreenLightApp extends StatelessWidget {
  const GreenLightApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = sl<AppSession>();
    final router = GoRouter(
      refreshListenable: session,
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const LocalTouchConsentScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
        GoRoute(path: '/verify', builder: (_, __) => const IdentityScreen()),
        GoRoute(
          path: '/agreements',
          builder: (_, __) => const AgreementListScreen(),
        ),
        GoRoute(path: '/new', builder: (_, __) => const NewAgreementScreen()),
        GoRoute(
          path: '/agreements/:id',
          builder: (_, state) => AgreementDetailScreen(
            agreementId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: sl<AppThemeController>(),
      builder: (context, themeMode, _) {
        return MaterialApp.router(
          title: 'Green Light',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: themeMode,
        );
      },
    );
  }
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF14764A),
    brightness: brightness,
    primary: isDark ? const Color(0xFF67D19C) : const Color(0xFF14764A),
    secondary: isDark ? const Color(0xFF8DB8E8) : const Color(0xFF28527A),
    tertiary: isDark ? const Color(0xFFFFD166) : const Color(0xFFE7A928),
    surface: isDark ? const Color(0xFF111816) : const Color(0xFFF8FAF8),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF17211E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0xFF2B3A35) : const Color(0xFFE0E7E2),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF344740) : const Color(0xFFD6E1D9),
        ),
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF101715) : Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

class ApiUrls {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://green-light-e9mq.onrender.com/api',
  );
}

class LocalConsentRecord {
  LocalConsentRecord({
    required this.id,
    required this.requesterName,
    required this.holderName,
    required this.status,
    required this.createdAt,
    this.signedAt,
    this.cancelledAt,
  });

  final String id;
  final String requesterName;
  final String holderName;
  final String status;
  final DateTime createdAt;
  final DateTime? signedAt;
  final DateTime? cancelledAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'requester_name': requesterName,
      'holder_name': holderName,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      if (signedAt != null) 'signed_at': signedAt!.toIso8601String(),
      if (cancelledAt != null) 'cancelled_at': cancelledAt!.toIso8601String(),
    };
  }

  factory LocalConsentRecord.fromJson(Map<String, dynamic> json) {
    return LocalConsentRecord(
      id: json['id'] ?? '',
      requesterName: json['requester_name'] ?? 'User 1',
      holderName: json['holder_name'] ?? 'Your name',
      status: json['status'] ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      signedAt: json['signed_at'] == null
          ? null
          : DateTime.tryParse(json['signed_at']),
      cancelledAt: json['cancelled_at'] == null
          ? null
          : DateTime.tryParse(json['cancelled_at']),
    );
  }
}

String cleanLocalPartyName(String value, String fallback) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized == 'YOUR NAME' ||
      normalized.toLowerCase() == 'bla') {
    return fallback;
  }
  return normalized;
}

class LocalUserProfile {
  LocalUserProfile({
    required this.name,
    required this.idNumber,
    required this.confirmedAt,
  });

  final String name;
  final String idNumber;
  final DateTime confirmedAt;

  String get maskedId {
    if (idNumber.length <= 4) return idNumber;
    return '•••• ${idNumber.substring(idNumber.length - 4)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'id_number': idNumber,
      'confirmed_at': confirmedAt.toIso8601String(),
    };
  }

  factory LocalUserProfile.fromJson(Map<String, dynamic> json) {
    return LocalUserProfile(
      name: json['name'] ?? '',
      idNumber: json['id_number'] ?? '',
      confirmedAt:
          DateTime.tryParse(json['confirmed_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class LocalConsentStore {
  LocalConsentStore(this._storage);

  final AppStorage _storage;

  Future<List<LocalConsentRecord>> records() {
    return _storage.localConsentRecords();
  }

  Future<String> displayName() async {
    return _storage.localDisplayName;
  }

  Future<LocalUserProfile?> profile() async {
    return _storage.localUserProfile();
  }

  Future<void> saveProfile({
    required String name,
    required String idNumber,
  }) async {
    final profile = LocalUserProfile(
      name: name.trim(),
      idNumber: idNumber.trim(),
      confirmedAt: DateTime.now(),
    );
    await _storage.saveLocalUserProfile(profile);
    await _storage.saveLocalDisplayName(profile.name);
  }

  Future<void> saveDisplayName(String value) async {
    await _storage.saveLocalDisplayName(
      value.trim().isEmpty ? 'Your name' : value.trim(),
    );
  }

  Future<LocalConsentRecord> saveDecision({
    required String requesterName,
    required String holderName,
    required bool accepted,
  }) async {
    final now = DateTime.now();
    final record = LocalConsentRecord(
      id: now.microsecondsSinceEpoch.toString(),
      requesterName: requesterName.trim().isEmpty
          ? 'User 1'
          : requesterName.trim(),
      holderName: holderName.trim().isEmpty ? 'Your name' : holderName.trim(),
      status: accepted ? 'signed' : 'cancelled',
      createdAt: now,
      signedAt: accepted ? now : null,
      cancelledAt: accepted ? null : now,
    );
    final existing = await records();
    await _storage.saveLocalConsentRecords(
      [record, ...existing].take(20).toList(),
    );
    return record;
  }
}

class NearbyPermissionRequirement {
  const NearbyPermissionRequirement({
    required this.id,
    required this.label,
    required this.description,
    required this.permission,
    required this.status,
  });

  final String id;
  final String label;
  final String description;
  final Permission permission;
  final PermissionStatus status;

  bool get isGranted => status.isGranted || status.isLimited;
  bool get needsSettings => status.isPermanentlyDenied || status.isRestricted;
}

class NearbyConsentTransport {
  NearbyConsentTransport({
    required this.onIncomingRequest,
    required this.onStatusChanged,
    required this.onPermissionRequired,
  });

  static const _channel = MethodChannel('green_light/nearby');

  final ValueChanged<String> onIncomingRequest;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onPermissionRequired;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start(
    LocalUserProfile profile, {
    bool requestPermissions = false,
  }) async {
    _channel.setMethodCallHandler(_handleNativeEvent);
    if (!isSupported) {
      onStatusChanged('Nearby works on a real Android phone build.');
      return;
    }
    if (requestPermissions) {
      await requestMissingPermissions();
    }
    final missingPermissions = await missingPermissionRequirements();
    if (missingPermissions.isNotEmpty) {
      onPermissionRequired('Allow nearby permissions to scan for users.');
      return;
    }
    try {
      await _channel.invokeMethod('start', {
        'displayName': profile.name,
        'idSuffix': profile.maskedId,
      });
      onStatusChanged('Scanning nearby devices');
    } on PlatformException catch (error) {
      onStatusChanged(error.message ?? 'Could not start nearby.');
    }
  }

  Future<void> requestPermissionsOnOpen() async {
    _channel.setMethodCallHandler(_handleNativeEvent);
    if (!isSupported) {
      onStatusChanged('Nearby works on a real Android phone build.');
      return;
    }
    final missingBeforeRequest = await missingPermissionRequirements();
    if (missingBeforeRequest.isEmpty) {
      onStatusChanged(
        'Nearby permissions are ready. Confirm identity to scan.',
      );
      return;
    }
    await requestMissingPermissions();
    final missingAfterRequest = await missingPermissionRequirements();
    if (missingAfterRequest.isEmpty) {
      onStatusChanged(
        'Nearby permissions are ready. Confirm identity to scan.',
      );
    } else {
      onPermissionRequired('Allow nearby permissions to scan for users.');
    }
  }

  Future<void> stop() async {
    if (!isSupported) return;
    await _channel.invokeMethod('stop');
  }

  Future<bool> sendConsentRequest(LocalUserProfile profile) async {
    if (!isSupported) {
      onStatusChanged('Build APK/AAB and test on two Android phones.');
      return false;
    }
    try {
      final sent = await _channel.invokeMethod<bool>('sendConsentRequest', {
        'displayName': profile.name,
      });
      if (sent != true) {
        onStatusChanged('No nearby connected user yet.');
        return false;
      }
      onStatusChanged('Consent request sent.');
      return true;
    } on PlatformException catch (error) {
      onStatusChanged(error.message ?? 'Could not send request.');
      return false;
    }
  }

  Future<void> sendDecision(bool accepted) async {
    if (!isSupported) return;
    await _channel.invokeMethod('sendDecision', {'accepted': accepted});
  }

  Future<void> openAppPermissions() async {
    await openAppSettings();
  }

  Future<void> openBluetoothSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod('openBluetoothSettings');
  }

  Future<void> openLocationSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod('openLocationSettings');
  }

  Future<void> openWifiSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod('openWifiSettings');
  }

  Future<List<NearbyPermissionRequirement>>
  missingPermissionRequirements() async {
    if (!isSupported) return [];
    final requirements = await _permissionRequirements();
    return [
      for (final requirement in requirements)
        if (!requirement.isGranted) requirement,
    ];
  }

  Future<void> requestPermission(
    NearbyPermissionRequirement requirement,
  ) async {
    if (requirement.needsSettings) {
      await openAppPermissions();
      return;
    }
    await requirement.permission.request();
  }

  Future<void> requestMissingPermissions() async {
    final requirements = await missingPermissionRequirements();
    for (final requirement in requirements) {
      if (requirement.needsSettings) continue;
      await requirement.permission.request();
    }
  }

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
    switch (call.method) {
      case 'nearbyStatus':
        onStatusChanged(
          friendlyNearbyStatus(
            args['message']?.toString() ?? 'Nearby updated.',
          ),
        );
      case 'incomingConsentRequest':
        final requesterName = args['requesterName']?.toString() ?? '';
        if (requesterName.trim().isNotEmpty) {
          onIncomingRequest(requesterName);
        }
      case 'consentDecision':
        final accepted = args['accepted'] == true;
        onStatusChanged(
          accepted
              ? 'Nearby user accepted your request.'
              : 'Nearby user cancelled your request.',
        );
    }
  }

  String friendlyNearbyStatus(String message) {
    if (message.contains('8032')) {
      return 'Phone setup needs attention.';
    }
    if (message.toLowerCase().contains('permission')) {
      return 'Allow nearby permissions to scan for users.';
    }
    return message;
  }

  Future<List<NearbyPermissionRequirement>> _permissionRequirements() async {
    final sdk = await _androidSdkVersion();
    final specs =
        <
          ({String id, String label, String description, Permission permission})
        >[
          (
            id: 'location',
            label: 'Location permission',
            description: 'Required by Android to discover nearby devices.',
            permission: Permission.location,
          ),
          if (sdk >= 31) ...[
            (
              id: 'bluetooth_scan',
              label: 'Bluetooth scan permission',
              description: 'Required to find nearby phones.',
              permission: Permission.bluetoothScan,
            ),
            (
              id: 'bluetooth_connect',
              label: 'Bluetooth connect permission',
              description: 'Required to connect to the nearby phone.',
              permission: Permission.bluetoothConnect,
            ),
            (
              id: 'bluetooth_advertise',
              label: 'Bluetooth advertise permission',
              description: 'Required so nearby phones can find this phone.',
              permission: Permission.bluetoothAdvertise,
            ),
          ],
          if (sdk >= 33)
            (
              id: 'nearby_wifi',
              label: 'Nearby Wi-Fi permission',
              description:
                  'Required by newer Android versions for local device discovery.',
              permission: Permission.nearbyWifiDevices,
            ),
        ];

    final requirements = <NearbyPermissionRequirement>[];
    for (final spec in specs) {
      requirements.add(
        NearbyPermissionRequirement(
          id: spec.id,
          label: spec.label,
          description: spec.description,
          permission: spec.permission,
          status: await spec.permission.status,
        ),
      );
    }
    return requirements;
  }

  Future<int> _androidSdkVersion() async {
    if (!isSupported) return 0;
    return await _channel.invokeMethod<int>('androidSdkVersion') ?? 0;
  }
}

class AppStorage {
  static const _localConsentRecordsKey = 'local_consent_records';
  static const _localDisplayNameKey = 'local_display_name';
  static const _localUserProfileKey = 'local_user_profile';

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String? get accessToken => _prefs.getString('access_token');
  String? get refreshToken => _prefs.getString('refresh_token');
  ThemeMode get themeMode {
    final value = _prefs.getString('theme_mode');
    if (value == 'dark') return ThemeMode.dark;
    if (value == 'light') return ThemeMode.light;
    return ThemeMode.system;
  }

  String get localDisplayName {
    final value = _prefs.getString(_localDisplayNameKey);
    if (value == null || value.isEmpty || value == 'YOUR NAME') {
      return 'Your name';
    }
    return value;
  }

  Future<void> saveTokens(String access, String refresh) async {
    await _prefs.setString('access_token', access);
    await _prefs.setString('refresh_token', refresh);
  }

  Future<void> clear() async {
    await _prefs.remove('access_token');
    await _prefs.remove('refresh_token');
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await _prefs.setString('theme_mode', mode.name);
  }

  Future<void> saveLocalDisplayName(String value) async {
    await _prefs.setString(_localDisplayNameKey, value);
  }

  Future<LocalUserProfile?> localUserProfile() async {
    final raw = _prefs.getString(_localUserProfileKey);
    if (raw == null || raw.isEmpty) return null;
    return LocalUserProfile.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw)),
    );
  }

  Future<void> saveLocalUserProfile(LocalUserProfile profile) async {
    await _prefs.setString(_localUserProfileKey, jsonEncode(profile.toJson()));
  }

  Future<List<LocalConsentRecord>> localConsentRecords() async {
    final raw = _prefs.getString(_localConsentRecordsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) =>
              LocalConsentRecord.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> saveLocalConsentRecords(List<LocalConsentRecord> records) async {
    await _prefs.setString(
      _localConsentRecordsKey,
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
  }
}

class AppThemeController extends ValueNotifier<ThemeMode> {
  AppThemeController(this._storage) : super(_storage.themeMode);

  final AppStorage _storage;

  bool get isDarkMode => value == ThemeMode.dark;

  Future<void> toggle() async {
    value = value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await _storage.saveThemeMode(value);
  }
}

class AppSession extends ChangeNotifier {
  AppSession(this._storage);

  final AppStorage _storage;

  bool get isLoggedIn => _storage.accessToken?.isNotEmpty == true;

  Future<void> saveTokens(String access, String refresh) async {
    await _storage.saveTokens(access, refresh);
    notifyListeners();
  }

  Future<void> logout() async {
    await _storage.clear();
    notifyListeners();
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this._storage);

  final AppStorage _storage;

  Map<String, String> get _headers {
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final token = _storage.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri authenticatedUri(String endpoint) {
    final uri = Uri.parse('${ApiUrls.baseUrl}$endpoint');
    final token = _storage.accessToken;
    if (token == null || token.isEmpty) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'access_token': token},
    );
  }

  Future<dynamic> get(String endpoint) async {
    final response = await http
        .get(Uri.parse('${ApiUrls.baseUrl}$endpoint'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    return await _decode(response);
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse('${ApiUrls.baseUrl}$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return await _decode(response);
  }

  Future<dynamic> multipart(
    String endpoint, {
    required Map<String, String> fields,
    required Map<String, XFile> files,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiUrls.baseUrl}$endpoint'),
    );
    final token = _storage.accessToken;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.headers['Accept'] = 'application/json';
    request.fields.addAll(fields);
    for (final entry in files.entries) {
      final bytes = await entry.value.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          entry.key,
          bytes,
          filename: entry.value.name,
        ),
      );
    }
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    return await _decode(await http.Response.fromStream(streamed));
  }

  Future<dynamic> _decode(http.Response response) async {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    if (response.statusCode == 401) {
      await sl<AppSession>().logout();
      throw ApiException('Session expired. Please sign in again.');
    }

    final message = body is Map
        ? body.values.map((value) => value.toString()).join('\n')
        : 'Request failed with status ${response.statusCode}';
    throw ApiException(message);
  }
}

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  Future<void> login(String phoneNumber, String password) async {
    final data = await _api.post('/users/login/', {
      'phone_number': phoneNumber,
      'password': password,
    });
    await sl<AppSession>().saveTokens(data['access'], data['refresh']);
  }

  Future<void> register({
    required String phoneNumber,
    required String password,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    await _api.post('/users/register/', {
      'phone_number': phoneNumber,
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
    });
    await login(phoneNumber, password);
  }
}

class ConsentRepository {
  ConsentRepository(this._api);
  final ApiClient _api;

  Future<List<Agreement>> agreements() async {
    final data = await _api.get('/consents/agreements/') as List<dynamic>;
    return data.map((item) => Agreement.fromJson(item)).toList();
  }

  Future<Agreement> agreement(int id) async {
    return Agreement.fromJson(await _api.get('/consents/agreements/$id/'));
  }

  Future<int> currentUserId() async {
    final userData = await _api.get('/users/me/') as Map<String, dynamic>;
    return userData['id'];
  }

  Future<Agreement> createAgreement({
    required String participantPhone,
    required String title,
    required String terms,
    required int durationHours,
    DateTime? requestedExpiresAt,
  }) async {
    final data = await _api.post('/consents/agreements/', {
      'participant_phone_number': participantPhone,
      'title': title,
      'terms': terms,
      'duration_hours': durationHours,
      if (requestedExpiresAt != null)
        'requested_expires_at': requestedExpiresAt.toUtc().toIso8601String(),
    });
    return Agreement.fromJson(data);
  }

  Future<IdentityVerificationRecord> submitIdentity({
    required XFile selfie,
    required XFile governmentId,
    required String documentType,
    required String lastFour,
  }) async {
    final location = await currentLocationFields();
    final data = await _api.multipart(
      '/consents/identity-verifications/',
      fields: {
        'document_type': documentType,
        'document_last_four': lastFour,
        'device_info': jsonEncode({'platform': devicePlatform()}),
        ...location,
      },
      files: {'selfie_image': selfie, 'government_id_image': governmentId},
    );
    return IdentityVerificationRecord.fromJson(data);
  }

  Future<IdentityBadgeState> identityBadgeState() async {
    final userData = await _api.get('/users/me/') as Map<String, dynamic>;
    final isUserVerified = userData['is_identity_verified'] == true;
    final verificationData =
        await _api.get('/consents/identity-verifications/') as List<dynamic>;
    final latest = verificationData.isEmpty
        ? null
        : IdentityVerificationRecord.fromJson(
            Map<String, dynamic>.from(verificationData.first),
          );
    final status = isUserVerified
        ? 'VERIFIED'
        : latest?.status ?? 'NOT_SUBMITTED';

    return IdentityBadgeState(
      status: status,
      isVerified: isUserVerified || latest?.status == 'VERIFIED',
    );
  }

  Future<Agreement> sign(
    int id,
    String signatureText, {
    required XFile livePhoto,
  }) async {
    final location = await currentLocationFields();
    final data = await _api.multipart(
      '/consents/agreements/$id/sign/',
      fields: {
        'signature_text': signatureText,
        'device_info': jsonEncode({'platform': devicePlatform()}),
        ...location,
      },
      files: {'signature_image': livePhoto},
    );
    return Agreement.fromJson(data);
  }

  Future<Agreement> renew(
    int id,
    int? durationHours, {
    DateTime? requestedExpiresAt,
  }) async {
    return Agreement.fromJson(
      await _api.post('/consents/agreements/$id/renew/', {
        if (durationHours != null) 'duration_hours': durationHours,
        if (requestedExpiresAt != null)
          'requested_expires_at': requestedExpiresAt.toUtc().toIso8601String(),
      }),
    );
  }

  Future<Agreement> revoke(int id) async {
    return Agreement.fromJson(
      await _api.post('/consents/agreements/$id/revoke/', {}),
    );
  }

  Future<List<AuditEntry>> audit(int id) async {
    final data =
        await _api.get('/consents/agreements/$id/audit/') as List<dynamic>;
    return data.map((item) => AuditEntry.fromJson(item)).toList();
  }

  Future<void> downloadAgreementPdf(int id) async {
    final uri = _api.authenticatedUri('/consents/agreements/$id/download/');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw ApiException('Could not open agreement PDF.');
    }
  }
}

String devicePlatform() {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform.name;
}

Future<Map<String, String>> currentLocationFields() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return {'location_confirmed': 'false'};
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return {
      'latitude': position.latitude.toStringAsFixed(6),
      'longitude': position.longitude.toStringAsFixed(6),
      'location_confirmed': 'true',
    };
  } catch (_) {
    return {'location_confirmed': 'false'};
  }
}

class Agreement {
  Agreement({
    required this.id,
    required this.title,
    required this.terms,
    required this.status,
    required this.durationHours,
    this.creatorName,
    this.participantName,
    this.requestedExpiresAt,
    this.expiresAt,
    required this.signatures,
  });

  final int id;
  final String title;
  final String terms;
  final String status;
  final int durationHours;
  final String? creatorName;
  final String? participantName;
  final DateTime? requestedExpiresAt;
  final DateTime? expiresAt;
  final List<Map<String, dynamic>> signatures;

  factory Agreement.fromJson(Map<String, dynamic> json) {
    return Agreement(
      id: json['id'],
      title: json['title'] ?? '',
      terms: json['terms'] ?? '',
      status: json['status'] ?? '',
      durationHours: json['duration_hours'] ?? 24,
      creatorName: json['creator_name'],
      participantName: json['participant_name'],
      requestedExpiresAt: json['requested_expires_at'] == null
          ? null
          : DateTime.parse(json['requested_expires_at']),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at']),
      signatures: (json['signatures'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }
}

class AgreementDetailData {
  AgreementDetailData({required this.agreement, required this.currentUserId});

  final Agreement agreement;
  final int currentUserId;

  bool get currentUserHasSigned {
    return agreement.signatures.any((item) {
      final signer = item['signer'];
      if (signer is int) return signer == currentUserId;
      return signer?.toString() == currentUserId.toString();
    });
  }
}

class AuditEntry {
  AuditEntry({
    required this.action,
    required this.actor,
    required this.createdAt,
  });

  final String action;
  final String actor;
  final DateTime createdAt;

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      action: json['action'] ?? '',
      actor: json['actor_phone_number'] ?? 'System',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class IdentityVerificationRecord {
  IdentityVerificationRecord({required this.status});

  final String status;

  factory IdentityVerificationRecord.fromJson(Map<String, dynamic> json) {
    return IdentityVerificationRecord(status: json['status'] ?? 'PENDING');
  }
}

class IdentityBadgeState {
  IdentityBadgeState({required this.status, required this.isVerified});

  final String status;
  final bool isVerified;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      context.go('/agreements');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(child: Center(child: BrandMark()));
  }
}

class LocalTouchConsentScreen extends StatefulWidget {
  const LocalTouchConsentScreen({super.key});

  @override
  State<LocalTouchConsentScreen> createState() =>
      _LocalTouchConsentScreenState();
}

class _LocalTouchConsentScreenState extends State<LocalTouchConsentScreen>
    with TickerProviderStateMixin {
  late final AnimationController holdController;
  late final AnimationController pulseController;
  late final NearbyConsentTransport nearbyTransport;
  late Future<List<LocalConsentRecord>> historyFuture;
  final profileName = TextEditingController();
  final profileId = TextEditingController();
  LocalUserProfile? profile;
  String? incomingRequesterName;
  String requestState = 'idle';
  String nearbyStatus = 'Confirm identity to start nearby scanning.';
  bool nearbyPermissionRequired = false;
  bool nearbySetupIssue = false;
  bool nearbyScanning = false;
  List<NearbyPermissionRequirement> missingNearbyPermissions = [];

  @override
  void initState() {
    super.initState();
    holdController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1350),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) acceptRequest();
        });
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat(reverse: true);
    nearbyTransport = NearbyConsentTransport(
      onIncomingRequest: handleIncomingRequest,
      onStatusChanged: (message) {
        if (mounted) {
          final lowerMessage = message.toLowerCase();
          final setupIssue =
              lowerMessage.contains('could not') ||
              lowerMessage.contains('turn on') ||
              lowerMessage.contains('setup needs') ||
              lowerMessage.contains('phone build') ||
              lowerMessage.contains('build apk');
          setState(() {
            nearbyStatus = setupIssue
                ? 'Use the setup buttons below, then search again.'
                : message;
            nearbyPermissionRequired = false;
            nearbySetupIssue = setupIssue;
            nearbyScanning =
                !setupIssue &&
                (lowerMessage.contains('scanning') ||
                    lowerMessage.contains('nearby ready') ||
                    lowerMessage.contains('connected'));
          });
        }
      },
      onPermissionRequired: (message) {
        if (mounted) {
          setState(() {
            nearbyStatus = message;
            nearbyPermissionRequired = true;
            nearbySetupIssue = false;
            nearbyScanning = false;
          });
          refreshMissingPermissions();
        }
      },
    );
    historyFuture = sl<LocalConsentStore>().records();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestNearbyPermissionsOnOpen();
    });
    loadProfile();
  }

  Future<void> requestNearbyPermissionsOnOpen() async {
    await nearbyTransport.requestPermissionsOnOpen();
    final missing = await refreshMissingPermissions();
    if (!mounted) return;
    if (profile != null && missing.isEmpty && !nearbySetupIssue) {
      setState(() => nearbyStatus = 'Ready to search nearby devices.');
    }
  }

  Future<void> loadProfile() async {
    final savedProfile = await sl<LocalConsentStore>().profile();
    if (!mounted) return;
    setState(() => profile = savedProfile);
    if (savedProfile != null) {
      await prepareNearbyPage();
    }
  }

  @override
  void dispose() {
    holdController.dispose();
    pulseController.dispose();
    nearbyTransport.stop();
    profileName.dispose();
    profileId.dispose();
    super.dispose();
  }

  void handleIncomingRequest(String requesterName) {
    holdController.reset();
    setState(() {
      incomingRequesterName = cleanLocalPartyName(requesterName, 'Nearby user');
      requestState = 'incoming';
      nearbyStatus = 'Incoming consent request received.';
      nearbySetupIssue = false;
      nearbyScanning = false;
    });
  }

  void startHold() {
    if (requestState != 'incoming') return;
    holdController.forward(from: holdController.value);
  }

  void stopHold() {
    if (holdController.status == AnimationStatus.completed) return;
    holdController.reverse();
  }

  Future<void> acceptRequest() async {
    if (requestState == 'signed') return;
    final confirmedProfile = profile;
    final requesterName = incomingRequesterName;
    if (confirmedProfile == null || requesterName == null) return;
    await sl<LocalConsentStore>().saveDecision(
      requesterName: requesterName,
      holderName: confirmedProfile.name,
      accepted: true,
    );
    await nearbyTransport.sendDecision(true);
    if (!mounted) return;
    setState(() {
      requestState = 'signed';
      historyFuture = sl<LocalConsentStore>().records();
    });
    toast('Agreement signed locally.');
  }

  Future<void> cancelRequest() async {
    if (requestState != 'incoming') return;
    final confirmedProfile = profile;
    final requesterName = incomingRequesterName;
    if (confirmedProfile == null || requesterName == null) return;
    holdController.reset();
    await sl<LocalConsentStore>().saveDecision(
      requesterName: requesterName,
      holderName: confirmedProfile.name,
      accepted: false,
    );
    await nearbyTransport.sendDecision(false);
    if (!mounted) return;
    setState(() {
      requestState = 'cancelled';
      historyFuture = sl<LocalConsentStore>().records();
    });
    toast('Request cancelled.');
  }

  void resetIncoming() {
    holdController.reset();
    setState(() {
      requestState = 'idle';
      incomingRequesterName = null;
    });
  }

  Future<void> confirmLocalIdentity() async {
    final name = profileName.text.trim();
    final idNumber = profileId.text.trim();
    if (name.length < 2) {
      toast('Enter your full name.');
      return;
    }
    if (idNumber.length < 4) {
      toast('Enter a valid ID number.');
      return;
    }
    await sl<LocalConsentStore>().saveProfile(name: name, idNumber: idNumber);
    final savedProfile = await sl<LocalConsentStore>().profile();
    if (!mounted) return;
    setState(() => profile = savedProfile);
    if (savedProfile != null) {
      await prepareNearbyPage();
    }
  }

  Future<void> sendConsentRequest() async {
    final confirmedProfile = profile;
    if (confirmedProfile == null) return;
    await nearbyTransport.sendConsentRequest(confirmedProfile);
  }

  Future<void> enableNearbyPermissions() async {
    final confirmedProfile = profile;
    setState(() {
      nearbyStatus = 'Opening nearby permission request...';
      nearbyPermissionRequired = false;
      nearbySetupIssue = false;
      nearbyScanning = false;
    });
    await nearbyTransport.requestPermissionsOnOpen();
    final missing = await refreshMissingPermissions();
    if (!mounted) return;
    if (confirmedProfile != null && missing.isEmpty) {
      setState(() {
        nearbyStatus = 'Ready to search nearby devices.';
        nearbySetupIssue = false;
      });
    }
  }

  Future<void> retryNearbyScan() async {
    final confirmedProfile = profile;
    if (confirmedProfile == null) {
      setState(() {
        nearbyStatus = 'Confirm identity before scanning for nearby users.';
        nearbySetupIssue = false;
        nearbyScanning = false;
      });
      return;
    }
    final missing = await refreshMissingPermissions();
    if (missing.isNotEmpty) return;
    setState(() {
      nearbyStatus = 'Searching nearby devices...';
      nearbyPermissionRequired = false;
      nearbySetupIssue = false;
      nearbyScanning = true;
    });
    await nearbyTransport.start(confirmedProfile, requestPermissions: false);
    await refreshMissingPermissions();
  }

  Future<List<NearbyPermissionRequirement>> refreshMissingPermissions() async {
    final missing = await nearbyTransport.missingPermissionRequirements();
    if (!mounted) return missing;
    setState(() {
      missingNearbyPermissions = missing;
      nearbyPermissionRequired = missing.isNotEmpty;
      if (missing.isNotEmpty) {
        nearbyScanning = false;
        nearbySetupIssue = false;
        nearbyStatus =
            'Allow the required permissions below to scan for nearby users.';
      }
    });
    return missing;
  }

  Future<void> prepareNearbyPage() async {
    final missing = await refreshMissingPermissions();
    if (!mounted || missing.isNotEmpty) return;
    setState(() {
      nearbyStatus = 'Ready to search nearby devices.';
      nearbyPermissionRequired = false;
      nearbySetupIssue = false;
      nearbyScanning = false;
    });
  }

  Future<void> requestNearbyPermission(
    NearbyPermissionRequirement requirement,
  ) async {
    await nearbyTransport.requestPermission(requirement);
    final missing = await refreshMissingPermissions();
    if (!mounted) return;
    if (profile != null && missing.isEmpty) {
      setState(() {
        nearbyStatus = 'Ready to search nearby devices.';
        nearbyPermissionRequired = false;
        nearbySetupIssue = false;
        nearbyScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSigned = requestState == 'signed';
    final isCancelled = requestState == 'cancelled';
    final confirmedProfile = profile;
    if (confirmedProfile == null) {
      return _LocalIdentityConfirmationScreen(
        name: profileName,
        idNumber: profileId,
        onConfirm: confirmLocalIdentity,
        missingPermissions: missingNearbyPermissions,
        onEnablePermissions: enableNearbyPermissions,
        onRequestPermission: requestNearbyPermission,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -350) cancelRequest();
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scheme.surface,
                        scheme.primary.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                ),
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  Row(
                    children: [
                      const BrandMark(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Green Light Local',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const ThemeModeButton(),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _ConfirmedProfileHeader(profile: confirmedProfile),
                  const SizedBox(height: 34),
                  if (requestState == 'idle') ...[
                    _WaitingNearbyPanel(
                      status: nearbyStatus,
                      permissionRequired: nearbyPermissionRequired,
                      setupIssue: nearbySetupIssue,
                      missingPermissions: missingNearbyPermissions,
                      scanning: nearbyScanning,
                      onEnablePermissions: enableNearbyPermissions,
                      onRequestPermission: requestNearbyPermission,
                      onSearch: retryNearbyScan,
                      onOpenAppSettings: nearbyTransport.openAppPermissions,
                      onSendRequest: sendConsentRequest,
                    ),
                  ] else ...[
                    _IncomingRequestPill(
                      requester: incomingRequesterName ?? '',
                      pulse: pulseController,
                      state: requestState,
                    ),
                    const SizedBox(height: 22),
                    _TouchConsentPad(
                      holdController: holdController,
                      pulseController: pulseController,
                      enabled: requestState == 'incoming',
                      isSigned: isSigned,
                      isCancelled: isCancelled,
                      onPointerDown: startHold,
                      onPointerUp: stopHold,
                    ),
                    const SizedBox(height: 26),
                    _LocalPartiesPanel(
                      requesterName: incomingRequesterName ?? '',
                      holderName: confirmedProfile.name,
                    ),
                  ],
                  if (requestState != 'idle') ...[
                    const SizedBox(height: 18),
                    _LocalActionStrip(
                      state: requestState,
                      onReset: resetIncoming,
                      onCancel: cancelRequest,
                    ),
                  ],
                  const SizedBox(height: 18),
                  _LocalHistoryPanel(historyFuture: historyFuture),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncomingRequestPill extends StatelessWidget {
  const _IncomingRequestPill({
    required this.requester,
    required this.pulse,
    required this.state,
  });

  final String requester;
  final Animation<double> pulse;
  final String state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final requesterName = requester.trim().isEmpty
        ? 'User 1'
        : requester.trim();
    final title = state == 'incoming'
        ? 'Incoming consent request'
        : state == 'signed'
        ? 'Agreement signed'
        : 'Request cancelled';
    final subtitle = state == 'incoming'
        ? 'From $requesterName'
        : state == 'signed'
        ? 'Stored locally on this phone'
        : 'No agreement was created';
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final scale = state == 'incoming' ? 1 + (pulse.value * 0.08) : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              state == 'incoming'
                  ? Icons.sensors_rounded
                  : state == 'signed'
                  ? Icons.verified_rounded
                  : Icons.cancel_rounded,
              color: scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalIdentityConfirmationScreen extends StatelessWidget {
  const _LocalIdentityConfirmationScreen({
    required this.name,
    required this.idNumber,
    required this.onConfirm,
    required this.missingPermissions,
    required this.onEnablePermissions,
    required this.onRequestPermission,
  });

  final TextEditingController name;
  final TextEditingController idNumber;
  final VoidCallback onConfirm;
  final List<NearbyPermissionRequirement> missingPermissions;
  final VoidCallback onEnablePermissions;
  final ValueChanged<NearbyPermissionRequirement> onRequestPermission;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandMark(),
                    const SizedBox(height: 18),
                    Text(
                      'Confirm identity',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your confirmed name is used for local agreements.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: idNumber,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Government ID number',
                        prefixIcon: Icon(Icons.badge_rounded),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.verified_user_rounded),
                      label: const Text('Confirm identity'),
                    ),
                    if (missingPermissions.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Divider(),
                      const SizedBox(height: 10),
                      Text(
                        'Nearby permissions required',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final requirement in missingPermissions) ...[
                        _PermissionActionTile(
                          requirement: requirement,
                          onPressed: () => onRequestPermission(requirement),
                        ),
                        const SizedBox(height: 10),
                      ],
                      OutlinedButton.icon(
                        onPressed: onEnablePermissions,
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text('Allow all missing permissions'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmedProfileHeader extends StatelessWidget {
  const _ConfirmedProfileHeader({required this.profile});

  final LocalUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Confirmed ID ${profile.maskedId}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingNearbyPanel extends StatelessWidget {
  const _WaitingNearbyPanel({
    required this.status,
    required this.permissionRequired,
    required this.setupIssue,
    required this.missingPermissions,
    required this.scanning,
    required this.onEnablePermissions,
    required this.onRequestPermission,
    required this.onSearch,
    required this.onOpenAppSettings,
    required this.onSendRequest,
  });

  final String status;
  final bool permissionRequired;
  final bool setupIssue;
  final List<NearbyPermissionRequirement> missingPermissions;
  final bool scanning;
  final VoidCallback onEnablePermissions;
  final ValueChanged<NearbyPermissionRequirement> onRequestPermission;
  final VoidCallback onSearch;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onSendRequest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasIssue = permissionRequired || setupIssue;
    final title = permissionRequired
        ? 'Nearby permissions needed'
        : setupIssue
        ? 'Phone setup needed'
        : scanning
        ? 'Searching nearby devices'
        : 'Ready to search';
    final description = permissionRequired
        ? 'Allow the exact permissions below before scanning.'
        : setupIssue
        ? 'Turn on the required phone settings, then tap search again.'
        : scanning
        ? 'Keep both phones unlocked with Green Light open.'
        : 'Tap the green button when the nearby phone is open.';
    return SectionCard(
      child: Column(
        children: [
          Icon(
            hasIssue ? Icons.nearby_error_rounded : Icons.sensors_rounded,
            color: hasIssue ? scheme.error : scheme.primary,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hasIssue ? scheme.error : scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (!hasIssue && status.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              status,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (permissionRequired) ...[
            for (final requirement in missingPermissions) ...[
              _PermissionActionTile(
                requirement: requirement,
                onPressed: () => onRequestPermission(requirement),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: onEnablePermissions,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Allow all missing permissions'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onOpenAppSettings,
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Open app permissions'),
            ),
          ] else if (scanning) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: scheme.primary.withValues(alpha: 0.08),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Scanning nearby devices'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onSendRequest,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Start request with nearby user'),
            ),
          ] else ...[
            _RoundNearbySearchButton(onPressed: onSearch),
          ],
        ],
      ),
    );
  }
}

class _RoundNearbySearchButton extends StatelessWidget {
  const _RoundNearbySearchButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Tooltip(
          message: 'Search nearby device',
          child: Material(
            color: scheme.primary,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: scheme.primary.withValues(alpha: 0.35),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: 92,
                height: 92,
                child: Icon(
                  Icons.sensors_rounded,
                  size: 42,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Search nearby device',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _PermissionActionTile extends StatelessWidget {
  const _PermissionActionTile({
    required this.requirement,
    required this.onPressed,
  });

  final NearbyPermissionRequirement requirement;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_permissionIcon(requirement.id), color: scheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requirement.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  requirement.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: Icon(
                      requirement.needsSettings
                          ? Icons.settings_rounded
                          : Icons.lock_open_rounded,
                    ),
                    label: Text(
                      requirement.needsSettings
                          ? 'Open app settings'
                          : 'Allow ${requirement.label}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _permissionIcon(String id) {
    if (id.startsWith('bluetooth')) return Icons.bluetooth_rounded;
    if (id == 'location') return Icons.location_on_rounded;
    if (id == 'nearby_wifi') return Icons.wifi_rounded;
    return Icons.lock_open_rounded;
  }
}

class _TouchConsentPad extends StatelessWidget {
  const _TouchConsentPad({
    required this.holdController,
    required this.pulseController,
    required this.enabled,
    required this.isSigned,
    required this.isCancelled,
    required this.onPointerDown,
    required this.onPointerUp,
  });

  final Animation<double> holdController;
  final Animation<double> pulseController;
  final bool enabled;
  final bool isSigned;
  final bool isCancelled;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 0.82,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: scheme.outlineVariant, width: 2),
          color: Theme.of(context).cardTheme.color,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: pulseController,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    _PulseRing(
                      size: 220 + pulseController.value * 46,
                      opacity: enabled ? 0.18 : 0.06,
                    ),
                    _PulseRing(
                      size: 160 + pulseController.value * 34,
                      opacity: enabled ? 0.24 : 0.08,
                    ),
                  ],
                );
              },
            ),
            Listener(
              onPointerDown: (_) => onPointerDown(),
              onPointerUp: (_) => onPointerUp(),
              onPointerCancel: (_) => onPointerUp(),
              child: AnimatedBuilder(
                animation: holdController,
                builder: (context, _) {
                  final buttonColor = isCancelled
                      ? scheme.error
                      : isSigned
                      ? const Color(0xFF1976D2)
                      : scheme.primary;
                  return SizedBox(
                    width: 156,
                    height: 156,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 156,
                          height: 156,
                          child: CircularProgressIndicator(
                            value: holdController.value,
                            strokeWidth: 8,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: 126,
                          height: 126,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: buttonColor,
                            boxShadow: [
                              BoxShadow(
                                color: buttonColor.withValues(alpha: 0.32),
                                blurRadius: 30,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Icon(
                            isCancelled
                                ? Icons.close_rounded
                                : isSigned
                                ? Icons.check_rounded
                                : Icons.touch_app_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Text(
                enabled
                    ? 'Press and hold to accept · Swipe left to cancel'
                    : isSigned
                    ? 'Agreement is signed and stored on this phone'
                    : 'Request cancelled on this phone',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.primary.withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }
}

class _LocalPartiesPanel extends StatelessWidget {
  const _LocalPartiesPanel({
    required this.requesterName,
    required this.holderName,
  });

  final String requesterName;
  final String holderName;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          _ReadOnlyPartyRow(
            icon: Icons.person_add_alt_1_rounded,
            label: 'Request from',
            value: requesterName,
          ),
          const SizedBox(height: 12),
          _ReadOnlyPartyRow(
            icon: Icons.badge_rounded,
            label: 'Your name',
            value: holderName,
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyPartyRow extends StatelessWidget {
  const _ReadOnlyPartyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_rounded, size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _LocalActionStrip extends StatelessWidget {
  const _LocalActionStrip({
    required this.state,
    required this.onReset,
    required this.onCancel,
  });

  final String state;
  final VoidCallback onReset;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (state == 'incoming') {
      return OutlinedButton.icon(
        onPressed: onCancel,
        icon: const Icon(Icons.swipe_left_rounded),
        label: const Text('Swipe left or tap to cancel'),
      );
    }
    return FilledButton.icon(
      onPressed: onReset,
      icon: const Icon(Icons.restart_alt_rounded),
      label: const Text('New local request'),
    );
  }
}

class _LocalHistoryPanel extends StatelessWidget {
  const _LocalHistoryPanel({required this.historyFuture});

  final Future<List<LocalConsentRecord>> historyFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LocalConsentRecord>>(
      future: historyFuture,
      builder: (context, snapshot) {
        final records = snapshot.data ?? [];
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Local trail',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator()
              else if (records.isEmpty)
                const Text('No local agreements yet.')
              else
                for (final record in records.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      record.status == 'signed'
                          ? Icons.verified_rounded
                          : Icons.cancel_rounded,
                    ),
                    title: Text(
                      '${cleanLocalPartyName(record.requesterName, 'Nearby user')} -> '
                      '${cleanLocalPartyName(record.holderName, 'Confirmed user')}',
                    ),
                    subtitle: Text(
                      '${record.status.toUpperCase()} · ${DateFormat.MMMd().add_jm().format(record.createdAt)}',
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phone = TextEditingController();
  final password = TextEditingController();
  bool loading = false;

  Future<void> submit() async {
    setState(() => loading = true);
    try {
      await sl<AuthRepository>().login(phone.text.trim(), password.text);
      if (mounted) context.go('/agreements');
    } catch (error) {
      toast(error.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: AuthPanel(
        title: 'Green Light',
        subtitle: 'Because consent should be clear, mutual, and verifiable.',
        children: [
          TextField(
            controller: phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: loading ? null : submit,
            icon: const Icon(Icons.lock_open_rounded),
            label: Text(loading ? 'Signing in' : 'Sign in'),
          ),
          TextButton(
            onPressed: () => context.go('/register'),
            child: const Text('Create account'),
          ),
        ],
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  bool loading = false;

  Future<void> submit() async {
    setState(() => loading = true);
    try {
      await sl<AuthRepository>().register(
        phoneNumber: phone.text.trim(),
        password: password.text,
        firstName: firstName.text.trim(),
        lastName: lastName.text.trim(),
        email: email.text.trim(),
      );
      if (mounted) context.go('/verify');
    } catch (error) {
      toast(error.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: AuthPanel(
        title: 'Create account',
        subtitle:
            'Verified identity is required before agreements can be signed.',
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: firstName,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: lastName,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: email,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: loading ? null : submit,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(loading ? 'Creating' : 'Create account'),
          ),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }
}

class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  final lastFour = TextEditingController();
  final picker = ImagePicker();
  XFile? selfie;
  XFile? governmentId;
  String documentType = 'NATIONAL_ID';
  bool loading = false;

  Future<void> pickSelfie() async {
    final image = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (image != null) setState(() => selfie = image);
  }

  Future<void> pickGovernmentId() async {
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) setState(() => governmentId = image);
  }

  Future<void> submit() async {
    if (selfie == null || governmentId == null) {
      toast('Selfie and government ID are required.');
      return;
    }
    setState(() => loading = true);
    try {
      final verification = await sl<ConsentRepository>().submitIdentity(
        selfie: selfie!,
        governmentId: governmentId!,
        documentType: documentType,
        lastFour: lastFour.text.trim(),
      );
      toast(
        verification.status == 'VERIFIED'
            ? 'Identity verified.'
            : 'Identity verification submitted.',
      );
      if (mounted) context.go('/agreements');
    } catch (error) {
      toast(error.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: const GreenLightAppBar(title: 'Identity'),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verification',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: documentType,
                  items: const [
                    DropdownMenuItem(
                      value: 'NATIONAL_ID',
                      child: Text('National ID'),
                    ),
                    DropdownMenuItem(
                      value: 'PASSPORT',
                      child: Text('Passport'),
                    ),
                    DropdownMenuItem(
                      value: 'DRIVING_LICENSE',
                      child: Text('Driving license'),
                    ),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                  ],
                  onChanged: (value) =>
                      setState(() => documentType = value ?? 'NATIONAL_ID'),
                  decoration: const InputDecoration(labelText: 'Document type'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastFour,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Document last four',
                  ),
                ),
                const SizedBox(height: 8),
                PickTile(
                  icon: Icons.face_retouching_natural_rounded,
                  title: 'Live selfie',
                  selected: selfie != null,
                  onTap: pickSelfie,
                ),
                const SizedBox(height: 10),
                PickTile(
                  icon: Icons.badge_rounded,
                  title: 'Government ID',
                  selected: governmentId != null,
                  onTap: pickGovernmentId,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: loading ? null : submit,
                  icon: const Icon(Icons.verified_user_rounded),
                  label: Text(loading ? 'Submitting' : 'Submit verification'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AgreementListScreen extends StatefulWidget {
  const AgreementListScreen({super.key});

  @override
  State<AgreementListScreen> createState() => _AgreementListScreenState();
}

class _AgreementListScreenState extends State<AgreementListScreen> {
  late Future<List<Agreement>> future;
  late Future<IdentityBadgeState> identityFuture;

  @override
  void initState() {
    super.initState();
    future = sl<ConsentRepository>().agreements();
    identityFuture = sl<ConsentRepository>().identityBadgeState();
  }

  void reload() {
    setState(() {
      future = sl<ConsentRepository>().agreements();
      identityFuture = sl<ConsentRepository>().identityBadgeState();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: GreenLightAppBar(
        title: 'Agreements',
        actions: [
          FutureBuilder<IdentityBadgeState>(
            future: identityFuture,
            builder: (context, snapshot) {
              final identity = snapshot.data;
              final isVerified = identity?.isVerified == true;
              return VerifiedIdentityButton(
                isVerified: isVerified,
                onPressed: () => context.go('/verify'),
              );
            },
          ),
          const ThemeModeButton(),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => sl<AppSession>().logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      child: FutureBuilder<List<Agreement>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.warning_amber_rounded,
              title: 'Unable to load agreements',
              action: reload,
            );
          }
          final agreements = snapshot.data ?? [];
          if (agreements.isEmpty) {
            return EmptyState(
              icon: Icons.assignment_turned_in_rounded,
              title: 'No agreements yet',
              action: () => context.go('/new'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: agreements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = agreements[index];
              return AgreementTile(
                agreement: item,
                onTap: () => context.go('/agreements/${item.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

class NewAgreementScreen extends StatefulWidget {
  const NewAgreementScreen({super.key});

  @override
  State<NewAgreementScreen> createState() => _NewAgreementScreenState();
}

class _NewAgreementScreenState extends State<NewAgreementScreen> {
  final participantPhone = TextEditingController();
  final title = TextEditingController(text: 'Mutual Consent Agreement');
  final terms = TextEditingController();
  int durationHours = 24;
  int selectedPresetHours = 24;
  DateTime requestedExpiresAt = DateTime.now().add(const Duration(hours: 24));
  bool loading = false;

  void setPreset(int hours) {
    setState(() {
      durationHours = hours;
      selectedPresetHours = hours;
      requestedExpiresAt = DateTime.now().add(Duration(hours: hours));
    });
  }

  Future<void> pickExpirationDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: requestedExpiresAt,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(requestedExpiresAt),
    );
    if (time == null) return;
    setState(() {
      requestedExpiresAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      durationHours = requestedExpiresAt.difference(now).inHours.clamp(1, 8760);
      selectedPresetHours = 0;
    });
  }

  Future<void> submit() async {
    setState(() => loading = true);
    try {
      final agreement = await sl<ConsentRepository>().createAgreement(
        participantPhone: participantPhone.text.trim(),
        title: title.text.trim(),
        terms: terms.text.trim(),
        durationHours: durationHours,
        requestedExpiresAt: requestedExpiresAt,
      );
      if (mounted) context.go('/agreements/${agreement.id}');
    } catch (error) {
      toast(error.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: const GreenLightAppBar(title: 'New agreement'),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: participantPhone,
            decoration: const InputDecoration(
              labelText: 'Participant phone number',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: terms,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(labelText: 'Agreement terms'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 24,
                label: Text('24h'),
                icon: Icon(Icons.today_rounded),
              ),
              ButtonSegment(
                value: 168,
                label: Text('7d'),
                icon: Icon(Icons.date_range_rounded),
              ),
              ButtonSegment(
                value: 720,
                label: Text('30d'),
                icon: Icon(Icons.event_available_rounded),
              ),
              ButtonSegment(
                value: 0,
                label: Text('Custom'),
                icon: Icon(Icons.edit_calendar_rounded),
              ),
            ],
            selected: {selectedPresetHours},
            onSelectionChanged: (value) {
              if (value.first == 0) {
                pickExpirationDate();
              } else {
                setPreset(value.first);
              }
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: const Icon(Icons.event_available_rounded),
            title: const Text('Expiration date'),
            subtitle: Text(
              DateFormat.yMMMd().add_jm().format(requestedExpiresAt),
            ),
            trailing: const Icon(Icons.edit_calendar_rounded),
            onTap: pickExpirationDate,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: loading ? null : submit,
            icon: const Icon(Icons.send_rounded),
            label: Text(loading ? 'Creating' : 'Create agreement'),
          ),
        ],
      ),
    );
  }
}

Future<DateTime?> pickAgreementExpirationDate(
  BuildContext context,
  DateTime initial,
) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(now)
        ? now.add(const Duration(hours: 1))
        : initial,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class AgreementDetailScreen extends StatefulWidget {
  const AgreementDetailScreen({required this.agreementId, super.key});
  final int agreementId;

  @override
  State<AgreementDetailScreen> createState() => _AgreementDetailScreenState();
}

class _AgreementDetailScreenState extends State<AgreementDetailScreen> {
  late Future<AgreementDetailData> future;
  final signature = TextEditingController();
  final picker = ImagePicker();
  XFile? signingPhoto;
  bool signedLocally = false;

  @override
  void initState() {
    super.initState();
    future = loadAgreementDetail();
  }

  Future<AgreementDetailData> loadAgreementDetail() async {
    final repository = sl<ConsentRepository>();
    final results = await Future.wait<dynamic>([
      repository.agreement(widget.agreementId),
      repository.currentUserId(),
    ]);
    return AgreementDetailData(
      agreement: results[0] as Agreement,
      currentUserId: results[1] as int,
    );
  }

  void reload() {
    setState(() => future = loadAgreementDetail());
  }

  Future<XFile?> pickSigningPhoto() async {
    final image = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (image != null) {
      setState(() => signingPhoto = image);
    }
    return image;
  }

  Future<void> sign() async {
    final signatureText = signature.text.trim();
    if (signatureText.isEmpty) {
      toast('Enter your signature name.');
      return;
    }
    var livePhoto = signingPhoto;
    livePhoto ??= await pickSigningPhoto();
    if (livePhoto == null) {
      toast('Live signing photo is required.');
      return;
    }
    try {
      await sl<ConsentRepository>().sign(
        widget.agreementId,
        signatureText,
        livePhoto: livePhoto,
      );
      setState(() {
        signedLocally = true;
        signingPhoto = null;
        signature.clear();
        future = loadAgreementDetail();
      });
    } catch (error) {
      toast(error.toString());
    }
  }

  int renewalDurationHours(Agreement agreement) {
    const allowedDurations = {24, 168, 720};
    return allowedDurations.contains(agreement.durationHours)
        ? agreement.durationHours
        : 24;
  }

  Future<void> renew(Agreement agreement) async {
    try {
      final renewed = await sl<ConsentRepository>().renew(
        widget.agreementId,
        renewalDurationHours(agreement),
      );
      if (mounted) context.go('/agreements/${renewed.id}');
    } catch (error) {
      toast(error.toString());
    }
  }

  Future<void> revoke() async {
    try {
      await sl<ConsentRepository>().revoke(widget.agreementId);
      reload();
    } catch (error) {
      toast(error.toString());
    }
  }

  Future<void> downloadPdf() async {
    try {
      await sl<ConsentRepository>().downloadAgreementPdf(widget.agreementId);
    } catch (error) {
      toast(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: const GreenLightAppBar(title: 'Agreement'),
      child: FutureBuilder<AgreementDetailData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return EmptyState(
              icon: Icons.warning_rounded,
              title: 'Agreement unavailable',
              action: reload,
            );
          }
          final detail = snapshot.data!;
          final agreement = detail.agreement;
          final canSign =
              agreement.status == 'PENDING_SIGNATURES' &&
              !detail.currentUserHasSigned &&
              !signedLocally;
          final canRevoke = agreement.status == 'ACTIVE';
          final canRenew =
              agreement.status == 'EXPIRED' || agreement.status == 'REVOKED';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              LegalAgreementDocument(agreement: agreement),
              const SizedBox(height: 14),
              if (canSign) ...[
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sign Agreement',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      for (final item in agreement.signatures)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.draw_rounded),
                          title: Text(_signatureTitle(item)),
                          subtitle: Text(item['signed_at'] ?? ''),
                        ),
                      TextField(
                        controller: signature,
                        decoration: const InputDecoration(
                          labelText: 'Signature name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      PickTile(
                        icon: Icons.face_retouching_natural_rounded,
                        title: 'Live signing photo',
                        selected: signingPhoto != null,
                        onTap: () => pickSigningPhoto(),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: sign,
                        icon: const Icon(Icons.verified_user_rounded),
                        label: const Text('Confirm and sign'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              FilledButton.icon(
                onPressed: downloadPdf,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download PDF'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canRevoke ? revoke : null,
                      icon: const Icon(Icons.block_rounded),
                      label: const Text('Revoke'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canRenew ? () => renew(agreement) : null,
                      icon: const Icon(Icons.autorenew_rounded),
                      label: const Text('Renew'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AuditPanel(agreementId: agreement.id),
            ],
          );
        },
      ),
    );
  }
}

class LegalAgreementDocument extends StatelessWidget {
  const LegalAgreementDocument({required this.agreement, super.key});

  final Agreement agreement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expiry = agreement.expiresAt ?? agreement.requestedExpiresAt;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  'GREEN LIGHT',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 0,
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'MUTUAL CONSENT AGREEMENT',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                StatusPill(status: agreement.status),
              ],
            ),
          ),
          const Divider(height: 34),
          ContractMetaGrid(
            rows: [
              ('Agreement ID', 'GL-${agreement.id.toString().padLeft(6, '0')}'),
              ('Created', 'Recorded in secure audit history'),
              (
                'Expires',
                expiry == null
                    ? 'Pending activation'
                    : DateFormat.yMMMMd().add_jm().format(expiry.toLocal()),
              ),
              ('Validity', agreement.status.replaceAll('_', ' ')),
            ],
          ),
          const SizedBox(height: 20),
          ContractSection(
            title: 'Participants',
            child: Column(
              children: [
                ContractLine(
                  label: 'Party A',
                  value: agreement.creatorName?.isNotEmpty == true
                      ? agreement.creatorName!
                      : 'Verified creator',
                ),
                ContractLine(
                  label: 'Party B',
                  value: agreement.participantName?.isNotEmpty == true
                      ? agreement.participantName!
                      : 'Verified participant',
                ),
                const ContractLine(
                  label: 'Verification',
                  value:
                      'Identity, device, and location confirmations are recorded in the audit trail.',
                ),
              ],
            ),
          ),
          ContractSection(
            title: 'Agreement Terms',
            child: Text(
              agreement.terms,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
          ),
          ContractSection(
            title: 'Digital Signatures',
            child: agreement.signatures.isEmpty
                ? const Text('Signatures are pending.')
                : Column(
                    children: [
                      for (final item in agreement.signatures)
                        ContractLine(
                          label: _signatureTitle(item),
                          value:
                              'Signed ${formatApiDate(item['signed_at'])}; Location ${item['location_confirmed'] == true ? 'confirmed' : 'not confirmed'}',
                        ),
                    ],
                  ),
          ),
          Text(
            'This document is generated by Green Light and reflects the recorded consent status at the time of viewing.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class ContractSection extends StatelessWidget {
  const ContractSection({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class ContractMetaGrid extends StatelessWidget {
  const ContractMetaGrid({required this.rows, super.key});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final row in rows)
          SizedBox(
            width: 240,
            child: ContractLine(label: row.$1, value: row.$2),
          ),
      ],
    );
  }
}

class ContractLine extends StatelessWidget {
  const ContractLine({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String formatApiDate(dynamic value) {
  if (value == null || value.toString().isEmpty) return 'time unavailable';
  try {
    return DateFormat.yMMMd().add_jm().format(DateTime.parse(value).toLocal());
  } catch (_) {
    return value.toString();
  }
}

String _signatureTitle(Map<String, dynamic> item) {
  final name = item['signer_name']?.toString() ?? '';
  if (name.isNotEmpty) return name;
  return item['signer_phone_number']?.toString() ?? 'Signer';
}

class AuditPanel extends StatelessWidget {
  const AuditPanel({required this.agreementId, super.key});
  final int agreementId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AuditEntry>>(
      future: sl<ConsentRepository>().audit(agreementId),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? [];
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audit trail',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator()
              else if (entries.isEmpty)
                const Text('No activity yet')
              else
                for (final entry in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history_rounded),
                    title: Text(entry.action.replaceAll('_', ' ')),
                    subtitle: Text(
                      '${entry.actor} · ${DateFormat.MMMd().add_jm().format(entry.createdAt.toLocal())}',
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.child,
    this.appBar,
    this.floatingActionButton,
    super.key,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: SafeArea(child: child),
    );
  }
}

class GreenLightAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GreenLightAppBar({required this.title, this.actions, super.key});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: Text(title), actions: actions, centerTitle: false);
  }
}

class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: sl<AppThemeController>(),
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return IconButton(
          tooltip: isDark ? 'Light mode' : 'Dark mode',
          onPressed: sl<AppThemeController>().toggle,
          icon: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          ),
        );
      },
    );
  }
}

class VerifiedIdentityButton extends StatelessWidget {
  const VerifiedIdentityButton({
    required this.isVerified,
    required this.onPressed,
    super.key,
  });

  final bool isVerified;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const verifiedBlue = Color(0xFF1976D2);
    final scheme = Theme.of(context).colorScheme;
    final color = isVerified ? verifiedBlue : scheme.onSurfaceVariant;

    return IconButton(
      tooltip: isVerified ? 'Identity verified' : 'Verify identity',
      onPressed: onPressed,
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isVerified
              ? verifiedBlue.withValues(alpha: 0.12)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isVerified
                ? verifiedBlue.withValues(alpha: 0.45)
                : scheme.outlineVariant,
          ),
        ),
        child: Icon(
          isVerified ? Icons.verified_rounded : Icons.verified_outlined,
          color: color,
          size: 20,
        ),
      ),
    );
  }
}

class AuthPanel extends StatelessWidget {
  const AuthPanel({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SectionCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BrandMark(),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(subtitle, textAlign: TextAlign.center),
                const SizedBox(height: 22),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 42),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class PickTile extends StatelessWidget {
  const PickTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      tileColor: scheme.surfaceContainerHighest.withValues(alpha: 0.48),
      leading: Icon(icon, color: selected ? scheme.primary : scheme.secondary),
      title: Text(title),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}

class AgreementTile extends StatelessWidget {
  const AgreementTile({
    required this.agreement,
    required this.onTap,
    super.key,
  });

  final Agreement agreement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.assignment_rounded,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agreement.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    agreement.participantName ?? 'Waiting for participant',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            StatusPill(status: agreement.status),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final active = status == 'ACTIVE';
    final expired = status == 'EXPIRED' || status == 'REVOKED';
    final color = active
        ? Theme.of(context).colorScheme.primary
        : expired
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: action, child: const Text('Continue')),
          ],
        ),
      ),
    );
  }
}

void toast(String message) {
  Fluttertoast.showToast(msg: message);
}
