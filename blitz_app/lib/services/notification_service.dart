import 'dart:async';
import 'package:flutter/services.dart';

/// A notification event received from Android's NotificationListenerService.
class ServiceNotificationEvent {
  final int? id;
  final String? title;
  final String? content;
  final String? packageName;
  final String? appName;
  final int? postedAt;
  final bool? hasRemoved;
  final bool? canReply;

  const ServiceNotificationEvent({
    this.id,
    this.title,
    this.content,
    this.packageName,
    this.appName,
    this.postedAt,
    this.hasRemoved,
    this.canReply,
  });

  factory ServiceNotificationEvent.fromMap(Map<Object?, Object?> map) {
    return ServiceNotificationEvent(
      id: map['id'] as int?,
      title: map['title'] as String?,
      content: map['text'] as String?,
      packageName: map['pkg'] as String?,
      appName: map['app_name'] as String?,
      postedAt: map['posted_at'] as int?,
      hasRemoved: map['removed'] as bool?,
      canReply: map['can_reply'] as bool?,
    );
  }

  /// Replies can now be sent via native channel.
  Future<bool> sendReply(String message) async {
    if (id == null) return false;
    return await AppNotificationService().replyTo(this, message);
  }
}

/// Manages reading live Android notifications via our custom native
/// [ZenNotificationService] (Kotlin) over Flutter platform channels.
class AppNotificationService {
  static final AppNotificationService _i = AppNotificationService._();
  factory AppNotificationService() => _i;
  AppNotificationService._();

  static const _method = MethodChannel('com.zen/notifications');
  static const _events = EventChannel('com.zen/notifications/stream');

  final List<ServiceNotificationEvent> _notifications = [];
  final _controller =
      StreamController<List<ServiceNotificationEvent>>.broadcast();

  Stream<List<ServiceNotificationEvent>> get stream => _controller.stream;
  List<ServiceNotificationEvent> get notifications =>
      List.unmodifiable(_notifications);

  StreamSubscription? _sub;

  // ── Permission ────────────────────────────────────────────────────

  /// Returns true if the user has granted Notification Listener access.
  Future<bool> isPermissionGranted() async {
    try {
      return await _method.invokeMethod<bool>('isPermissionGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android Settings → Notification Access so the user can grant it.
  Future<void> requestPermission() async {
    try {
      await _method.invokeMethod('requestPermission');
    } catch (_) {}
  }

  // ── Listening ─────────────────────────────────────────────────────

  /// Start streaming notifications from native.
  /// If [askPermission] is true and permission not yet granted, opens settings.
  Future<void> startListening({bool askPermission = false}) async {
    try {
      final granted = await isPermissionGranted();
      if (!granted) {
        if (askPermission) await requestPermission();
        return; // Can't listen without permission
      }

      _sub?.cancel();
      _sub = _events.receiveBroadcastStream().listen(
        (dynamic rawEvent) {
          if (rawEvent is! Map<Object?, Object?>) return;
          final event = ServiceNotificationEvent.fromMap(rawEvent);

          if (event.hasRemoved == true) {
            _notifications.removeWhere((n) => n.id == event.id);
          } else {
            // Dedupe by id
            _notifications.removeWhere((n) => n.id == event.id);
            _notifications.insert(0, event);
            if (_notifications.length > 50) _notifications.removeLast();
          }
          _controller.add(List.unmodifiable(_notifications));
        },
        onError: (_) {}, // Silently handle stream errors
        cancelOnError: false,
      );
    } catch (_) {
      // MissingPluginException or other platform errors — silently ignore
    }
  }

  /// Sends a direct reply to the notification.
  Future<bool> replyTo(ServiceNotificationEvent notif, String message) async {
    try {
      return await _method.invokeMethod<bool>('replyToNotification', {
            'id': notif.id,
            'message': message,
          }) ??
          false;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }

  void clearAll() {
    _notifications.clear();
    _controller.add([]);
  }

  // ── Helper ────────────────────────────────────────────────────────

  /// Returns a user-friendly app name from package name.
  String friendlyApp(String? pkg) {
    if (pkg == null) return 'Unknown';
    const map = {
      'com.whatsapp': 'WhatsApp',
      'com.instagram.android': 'Instagram',
      'com.google.android.gm': 'Gmail',
      'com.twitter.android': 'X',
      'com.snapchat.android': 'Snapchat',
      'com.facebook.katana': 'Facebook',
      'com.spotify.music': 'Spotify',
      'com.google.android.apps.messaging': 'Messages',
      'com.discord': 'Discord',
      'com.slack': 'Slack',
      'com.linkedin.android': 'LinkedIn',
      'com.google.android.youtube': 'YouTube',
    };
    return map[pkg] ?? pkg.split('.').last.capitalize();
  }
}

extension _StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
