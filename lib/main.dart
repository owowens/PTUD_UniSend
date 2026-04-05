import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'providers/order_provider.dart';
import 'services/chat_service.dart';
import 'services/order_service.dart';
import 'services/user_session_service.dart';
import 'widgets/common/app_logo.dart';
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
  String? firebaseInitError;

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
    firebaseInitError = e.toString();
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

  runApp(
    MainApp(firebaseReady: firebaseReady, firebaseInitError: firebaseInitError),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({
    super.key,
    required this.firebaseReady,
    this.firebaseInitError,
  });

  final bool firebaseReady;
  final String? firebaseInitError;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  fb.FirebaseAuth? _auth;
  ThemeMode _themeMode = ThemeMode.light;
  Timer? _welcomeTimer;
  bool _showWelcomeSplash = true;
  late final UserSessionService _userSessionService;
  late final OrderService _orderService;
  late final ChatService _chatService;
  late final OrderProvider _orderProvider;
  late final ChatProvider _chatProvider;

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
    _chatService = ChatService();
    _orderProvider = OrderProvider(
      orderService: _orderService,
      userSessionService: _userSessionService,
    );
    _chatProvider = ChatProvider(
      chatService: _chatService,
      userSessionService: _userSessionService,
    );

    _welcomeTimer = Timer(const Duration(milliseconds: 5000), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showWelcomeSplash = false;
      });
    });
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    _chatProvider.dispose();
    _orderProvider.dispose();
    _userSessionService.dispose();
    super.dispose();
  }

  String _resolveInitialUserId() {
    final firebaseUserId = _auth?.currentUser?.uid;
    if (firebaseUserId != null && firebaseUserId.trim().isNotEmpty) {
      return firebaseUserId.trim();
    }
    return 'local_user';
  }

  ThemeData _buildTheme(Brightness brightness) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F4C5C),
      brightness: brightness,
    );

    final colorScheme = brightness == Brightness.light
        ? baseScheme.copyWith(
            primary: const Color(0xFF0F4C5C),
            onPrimary: const Color(0xFFFFFFFF),
            primaryContainer: const Color(0xFFCFE7EA),
            onPrimaryContainer: const Color(0xFF0B2D36),
            secondary: const Color(0xFFF7B267),
            onSecondary: const Color(0xFF3A2200),
            secondaryContainer: const Color(0xFFFFE3C7),
            onSecondaryContainer: const Color(0xFF5B3700),
            tertiary: const Color(0xFF3D5A80),
            onTertiary: const Color(0xFFFFFFFF),
            tertiaryContainer: const Color(0xFFD7E3F4),
            onTertiaryContainer: const Color(0xFF1E2E4A),
            error: const Color(0xFFB42318),
            onError: const Color(0xFFFFFFFF),
            errorContainer: const Color(0xFFFFDAD6),
            onErrorContainer: const Color(0xFF410002),
            surface: const Color(0xFFF7F4EF),
            onSurface: const Color(0xFF1F1B16),
            surfaceContainerHighest: const Color(0xFFEAE2D6),
            onSurfaceVariant: const Color(0xFF4C463D),
            outline: const Color(0xFF8A8378),
            outlineVariant: const Color(0xFFD4CBBE),
            inverseSurface: const Color(0xFF34302A),
            onInverseSurface: const Color(0xFFF3EEE6),
            inversePrimary: const Color(0xFF8BD3DD),
          )
        : baseScheme.copyWith(
            primary: const Color(0xFF8BD3DD),
            onPrimary: const Color(0xFF00363F),
            primaryContainer: const Color(0xFF0B4A55),
            onPrimaryContainer: const Color(0xFFCFE7EA),
            secondary: const Color(0xFFF7B267),
            onSecondary: const Color(0xFF3A2200),
            secondaryContainer: const Color(0xFF5B3700),
            onSecondaryContainer: const Color(0xFFFFE3C7),
            tertiary: const Color(0xFFB8C7E6),
            onTertiary: const Color(0xFF1E2E4A),
            tertiaryContainer: const Color(0xFF2B3E5C),
            onTertiaryContainer: const Color(0xFFD7E3F4),
            error: const Color(0xFFFFB4AB),
            onError: const Color(0xFF690005),
            errorContainer: const Color(0xFF93000A),
            onErrorContainer: const Color(0xFFFFDAD6),
            surface: const Color(0xFF121413),
            onSurface: const Color(0xFFE7E2D9),
            surfaceContainerHighest: const Color(0xFF2A2E2C),
            onSurfaceVariant: const Color(0xFFCAC5BC),
            outline: const Color(0xFF948F86),
            outlineVariant: const Color(0xFF444841),
            inverseSurface: const Color(0xFFE7E2D9),
            onInverseSurface: const Color(0xFF2B2A27),
            inversePrimary: const Color(0xFF0F4C5C),
          );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
    );

    return base.copyWith(
      textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0.6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withAlpha(120),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: colorScheme.outlineVariant),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    final shouldBypassAuth = kBypassLogin;

    if (!widget.firebaseReady && !shouldBypassAuth) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: _themeMode,
        home: _FirebaseConfigErrorScreen(
          errorMessage:
              widget.firebaseInitError ??
              'Firebase chưa khởi tạo được. Kiểm tra cấu hình Android/iOS/Web.',
        ),
      );
    }

    if (_showWelcomeSplash) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: _themeMode,
        home: const _WelcomeSplashScreen(),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UserSessionService>.value(
          value: _userSessionService,
        ),
        Provider<OrderService>.value(value: _orderService),
        Provider<ChatService>.value(value: _chatService),
        ChangeNotifierProvider<OrderProvider>.value(value: _orderProvider),
        ChangeNotifierProvider<ChatProvider>.value(value: _chatProvider),
      ],
      child: MaterialApp(
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
      ),
    );
  }
}

class _WelcomeSplashScreen extends StatelessWidget {
  const _WelcomeSplashScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary,
              colorScheme.tertiary,
              colorScheme.secondary,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Chào mừng đến với UniSend',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(26),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const AppLogo(size: 216),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Đang khởi động ứng dụng...',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withAlpha(230),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FirebaseConfigErrorScreen extends StatelessWidget {
  const _FirebaseConfigErrorScreen({required this.errorMessage});

  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lỗi cấu hình Firebase')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ứng dụng đang ở chế độ Firebase thật. Vui lòng kiểm tra cấu hình.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SelectableText(errorMessage),
            const SizedBox(height: 20),
            Text(
              'Nếu cần bỏ qua tạm thời để test UI, chạy với --dart-define=BYPASS_LOGIN=true.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
