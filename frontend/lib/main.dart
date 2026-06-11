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
      redirect: (context, state) {
        final loggedIn = session.isLoggedIn;
        final publicPath =
            state.matchedLocation == '/login' ||
            state.matchedLocation == '/register';
        if (!loggedIn && !publicPath) return '/login';
        if (loggedIn && publicPath) return '/agreements';
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
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
    defaultValue: 'http://127.0.0.1:8000/api',
  );
}

class AppStorage {
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

  Future<Agreement> sign(int id, String signatureText) async {
    final location = await currentLocationFields();
    final data = await _api.multipart(
      '/consents/agreements/$id/sign/',
      fields: {
        'signature_text': signatureText,
        'device_info': jsonEncode({'platform': devicePlatform()}),
        ...location,
      },
      files: <String, XFile>{},
    );
    return Agreement.fromJson(data);
  }

  Future<Agreement> renew(int id, int durationHours, {DateTime? requestedExpiresAt}) async {
    return Agreement.fromJson(
      await _api.post('/consents/agreements/$id/renew/', {
        'duration_hours': durationHours,
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
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at']),
      signatures: (json['signatures'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
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
  bool loading = false;

  Future<void> submit() async {
    setState(() => loading = true);
    try {
      final agreement = await sl<ConsentRepository>().createAgreement(
        participantPhone: participantPhone.text.trim(),
        title: title.text.trim(),
        terms: terms.text.trim(),
        durationHours: durationHours,
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
            ],
            selected: {durationHours},
            onSelectionChanged: (value) =>
                setState(() => durationHours = value.first),
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

class AgreementDetailScreen extends StatefulWidget {
  const AgreementDetailScreen({required this.agreementId, super.key});
  final int agreementId;

  @override
  State<AgreementDetailScreen> createState() => _AgreementDetailScreenState();
}

class _AgreementDetailScreenState extends State<AgreementDetailScreen> {
  late Future<Agreement> future;
  final signature = TextEditingController();

  @override
  void initState() {
    super.initState();
    future = sl<ConsentRepository>().agreement(widget.agreementId);
  }

  void reload() {
    setState(
      () => future = sl<ConsentRepository>().agreement(widget.agreementId),
    );
  }

  Future<void> sign() async {
    try {
      await sl<ConsentRepository>().sign(
        widget.agreementId,
        signature.text.trim(),
      );
      signature.clear();
      reload();
    } catch (error) {
      toast(error.toString());
    }
  }

  Future<void> renew(int hours) async {
    try {
      final renewed = await sl<ConsentRepository>().renew(
        widget.agreementId,
        hours,
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: const GreenLightAppBar(title: 'Agreement'),
      child: FutureBuilder<Agreement>(
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
          final agreement = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            agreement.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        StatusPill(status: agreement.status),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${agreement.creatorName ?? 'Creator'} and ${agreement.participantName ?? 'Participant'}',
                    ),
                    if (agreement.expiresAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Expires ${DateFormat.yMMMd().add_jm().format(agreement.expiresAt!.toLocal())}',
                      ),
                    ],
                    const Divider(height: 28),
                    Text(agreement.terms),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signatures',
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
                    FilledButton.icon(
                      onPressed: sign,
                      icon: const Icon(Icons.edit_document),
                      label: const Text('Sign agreement'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: revoke,
                      icon: const Icon(Icons.block_rounded),
                      label: const Text('Revoke'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => renew(agreement.durationHours),
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
