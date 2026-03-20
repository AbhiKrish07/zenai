import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _orbController;

  final List<Map<String, String>> _pages = [
    {
      'title': 'ZEN',
      'subtitle': 'AMBIENT INTELLIGENCE',
      'desc': 'A living canvas for your digital life.\nZen anticipates your needs and manages your chaos.',
    },
    {
      'title': 'COMMAND',
      'subtitle': 'MODULAR DASHBOARD',
      'desc': 'Place widgets anywhere. Visualize tasks,\nenergy levels, and focus time on a spatial grid.',
    },
    {
      'title': 'FORGE',
      'subtitle': 'HACKER-GRADE TOOLS',
      'desc': 'Write code, execute scripts, and build\nwith built-in AI assistance in an obsidian workspace.',
    },
    {
      'title': 'PRIVATE',
      'subtitle': 'TOTALLY LOCAL',
      'desc': 'Your data stays on your machine.\nNo cloud sync, no tracking, just pure performance.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _orbController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Animation
          _buildAnimatedBackground(),

          // Page Content
          PageView.builder(
            controller: _pageController,
            onPageChanged: (v) => setState(() => _currentPage = v),
            itemCount: _pages.length,
            itemBuilder: (context, index) {
              final page = _pages[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),
                    _buildVisualForPage(index),
                    const Spacer(),
                    Text(
                      page['title']!,
                      style: GoogleFonts.syne(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      page['subtitle']!,
                      style: GoogleFonts.spaceMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: BlitzTheme.accent,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      page['desc']!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.syne(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                        height: 1.6,
                      ),
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
              );
            },
          ),

          // Controls
          Positioned(
            bottom: 64,
            left: 32,
            right: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Indicators
                Row(
                  children: List.generate(
                    _pages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 6),
                      width: _currentPage == index ? 24 : 6,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: _currentPage == index 
                          ? BlitzTheme.accent 
                          : Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                ),
                
                // Button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    if (_currentPage < _pages.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                      );
                    } else {
                      Navigator.pushReplacement(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const LoginScreen(),
                          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      color: BlitzTheme.accent.withValues(alpha: 0.1),
                      border: Border.all(color: BlitzTheme.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentPage == _pages.length - 1 ? 'READY' : 'NEXT',
                          style: GoogleFonts.spaceMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
                      ],
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

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _orbController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: WelcomeBackgroundPainter(_orbController.value),
        );
      },
    );
  }

  Widget _buildVisualForPage(int index) {
    switch (index) {
      case 0:
        return _pulsingOrb();
      case 1:
        return _widgetGrid();
      case 2:
        return _forgePreview();
      case 3:
        return _privacySeal();
      default:
        return const SizedBox();
    }
  }

  Widget _pulsingOrb() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFF8F9FF), Color(0xFF6E8CFF), Color(0xFF1A1F35)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6E8CFF).withValues(alpha: 0.4),
            blurRadius: 60,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }

  Widget _widgetGrid() {
    return SizedBox(
      height: 140,
      child: Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            _miniWidget(40, 40, BlitzTheme.accent),
            _miniWidget(80, 40, BlitzTheme.gold),
            _miniWidget(90, 60, BlitzTheme.cyan),
            _miniWidget(50, 60, BlitzTheme.cyan.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _miniWidget(double w, double h, Color c) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
    );
  }

  Widget _forgePreview() {
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                _dot(Colors.red), _dot(Colors.orange), _dot(Colors.green),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _codeLine(60), _codeLine(80), _codeLine(40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: c.withValues(alpha: 0.5), shape: BoxShape.circle));
  Widget _codeLine(double w) => Container(width: w, height: 4, margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2)));

  Widget _privacySeal() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: BlitzTheme.accent.withValues(alpha: 0.3), width: 1.5),
          ),
        ),
        const Icon(Icons.security_rounded, size: 48, color: BlitzTheme.accent),
      ],
    );
  }
}

class WelcomeBackgroundPainter extends CustomPainter {
  final double progress;
  WelcomeBackgroundPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;
    final center = Offset(size.width * 0.8, size.height * 0.1);
    
    // Draw subtle radial lines or orbs
    for (var i = 1; i <= 3; i++) {
      paint.color = Colors.white.withValues(alpha: 0.05 / i);
      paint.strokeWidth = 1.0;
      canvas.drawCircle(center, 100.0 * i + (10 * progress), paint);
    }
  }

  @override
  bool shouldRepaint(WelcomeBackgroundPainter oldDelegate) => true;
}
