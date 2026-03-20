import 'dart:convert';
import 'package:http/http.dart' as http;

/// Spotify Web API service — play/pause/skip/search via OAuth token.
/// User must authenticate once via Spotify to get the access token.
class SpotifyService {
  static final SpotifyService _i = SpotifyService._();
  factory SpotifyService() => _i;
  SpotifyService._();

  String? _accessToken;
  Map<String, dynamic>? _currentTrack;

  static const String _base = 'https://api.spotify.com/v1/me/player';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${_accessToken ?? ""}',
        'Content-Type': 'application/json',
      };

  bool get isConnected => _accessToken != null;

  void setToken(String token) {
    _accessToken = token;
  }

  // ── Playback Controls ──────────────────────────────────────────────
  Future<bool> play() => _put('$_base/play');
  Future<bool> pause() => _put('$_base/pause');
  Future<bool> next() => _post('$_base/next');
  Future<bool> previous() => _post('$_base/previous');

  Future<bool> setVolume(int percent) =>
      _put('$_base/volume?volume_percent=$percent');

  // ── Current Track ──────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getCurrentTrack() async {
    if (_accessToken == null) return null;
    try {
      final resp = await http
          .get(Uri.parse('$_base/currently-playing'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final data = jsonDecode(resp.body);
        _currentTrack = {
          'title': data['item']?['name'] ?? 'Unknown',
          'artist': (data['item']?['artists'] as List?)
                  ?.map((a) => a['name'])
                  .join(', ') ??
              'Unknown',
          'album_art': data['item']?['album']?['images']?[0]?['url'],
          'is_playing': data['is_playing'] ?? false,
          'progress_ms': data['progress_ms'] ?? 0,
          'duration_ms': data['item']?['duration_ms'] ?? 1,
        };
        return _currentTrack;
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? get cachedTrack => _currentTrack;

  // ── Search ─────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> search(String query) async {
    if (_accessToken == null) return [];
    try {
      final url = Uri.parse(
          'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=track&limit=5');
      final resp = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = (data['tracks']?['items'] as List?) ?? [];
        return items
            .map<Map<String, dynamic>>((i) => {
                  'title': i['name'],
                  'artist': (i['artists'] as List).map((a) => a['name']).join(', '),
                  'uri': i['uri'],
                })
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Play a specific track by Spotify URI
  Future<bool> playTrack(String uri) async {
    if (_accessToken == null) return false;
    try {
      final resp = await http
          .put(
            Uri.parse('$_base/play'),
            headers: _headers,
            body: jsonEncode({'uris': [uri]}),
          )
          .timeout(const Duration(seconds: 8));
      return resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // ── HTTP helpers ───────────────────────────────────────────────────
  Future<bool> _put(String url) async {
    if (_accessToken == null) return false;
    try {
      final resp = await http
          .put(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 8));
      return resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _post(String url) async {
    if (_accessToken == null) return false;
    try {
      final resp = await http
          .post(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 8));
      return resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
