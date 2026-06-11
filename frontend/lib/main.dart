import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sl = GetIt.instance;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = AppStorage();
  await storage.init();
  sl.registerSingleton<AppStorage>(storage);
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

    return MaterialApp.router(
      title: 'Green Light',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E8A5A),
          primary: const Color(0xFF14764A),
          secondary: const Color(0xFF28527A),
          tertiary: const Color(0xFFE7A928),
          surface: const Color(0xFFF8FAF8),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAF8),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
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

  Future<void> saveTokens(String access, String refresh) async {
    await _prefs.setString('access_token', access);
    await _prefs.setString('refresh_token', refresh);
  }

  Future<void> clear() async {
    await _prefs.remove('access_token');
    await _prefs.remove('refresh_token');
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

  Future<dynamic> get(String endpoint) async {
    final response = await http
        .get(Uri.parse('${ApiUrls.baseUrl}$endpoint'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse('${ApiUrls.baseUrl}$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(response);
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
    return _decode(await http.Response.fromStream(streamed));
  }

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
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
  }) async {
    final data = await _api.post('/consents/agreements/', {
      'participant_phone_number': participantPhone,
      'title': title,
      'terms': terms,
      'duration_hours': durationHours,
    });
    return Agreement.fromJson(data);
  }

  Future<void> submitIdentity({
    required XFile selfie,
    required XFile governmentId,
    required String documentType,
    required String lastFour,
  }) async {
    await _api.multipart(
      '/consents/identity-verifications/',
      fields: {
        'document_type': documentType,
        'document_last_four': lastFour,
        'device_info': jsonEncode({'platform': devicePlatform()}),
      },
      files: {'selfie_image': selfie, 'government_id_image': governmentId},
    );
  }

  Future<Agreement> sign(int id, String signatureText) async {
    final data = await _api.multipart(
      '/consents/agreements/$id/sign/',
      fields: {
        'signature_text': signatureText,
        'device_info': jsonEncode({'platform': devicePlatform()}),
      },
      files: <String, XFile>{},
    );
    return Agreement.fromJson(data);
  }

  Future<Agreement> renew(int id, int durationHours) async {
    return Agreement.fromJson(
      await _api.post('/consents/agreements/$id/renew/', {
        'duration_hours': durationHours,
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
}

String devicePlatform() {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform.name;
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
      await sl<ConsentRepository>().submitIdentity(
        selfie: selfie!,
        governmentId: governmentId!,
        documentType: documentType,
        lastFour: lastFour.text.trim(),
      );
      toast('Identity verification submitted.');
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

  @override
  void initState() {
    super.initState();
    future = sl<ConsentRepository>().agreements();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: GreenLightAppBar(
        title: 'Agreements',
        actions: [
          IconButton(
            tooltip: 'Verify identity',
            onPressed: () => context.go('/verify'),
            icon: const Icon(Icons.verified_rounded),
          ),
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
              action: () =>
                  setState(() => future = sl<ConsentRepository>().agreements()),
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
          color: Theme.of(context).colorScheme.primary,
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
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
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: Colors.white,
      leading: Icon(icon),
      title: Text(title),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
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
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.assignment_rounded),
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
