import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ═══════════════════════════════════════════════════════
///   Zen Theme  —  Black & Orange Minimalist
///   Primary: #000000   Accent: #FF4500   Text: #F0EDE8
/// ═══════════════════════════════════════════════════════
class ZenTheme {
  static const Color accent    = Color(0xFFFF4500); 
  static Color dynamicAccent   = const Color(0xFFFF4500);
  
  static const Color black       = Color(0xFF000000);
  static const Color bg        = Color(0xFF0E0E0F);
  static const Color bg2         = Color(0xFF050505);
  static const Color surface   = Color(0xFF161617);
  static const Color surfaceHigh = Color(0xFF111111);
  static const Color border    = Color(0x16FFFFFF); // rgba(255,255,255,0.09)
  static const Color border2     = Color(0xFF262626);

  static const Color text      = Color(0xE6FFFFFF); // rgba(255,255,255,0.90)
  static const Color textMuted = Color(0x80FFFFFF); // rgba(255,255,255,0.50)
  static const Color textFaint = Color(0x47FFFFFF); // rgba(255,255,255,0.28)

  // Semantic
  static const Color success   = Color(0xFF4ADE80);
  static const Color green     = Color(0xFF4ADE80);
  static const Color warning   = Color(0xFFFBBF24);
  static const Color error     = Color(0xFFF87171);

  static List<Map<String, dynamic>> get variants => [
    {'name': 'Zen Classic', 'color': const Color(0xFFFF4500), 'id': 'classic'},
    {'name': 'Cyber Purple', 'color': const Color(0xFFA78BFA), 'id': 'cyber'},
    {'name': 'Deep Emerald', 'color': const Color(0xFF00C86A), 'id': 'emerald'},
    {'name': 'Arctic Blue', 'color': const Color(0xFF60A5FA), 'id': 'arctic'},
    {'name': 'Ruby Crimson', 'color': const Color(0xFFFF3B30), 'id': 'ruby'},
    {'name': 'Gold Horizon', 'color': const Color(0xFFFBBF24), 'id': 'gold'},
  ];

  static void setAccent(Color color) => dynamicAccent = color;

  // ── Typography — DM Sans & Space Grotesk ──────────────────────────────
  static TextStyle body({
    double size = 12,
    Color color = text,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
    double height = 1.4,
  }) =>
      GoogleFonts.dmSans(
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle numeric({
    double size = 28,
    Color color = text,
    FontWeight weight = FontWeight.w500,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        color: color,
        fontWeight: weight,
      );

  static TextStyle mono({
    double size = 12,
    Color color = text,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
    double height = 1.4,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle label({double size = 10, Color? color}) => body(
        size: size,
        color: color ?? textFaint,
        letterSpacing: 0.8,
        weight: FontWeight.w500,
      ).copyWith(letterSpacing: 0.5); // 0.08em tracking approximated

  // ── Decorations ───────────────────────────────────────────────────────
  static BoxDecoration pillDecoration({bool active = false}) => BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: active ? accent.withValues(alpha: 0.7) : border,
          width: active ? 1.5 : 1,
        ),
        boxShadow: active
            ? [BoxShadow(color: accent.withValues(alpha: 0.2), blurRadius: 24, spreadRadius: 2)]
            : [],
      );

  static BoxDecoration cardDecoration({double radius = 18}) => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: 0.5),
      );

  // Thin horizontal rule — used sparingly
  static Widget rule({double opacity = 0.08}) => Divider(
        color: Colors.white.withValues(alpha: opacity),
        height: 1,
        thickness: 1,
      );

  // ── ThemeData ─────────────────────────────────────────────────────────

  static ThemeData get classicTheme => _buildTheme(dynamicAccent);
  static ThemeData get minimalistTheme => _buildTheme(Colors.white, isMinimalist: true);

  static ThemeData _buildTheme(Color accentColor, {bool isMinimalist = false}) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: isMinimalist ? Colors.black : bg,
      primaryColor: accentColor,
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        secondary: accentColor,
        surface: isMinimalist ? Colors.black : surface,
        error: error,
        onPrimary: isMinimalist ? Colors.black : black,
        onSurface: text,
      ),
      textTheme: GoogleFonts.ibmPlexMonoTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: text,
        displayColor: text,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: mono(size: 13, weight: FontWeight.w600, letterSpacing: 2),
        iconTheme: const IconThemeData(color: textMuted, size: 18),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isMinimalist ? Colors.white.withValues(alpha: 0.04) : surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isMinimalist ? 0 : 6),
          borderSide: BorderSide(color: isMinimalist ? Colors.white24 : border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isMinimalist ? 0 : 6),
          borderSide: BorderSide(color: isMinimalist ? Colors.white10 : border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isMinimalist ? 0 : 6),
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
        hintStyle: body(size: 12, color: textFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: isMinimalist ? Colors.black : black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMinimalist ? 0 : 6)),
          textStyle: mono(size: 12, weight: FontWeight.w600, letterSpacing: 1),
        ),
      ),
      iconTheme: const IconThemeData(color: textMuted, size: 18),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isMinimalist ? Colors.black : bg,
        selectedItemColor: accentColor,
        unselectedItemColor: textFaint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  // Deprecated - use classicTheme or minimalistTheme
  static ThemeData get darkTheme => classicTheme;
}

// ── Backwards compatibility alias for existing code ────────────────────────
// The existing BlitzTheme continues to work; these aliases let new voice
// widgets import ZenTheme without touching legacy screens.
class SpatialTheme {
  static const Color bg          = ZenTheme.bg;
  static const Color bg2         = ZenTheme.bg2;
  static const Color surface     = ZenTheme.surface;
  static const Color surfaceLight = ZenTheme.surfaceHigh;
  static const Color border      = ZenTheme.border;
  static const Color border2     = ZenTheme.border2;
  static const Color textPrimary = ZenTheme.text;
  static const Color textMuted   = ZenTheme.textMuted;
  static const Color faint       = Color(0x0EFFFFFF);

  static const Color accent      = ZenTheme.accent;
  static const Color green       = ZenTheme.success;
  static const Color red         = ZenTheme.error;
  static const Color gold        = Color(0xFFFBBF24);
  static const Color blue        = Color(0xFF60A5FA);
  static const Color cyan        = Color(0xFF22D3EE);

  static LinearGradient get accentGradient => LinearGradient(
    colors: [ZenTheme.accent, ZenTheme.accent.withValues(alpha: 0.7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient coreGradient = LinearGradient(
    colors: [Color(0xFF818CF8), Color(0xFFA78BFA), Color(0xFFC084FC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFF000000), Color(0xFF050505), Color(0xFF000000)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0x14FFFFFF), Color(0x08FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Map<String, Color> get moduleColors => {
    'coding': const Color(0xFF60A5FA),
    'studying': const Color(0xFFFBBF24),
    'create': const Color(0xFFFB7185),
    'research': const Color(0xFF4ADE80),
    'memory': const Color(0xFFC084FC),
    'vision': const Color(0xFF22D3EE),
    'voice': ZenTheme.accent,
    'ceo': const Color(0xFFF59E0B),
  };

  static ThemeData get darkTheme => ZenTheme.darkTheme;
}

typedef BlitzTheme = SpatialTheme;

/// Glassmorphism card decoration (kept for legacy screens)
BoxDecoration glassCard({
  double borderRadius = 16,
  Color? borderColor,
  double opacity = 0.06,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(borderRadius),
    color: Colors.white.withValues(alpha: opacity),
    border: Border.all(
      color: borderColor ?? BlitzTheme.border,
      width: 1,
    ),
  );
}

/// Orange glow shadow for voice elements
List<BoxShadow> orangeGlow({double blur = 20, double spread = 0}) => [
  BoxShadow(
    color: ZenTheme.accent.withValues(alpha: 0.25),
    blurRadius: blur,
    spreadRadius: spread,
  ),
  BoxShadow(
    color: ZenTheme.accent.withValues(alpha: 0.08),
    blurRadius: blur * 2,
    spreadRadius: spread,
  ),
];

/// Accent (purple) glow shadow for legacy screens
List<BoxShadow> accentGlow({Color? color, double blur = 20, double spread = 0}) {
  final c = color ?? BlitzTheme.accent;
  return [
    BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: blur, spreadRadius: spread),
    BoxShadow(color: c.withValues(alpha: 0.1), blurRadius: blur * 2, spreadRadius: spread),
  ];
}
