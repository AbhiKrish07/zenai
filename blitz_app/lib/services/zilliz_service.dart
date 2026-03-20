import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../core/zen_brain.dart';

/// Zilliz Cloud vector memory service.
/// Stores chat memories as semantic vectors and retrieves
/// the most relevant ones for each new user message.
class ZillizService {
  static final ZillizService _instance = ZillizService._internal();
  factory ZillizService() => _instance;
  ZillizService._internal();

  // Groq embedding endpoint
  static const String _embedUrl =
      'https://api.groq.com/openai/v1/embeddings';

  // Vector dimension for nomic-embed-text
  static const int _dim = 768;

  String get _auth {
    final user = ZenBrain().zillizUser;
    final pass = ZenBrain().zillizPassword;
    if (user.isEmpty || pass.isEmpty) return '';
    final creds = '$user:$pass';
    return 'Bearer ${base64Encode(utf8.encode(creds))}';
  }

  String get _endpoint => ZenBrain().zillizEndpoint;
  String get _collection => BlitzConfig.zillizCollection;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': _auth,
      };

  static int _requestCount = 0;

  // ── Embed text via Groq nomic-embed-text ──────────────────────────
  Future<List<double>?> _embed(String text) async {
    try {
      final String userKey = ZenBrain().apiKey;
      final String key = userKey.isNotEmpty 
          ? userKey 
          : BlitzConfig.groqKeyPool[_requestCount % BlitzConfig.groqKeyPool.length];
      
      _requestCount++;

      final resp = await http
          .post(
            Uri.parse(_embedUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key',
            },
            body: jsonEncode({
              'model': 'nomic-embed-text',
              'input': text,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final embedding =
            (data['data']?[0]?['embedding'] as List?)
                ?.cast<double>();
        return embedding;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ── Ensure collection exists ───────────────────────────────────────
  Future<bool> ensureCollection() async {
    if (_endpoint.contains('XXXXXXXXX')) return false; // Not configured yet
    try {
      // Check if collection exists
      final resp = await http
          .get(
            Uri.parse(
                '$_endpoint/v2/vectordb/collections/describe?collectionName=$_collection'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['code'] == 0) return true; // Already exists
      }

      // Create collection
      final createResp = await http
          .post(
            Uri.parse('$_endpoint/v2/vectordb/collections/create'),
            headers: _headers,
            body: jsonEncode({
              'collectionName': _collection,
              'dimension': _dim,
              'metricType': 'COSINE',
              'primaryField': 'id',
              'vectorField': 'vector',
              'schema': {
                'fields': [
                  {
                    'fieldName': 'id',
                    'dataType': 'VarChar',
                    'isPrimary': true,
                    'elementTypeParams': {'max_length': '256'},
                  },
                  {
                    'fieldName': 'vector',
                    'dataType': 'FloatVector',
                    'elementTypeParams': {'dim': '$_dim'},
                  },
                  {
                    'fieldName': 'text',
                    'dataType': 'VarChar',
                    'elementTypeParams': {'max_length': '4096'},
                  },
                  {
                    'fieldName': 'category',
                    'dataType': 'VarChar',
                    'elementTypeParams': {'max_length': '128'},
                  },
                  {
                    'fieldName': 'created_at',
                    'dataType': 'VarChar',
                    'elementTypeParams': {'max_length': '64'},
                  },
                ],
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      return createResp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ── Store a memory vector ──────────────────────────────────────────
  Future<bool> upsertMemory({
    required String id,
    required String text,
    String category = 'general',
  }) async {
    if (_endpoint.contains('XXXXXXXXX')) return false;
    final vector = await _embed(text);
    if (vector == null) return false;

    try {
      final resp = await http
          .post(
            Uri.parse('$_endpoint/v2/vectordb/entities/upsert'),
            headers: _headers,
            body: jsonEncode({
              'collectionName': _collection,
              'data': [
                {
                  'id': id,
                  'vector': vector,
                  'text': text,
                  'category': category,
                  'created_at': DateTime.now().toIso8601String(),
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ── Semantic search: find top-k relevant memories ─────────────────
  Future<List<String>> searchMemories(String query, {int topK = 5}) async {
    if (_endpoint.contains('XXXXXXXXX')) return [];
    final vector = await _embed(query);
    if (vector == null) return [];

    try {
      final resp = await http
          .post(
            Uri.parse('$_endpoint/v2/vectordb/entities/search'),
            headers: _headers,
            body: jsonEncode({
              'collectionName': _collection,
              'data': [vector],
              'annsField': 'vector',
              'limit': topK,
              'outputFields': ['text', 'category'],
              'searchParams': {'metricType': 'COSINE', 'params': {'nprobe': 10}},
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final results = data['data'] as List? ?? [];
        return results
            .map((r) => '[${r['category']}] ${r['text']}')
            .cast<String>()
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ── Delete a memory by ID ──────────────────────────────────────────
  Future<bool> deleteMemory(String id) async {
    if (_endpoint.contains('XXXXXXXXX')) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('$_endpoint/v2/vectordb/entities/delete'),
            headers: _headers,
            body: jsonEncode({
              'collectionName': _collection,
              'filter': 'id == "$id"',
            }),
          )
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Returns true if Zilliz is properly configured (not placeholder endpoint)
  bool get isConfigured => !_endpoint.contains('XXXXXXXXX');
}
