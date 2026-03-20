import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

/// iOS/iPadOS platform bridge
class IOSBridge {
  static final _localAuth = LocalAuthentication();

  /// Authenticate with Face ID / Touch ID
  static Future<bool> authenticate() async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics;
      if (!canAuth) return true; // No biometrics, allow access
      
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to access Zen',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  /// Haptic feedback
  static void lightHaptic() => HapticFeedback.lightImpact();
  static void mediumHaptic() => HapticFeedback.mediumImpact();
  static void heavyHaptic() => HapticFeedback.heavyImpact();
  static void selectionHaptic() => HapticFeedback.selectionClick();

  /// Deep links
  static Future<void> openDeepLink(String path) async {
    final uri = Uri.parse('jarvis://$path');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Open URL
  static Future<void> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Open Spotify
  static Future<void> openSpotify() async {
    await openUrl('spotify://');
  }

  /// Open YouTube
  static Future<void> openYouTube([String? query]) async {
    if (query != null) {
      await openUrl('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}');
    } else {
      await openUrl('youtube://');
    }
  }

  /// Clipboard
  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<String?> getClipboard() async {
    final data = await Clipboard.getData('text/plain');
    return data?.text;
  }
}
