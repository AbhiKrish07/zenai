import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'core/zen_brain.dart';
import 'core/database.dart';
import 'core/notifications.dart';
import 'core/background_service.dart';
import 'screens/splash_screen.dart';
import 'voice/voice_mode_screen.dart';
import 'core/session.dart';
import 'core/theme_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Zen — Ambient Intelligence Layer
//  Entry point: initialises all core services then mounts the app shell.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // We ensure runtime fetching is enabled for Google Fonts to resolve asset loading.
  GoogleFonts.config.allowRuntimeFetching = true;

  // ── Error Handling Overlay ─────────────────────────────────────────────
  // This catches asynchronous errors that might otherwise pause the debugger.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Caught Async Error: $error');
    // If it's a SocketException, it's usually just a backend/network issue.
    return true; 
  };

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
  };

  // ── System chrome ──────────────────────────────────────────────────────
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF000000),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // ── Core service init (parallel execution) ────────────────────────────
  // We launch 'runApp' immediately so the SplashScreen can mount.
  // The services init in the background while the splash animation plays.
  runApp(const ZenApp());

  _initializeCoreServices();
}

/// Notifier to track if core services are ready
final ValueNotifier<bool> isZenReady = ValueNotifier(false);

/// Robust background initialization of all core services
Future<void> _initializeCoreServices() async {
  try {
    debugPrint('[Zen] Initializing Core Services...');

    // 1. Session & DB must be first
    await ZenSession().init().timeout(const Duration(seconds: 3), 
        onTimeout: () => debugPrint('[Zen] Session init timeout'));
    
    // Attempt database connection with a strict timeout
    await ZenDatabase().database.timeout(const Duration(seconds: 5)).catchError((e) {
      debugPrint('[Zen] DB Error: $e');
      return ZenDatabase().database; // Try one more time without timeout if it's first run
    });

    // 2. Others can be parallel
    // We catch errors individually so one failure (like network) doesn't stop others.
    await Future.wait([
      if (!kIsWeb) ZenNotifications().init()
          .timeout(const Duration(seconds: 3))
          .catchError((e) => debugPrint('[Zen] Notification init error: $e')),
      
      ZenBrain().init()
          .timeout(const Duration(seconds: 3))
          .catchError((e) => debugPrint('[Zen] Brain init error: $e')),
      
      ThemeManager().init()
          .timeout(const Duration(seconds: 3))
          .catchError((e) => debugPrint('[Zen] Theme init error: $e')),
      
      _initBackgroundService(),
    ]);

    debugPrint('[Zen] Core Services Ready.');
  } catch (e) {
    debugPrint('CRITICAL: Service initialization failed: $e');
    debugPrint('TIP: If your debugger is pausing on _Nativesocket.lookup, '
               'disable "Pause on Caught Exceptions" in your IDE or Ensure your backend is running.');
  } finally {
    isZenReady.value = true;
  }
}

Future<void> _initBackgroundService() async {
  // workmanager only supports Android and iOS
  try {
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      debugPrint('[Zen] Initializing Background Services...');
      await BackgroundService.init();
    } else {
      debugPrint('[Zen] Background Services skipped (Platform not supported)');
    }
  } catch (e) {
    debugPrint('[Zen] BackgroundService error: $e');
  }
}

class ZenApp extends StatelessWidget {
  const ZenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Redundantly ensure font fetching is enabled during UI build cycles.
    GoogleFonts.config.allowRuntimeFetching = true;
    return ListenableBuilder(
      listenable: ThemeManager(),
      builder: (context, _) => MaterialApp(
        title: 'Zen AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeManager().themeData,
        routes: {
          '/voice': (_) => const VoiceModeScreen(),
        },
        home: const SplashScreen(),
      ),
    );
  }
}
