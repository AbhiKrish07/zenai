import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  Color _accent = const Color(0xFFFF4500);
  Color get accent => _accent;

  LinearGradient _backgroundGradient = const LinearGradient(
    colors: [Colors.black, Color(0xFF0A0A0A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  LinearGradient get backgroundGradient => _backgroundGradient;

  bool _isMinimalist = false;
  bool get isMinimalist => _isMinimalist;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    _isMinimalist = prefs.getBool('theme_minimalist') ?? false;
    
    final value = prefs.getInt('theme_color');
    if (value != null) {
      _accent = Color(value);
      ZenTheme.setAccent(_accent);
    }
    _wallpaperPath = prefs.getString('home_wallpaper');
    notifyListeners();
  }

  String? _wallpaperPath;
  String? get wallpaperPath => _wallpaperPath;

  Future<void> setWallpaper(String path) async {
    _wallpaperPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_wallpaper', path);
    notifyListeners();
  }

  Future<void> setAccent(Color color) async {
    _accent = color;
    ZenTheme.setAccent(color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color', color.toARGB32());
    notifyListeners();
  }

  Future<void> toggleMinimalist() async {
    _isMinimalist = !_isMinimalist;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme_minimalist', _isMinimalist);
    notifyListeners();
  }

  void setMorph(String mood) {
    switch (mood.toLowerCase()) {
      case 'focus':
        _backgroundGradient = const LinearGradient(
          colors: [Color(0xFF000512), Color(0xFF001036)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
        break;
      case 'chill':
        _backgroundGradient = const LinearGradient(
          colors: [Color(0xFF0A0214), Color(0xFF1A0A30)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
        break;
      default:
        _backgroundGradient = const LinearGradient(
          colors: [Colors.black, Color(0xFF0A0A0A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
    }
    notifyListeners();
  }

  ThemeData get themeData {
    if (_isMinimalist) {
      return ZenTheme.minimalistTheme;
    }
    return ZenTheme.classicTheme.copyWith(
      colorScheme: ZenTheme.classicTheme.colorScheme.copyWith(
        primary: _accent,
        secondary: _accent,
      ),
    );
  }
}
