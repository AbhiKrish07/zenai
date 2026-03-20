import 'dart:io';
import 'package:flutter/services.dart';

/// macOS platform bridge — AppleScript, shell commands, system control
class MacBridge {
  static const _channel = MethodChannel('com.jarvis/mac_bridge');

  /// Run a terminal command silently and return output
  static Future<String> runCommand(String command) async {
    if (!Platform.isMacOS) return 'Not on macOS';
    try {
      final result = await Process.run('bash', ['-c', command]);
      return result.stdout.toString().trim();
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Open application by name
  static Future<void> openApp(String appName) async {
    await runCommand('open -a "$appName"');
  }

  /// Close application by name
  static Future<void> closeApp(String appName) async {
    await runCommand('osascript -e \'tell application "$appName" to quit\'');
  }

  /// Get running processes
  static Future<List<String>> getRunningProcesses() async {
    final output = await runCommand('ps aux | head -50');
    return output.split('\n');
  }

  /// Control Spotify via AppleScript
  static Future<void> spotifyPlayPause() async {
    await runCommand('osascript -e \'tell application "Spotify" to playpause\'');
  }

  static Future<void> spotifyNext() async {
    await runCommand('osascript -e \'tell application "Spotify" to next track\'');
  }

  static Future<String> spotifyCurrentTrack() async {
    return await runCommand(
      'osascript -e \'tell application "Spotify" to name of current track & " - " & artist of current track\'',
    );
  }

  /// Send iMessage
  static Future<void> sendIMessage(String to, String message) async {
    await runCommand(
      'osascript -e \'tell application "Messages" to send "$message" to buddy "$to"\'',
    );
  }

  /// Get current frontmost app
  static Future<String> getCurrentApp() async {
    return await runCommand(
      'osascript -e \'tell application "System Events" to get name of first application process whose frontmost is true\'',
    );
  }

  /// Screen brightness (macOS)
  static Future<void> setBrightness(double level) async {
    try {
      await _channel.invokeMethod('setBrightness', {'level': level});
    } catch (_) {}
  }

  /// Volume control
  static Future<void> setVolume(double level) async {
    final vol = (level * 100).round();
    await runCommand('osascript -e \'set volume output volume $vol\'');
  }

  static Future<void> mute() async {
    await runCommand('osascript -e \'set volume output muted true\'');
  }

  static Future<void> unmute() async {
    await runCommand('osascript -e \'set volume output muted false\'');
  }

  /// Take screenshot
  static Future<String?> takeScreenshot() async {
    final path = '/tmp/zen_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
    await runCommand('screencapture -x $path');
    return File(path).existsSync() ? path : null;
  }
}
