import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../theme.dart';
import '../main.dart';
import 'home_screen.dart';
import 'welcome_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _scale;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );
    _scale = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0, 0.6, curve: Curves.elasticOut)),
    );
    _controller.forward();

    void checkAndNavigate() async {
      if (!mounted) return;
      
      // Wait for core services to finish (with safety limit)
      int retryCount = 0;
      while (!isZenReady.value && retryCount < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        retryCount++;
      }

      final prefs = await SharedPreferences.getInstance();
      final isFirstRun = prefs.getBool('first_run_v3') ?? true;
      final activeUserId = await _storage.read(key: 'active_user_id');
      
      Widget nextScreen;
      
      if (isFirstRun) {
        nextScreen = const WelcomeScreen();
        await prefs.setBool('first_run_v3', false);
      } else if (activeUserId != null) {
        nextScreen = const HomeScreen();
      } else {
        nextScreen = const LoginScreen();
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => nextScreen,
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    }

    // Minimum display time for Splash
    Timer(const Duration(milliseconds: 2500), checkAndNavigate);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BlitzTheme.bgGradient),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              return Opacity(
                opacity: _fadeIn.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            center: Alignment(-0.3, -0.3),
                            colors: [
                              Color(0xFFF8F9FF),
                              Color(0xFFD7E1FF),
                              Color(0xFF5F73CD)
                            ],
                            stops: [0.0, 0.4, 0.9],
                          ),
                          boxShadow: accentGlow(
                              color: const Color(0xFF6E8CFF), blur: 40),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'ZEN',
                        style: GoogleFonts.syne(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: BlitzTheme.textPrimary,
                          letterSpacing: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'THE HOME SCREEN THAT THINKS',
                        style: GoogleFonts.spaceMono(
                          fontSize: 10,
                          color: BlitzTheme.textMuted,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BlitzTheme.accent.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
