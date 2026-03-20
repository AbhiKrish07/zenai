import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ZenSession {
  static final ZenSession _instance = ZenSession._internal();
  factory ZenSession() => _instance;
  ZenSession._internal();

  final _storage = const FlutterSecureStorage();
  String? _activeUserId;
  String? _activeUserName;
  bool _initialized = false;

  String? get activeUserId => _activeUserId;
  String? get activeUserName => _activeUserName;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _activeUserId = await _storage.read(key: 'active_user_id');
    _activeUserName = await _storage.read(key: 'active_user_name');
    _initialized = true;
  }

  Future<void> ensureInitialized() async {
    if (!_initialized) await init();
  }

  Future<void> login(String userId, {String? name}) async {
    _activeUserId = userId;
    _activeUserName = name;
    await _storage.write(key: 'active_user_id', value: userId);
    if (name != null) {
      await _storage.write(key: 'active_user_name', value: name);
    }
    _initialized = true;
  }

  Future<void> logout() async {
    _activeUserId = null;
    _activeUserName = null;
    await _storage.delete(key: 'active_user_id');
    await _storage.delete(key: 'active_user_name');
    _initialized = true;
  }
}
