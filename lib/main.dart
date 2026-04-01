import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_fonts/google_fonts.dart';
import 'services/order_service.dart';
import 'services/user_session_service.dart';
import 'views/auth/login_screen.dart';
import 'views/auth/register_screen.dart';
import 'views/main/main_navigation.dart';

const bool kBypassLogin = bool.fromEnvironment(
  'BYPASS_LOGIN',
  defaultValue: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;

  // Khởi tạo Firebase: trên web cần truyền FirebaseOptions
  try {
    if (kIsWeb) {
      // Cấu hình Web App từ Firebase Console (đã cung cấp)
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyCLlnY29C7EVjOw-eW5hziZ0N-y_vkZjv8',
          authDomain: 'unisend-n4-ptud-ck.firebaseapp.com',
          projectId: 'unisend-n4-ptud-ck',
          storageBucket: 'unisend-n4-ptud-ck.firebasestorage.app',
          messagingSenderId: '1088634361868',
          appId: '1:1088634361868:web:dfca21a76007d87f13b629',
          measurementId: 'G-VZM64B75R2',
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase init failed, running in UI-only mode: $e');
  }

  try {
    await Supabase.initialize(
      url: 'https://tsnitkxrditmobzhjzme.supabase.co',
      anonKey: 'sb_publishable_A4YYuzcJqwGuo1CQkX8AMA_CkuikmKM',
    );
  } catch (e) {
    debugPrint('Supabase init failed, continue with local UI: $e');
  }

  runApp(MainApp(firebaseReady: firebaseReady));
}

class MainApp extends StatefulWidget {
  const MainApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  fb.FirebaseAuth? _auth;
  ThemeMode _themeMode = ThemeMode.light;
  late final UserSessionService _userSessionService;
  late final OrderService _orderService;

  @override
  void initState() {
    super.initState();
    if (widget.firebaseReady) {
      _auth = fb.FirebaseAuth.instance;
    }
    _userSessionService = UserSessionService(
      initialUserId: _resolveInitialUserId(),
    );
    _orderService = OrderService();
  }

  String _resolveInitialUserId() {
    final firebaseUserId = _auth?.currentUser?.uid;
    if (firebaseUserId != null && firebaseUserId.trim().isNotEmpty) {
      return firebaseUserId.trim();
    }
    return 'local_user';
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: brightness,
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }

  void _onThemeModeChanged(bool isDarkMode) {
    setState(() {
      _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shouldBypassAuth = kBypassLogin || !widget.firebaseReady;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      routes: {
        '/login': (c) => shouldBypassAuth
            ? MainNavigation(
                isDarkMode: _themeMode == ThemeMode.dark,
                onThemeModeChanged: _onThemeModeChanged,
                orderService: _orderService,
                userSessionService: _userSessionService,
              )
            : LoginScreen(onSignedIn: () => setState(() {})),
        '/register': (c) => shouldBypassAuth
            ? MainNavigation(
                isDarkMode: _themeMode == ThemeMode.dark,
                onThemeModeChanged: _onThemeModeChanged,
                orderService: _orderService,
                userSessionService: _userSessionService,
              )
            : const RegisterScreen(),
      },
      home: shouldBypassAuth
          ? MainNavigation(
              isDarkMode: _themeMode == ThemeMode.dark,
              onThemeModeChanged: _onThemeModeChanged,
              orderService: _orderService,
              userSessionService: _userSessionService,
            )
          : StreamBuilder<fb.User?>(
              stream: _auth!.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasData) {
                  _userSessionService.setCurrentUserId(snapshot.data!.uid);
                  return MainNavigation(
                    isDarkMode: _themeMode == ThemeMode.dark,
                    onThemeModeChanged: _onThemeModeChanged,
                    orderService: _orderService,
                    userSessionService: _userSessionService,
                  );
                }
                return LoginScreen(onSignedIn: () => setState(() {}));
              },
            ),
    );
  }
}
