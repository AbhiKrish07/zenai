import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../models/event.dart';
import '../models/assignment.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/memory_slot.dart';
import '../models/study_session.dart';
import '../models/reading_item.dart';
import '../models/expense.dart';
import '../models/mood.dart';
import '../models/startup_metrics.dart';
import '../models/investor.dart';
import '../models/widget_item.dart';

class ZenDatabase {
  static final ZenDatabase _instance = ZenDatabase._internal();
  factory ZenDatabase() => _instance;
  ZenDatabase._internal();

  static Database? _db;
  static Completer<Database>? _dbCompleter;

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_dbCompleter != null) return _dbCompleter!.future;
    _dbCompleter = Completer<Database>();
    try {
      debugPrint('[ZenDB] Initializing Database...');
      _db = await _initDB();
      debugPrint('[ZenDB] Database Initialized Successfully.');
      _dbCompleter!.complete(_db!);
      return _db!;
    } catch (e, stack) {
      debugPrint('[ZenDB] Database Init Error: $e');
      debugPrint(stack.toString());
      _dbCompleter!.completeError(e);
      _dbCompleter = null;
      rethrow;
    }
  }

  Future<Database> _initDB() async {
    const version = 16;
    if (kIsWeb) {
      debugPrint('[ZenDB] Web Platform detected. skipping SQLite init.');
      // Return a dummy/mock value or throw a more descriptive error if needed.
      // But for our current architecture, we just avoid calling db.
      throw UnsupportedError('SQLite is not available on Web. Use platform-specific storage.');
    }
    final dbPath = await getDatabasesPath();
    final fullPath = '$dbPath/zen_v6.db';
    return await openDatabase(fullPath, version: version, onCreate: _createTables);
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('CREATE TABLE tasks(id TEXT PRIMARY KEY, title TEXT, description TEXT, priority TEXT, due_date TEXT, completed INTEGER, completed_at TEXT, recurring TEXT, energy_level TEXT, ai_score REAL, created_at TEXT, updated_at TEXT)');
    await db.execute('CREATE TABLE events(id TEXT PRIMARY KEY, title TEXT, description TEXT, start_time TEXT, end_time TEXT, event_type TEXT, location TEXT, briefing TEXT, synced INTEGER, device_event_id TEXT, created_at TEXT)');
    await db.execute('CREATE TABLE assignments(id TEXT PRIMARY KEY, title TEXT, course TEXT, due_date TEXT, grade REAL, max_grade REAL, weight REAL, status TEXT, notes TEXT, created_at TEXT)');
    await db.execute('CREATE TABLE chat_sessions(id TEXT PRIMARY KEY, title TEXT, updated_at TEXT, folder_id TEXT, is_archived INTEGER, is_deleted INTEGER)');
    await db.execute('CREATE TABLE chat_messages(id TEXT PRIMARY KEY, role TEXT, content TEXT, timestamp TEXT, metadata TEXT, session_id TEXT)');
    await db.execute('CREATE TABLE memories(id TEXT PRIMARY KEY, key TEXT, value TEXT, category TEXT, created_at TEXT, updated_at TEXT)');
    await db.execute('CREATE TABLE study_sessions(id TEXT PRIMARY KEY, subject TEXT, duration_minutes INTEGER, session_type TEXT, started_at TEXT, ended_at TEXT, notes TEXT)');
    await db.execute('CREATE TABLE reading_items(id TEXT PRIMARY KEY, title TEXT, url TEXT, item_type TEXT, status TEXT, notes TEXT, summary TEXT, author TEXT, created_at TEXT, updated_at TEXT)');
    await db.execute('CREATE TABLE expenses(id TEXT PRIMARY KEY, amount REAL, category TEXT, description TEXT, date TEXT, recurring INTEGER, created_at TEXT)');
    await db.execute('CREATE TABLE mood_entries(id TEXT PRIMARY KEY, mood_score INTEGER, energy_level INTEGER, notes TEXT, tags TEXT, date TEXT, created_at TEXT)');
    await db.execute('CREATE TABLE startup_metrics(id TEXT PRIMARY KEY, revenue REAL, users INTEGER, date TEXT)');
    await db.execute('CREATE TABLE investors(id TEXT PRIMARY KEY, name TEXT, status TEXT, notes TEXT)');
    await db.execute('CREATE TABLE home_widgets(id TEXT PRIMARY KEY, user_id TEXT, type TEXT, x REAL, y REAL, width REAL, height REAL, data TEXT)');
    await db.execute('CREATE TABLE dashboard_tiles(id TEXT PRIMARY KEY, label TEXT, type TEXT, data TEXT)');
    await db.execute('CREATE TABLE users(id TEXT PRIMARY KEY, username TEXT UNIQUE, passphrase_hash TEXT, name TEXT, created_at TEXT)');
    await db.execute('CREATE TABLE folders(id TEXT PRIMARY KEY, name TEXT)');
  }

  // ── TASKS ──
  Future<void> insertTask(Task task) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final tasksJson = prefs.getString('zen_tasks_web') ?? '[]';
        final List<dynamic> list = jsonDecode(tasksJson);
        final Map<String, dynamic> taskMap = task.toMap();
        
        final idx = list.indexWhere((t) {
          if (t is Map) return t['id'] == task.id;
          return false;
        });

        if (idx != -1) {
          list[idx] = taskMap;
        } else {
          list.add(taskMap);
        }
        
        final bool success = await prefs.setString('zen_tasks_web', jsonEncode(list));
        debugPrint('[ZenDB] Web Task Saved: ${task.title} (ID: ${task.id}, Success: $success, Total: ${list.length})');
      } catch (e) {
        debugPrint('[ZenDB] Web Insert Error: $e');
      }
      return;
    }
    final db = await database;
    debugPrint('[ZenDB] Inserting task: ${task.title}');
    await db.insert('tasks', task.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Task>> getTasks({bool includeCompleted = false}) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final tasksJson = prefs.getString('zen_tasks_web') ?? '[]';
        final List<dynamic> list = jsonDecode(tasksJson);
        final List<Task> tasks = [];
        
        for (var item in list) {
          try {
            if (item is Map) {
              // Use Map.from to ensure Map<String, dynamic> on Web
              tasks.add(Task.fromMap(Map<String, dynamic>.from(item)));
            }
          } catch (e) {
            debugPrint('[ZenDB] Error parsing task: $e | Raw: $item');
          }
        }
        
        debugPrint('[ZenDB] Web Found ${tasks.length} tasks.');
        if (includeCompleted) return tasks;
        return tasks.where((t) => !t.completed).toList();
      } catch (e) {
        debugPrint('[ZenDB] Error getting web tasks: $e');
        return [];
      }
    }
    final db = await database;
    debugPrint('[ZenDB] Querying tasks (includeCompleted: $includeCompleted)');
    final res = includeCompleted ? await db.query('tasks') : await db.query('tasks', where: 'completed = 0');
    final tasks = res.map((m) => Task.fromMap(m)).toList();
    debugPrint('[ZenDB] Found ${tasks.length} tasks.');
    return tasks;
  }
  Future<void> completeTask(String id) async {
    if (kIsWeb) {
      final tasks = await getTasks(includeCompleted: true);
      final idx = tasks.indexWhere((t) => t.id == id);
      if (idx != -1) await insertTask(tasks[idx].copyWith(completed: true, completedAt: DateTime.now()));
      return;
    }
    final db = await database;
    await db.update('tasks', {'completed': 1, 'completed_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> uncompleteTask(String id) async {
    if (kIsWeb) {
      final tasks = await getTasks(includeCompleted: true);
      final idx = tasks.indexWhere((t) => t.id == id);
      if (idx != -1) await insertTask(tasks[idx].copyWith(completed: false, completedAt: null));
      return;
    }
    final db = await database;
    await db.update('tasks', {'completed': 0, 'completed_at': null}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> deleteTask(String id) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('zen_tasks_web') ?? '[]';
      final List<dynamic> list = jsonDecode(tasksJson);
      list.removeWhere((t) => t['id'] == id);
      await prefs.setString('zen_tasks_web', jsonEncode(list));
      return;
    }
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }
  Future<void> updateTask(Task t) async => insertTask(t);

  Future<void> updateTaskScore(String id, double s) async {
    if (kIsWeb) {
      final tasks = await getTasks(includeCompleted: true);
      final idx = tasks.indexWhere((t) => t.id == id);
      if (idx != -1) await insertTask(tasks[idx].copyWith(aiScore: s));
      return;
    }
    final db = await database;
    await db.update('tasks', {'ai_score': s}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> getCompletedTasksToday() async => 0;

  // ── SESSIONS & FOLDERS ──
  Future<List<ChatSession>> getChatSessions() async {
    final db = await database;
    final res = await db.query('chat_sessions', where: 'is_deleted = 0');
    return res.map((m) => ChatSession.fromMap(m)).toList();
  }
  Future<void> insertChatSession(ChatSession s) async {
    final db = await database;
    await db.insert('chat_sessions', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<ChatSession>> getTrashSessions() async {
    final db = await database;
    final res = await db.query('chat_sessions', where: 'is_deleted = 1');
    return res.map((m) => ChatSession.fromMap(m)).toList();
  }
  Future<void> trashChatSession(String id) async {
    final db = await database;
    await db.update('chat_sessions', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> restoreChatSession(String id) async {
    final db = await database;
    await db.update('chat_sessions', {'is_deleted': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> deleteChatSession(String id) async {
    final db = await database;
    await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
  }
  Future<void> renameSession(String id, String title) async {
    final db = await database;
    await db.update('chat_sessions', {'title': title}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> moveSessionToFolder(String s, String? f) async {
    final db = await database;
    await db.update('chat_sessions', {'folder_id': f}, where: 'id = ?', whereArgs: [s]);
  }
  Future<void> updateSessionArchive(String s, bool a) async {
    final db = await database;
    await db.update('chat_sessions', {'is_archived': a ? 1 : 0}, where: 'id = ?', whereArgs: [s]);
  }
  Future<void> createFolder(String n) async {
    final db = await database;
    await db.insert('folders', {'id': DateTime.now().millisecondsSinceEpoch.toString(), 'name': n});
  }
  Future<List<Map<String, dynamic>>> getFolders() async {
    final db = await database;
    return await db.query('folders');
  }

  // ── MESSAGES ──
  Future<void> insertMessage(ChatMessage msg) async {
    final db = await database;
    await db.insert('chat_messages', msg.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<ChatMessage>> getRecentMessages({String? sessionId, int limit = 50}) async {
    final db = await database;
    final res = sessionId != null ? await db.query('chat_messages', where: 'session_id = ?', limit: limit) : await db.query('chat_messages', limit: limit);
    return res.map((m) => ChatMessage.fromMap(m)).toList();
  }
  Future<void> deleteMessage(String id) async {
    final db = await database;
    await db.delete('chat_messages', where: 'id = ?', whereArgs: [id]);
  }
  Future<List<ChatMessage>> searchMessages(String q, {String? s}) async => [];
  Future<void> clearMessages({String? sessionId}) async {
    final db = await database;
    if (sessionId != null) { await db.delete('chat_messages', where: 'session_id = ?', whereArgs: [sessionId]); }
    else { await db.delete('chat_messages'); }
  }

  // ── MEMORY ──
  Future<void> setMemory(String key, String value, {String category = 'general'}) async {
    final db = await database;
    await db.insert('memories', {'id': key, 'key': key, 'value': value, 'category': category, 'created_at': DateTime.now().toIso8601String(), 'updated_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<String?> getMemory(String key) async {
    final db = await database;
    final res = await db.query('memories', where: 'key = ?', whereArgs: [key]);
    return res.isNotEmpty ? res.first['value'] as String? : null;
  }
  Future<void> deleteMemory(String key) async {
    final db = await database;
    await db.delete('memories', where: 'key = ?', whereArgs: [key]);
  }
  Future<List<MemorySlot>> getAllMemories() async {
    final db = await database;
    final res = await db.query('memories');
    return res.map((m) => MemorySlot.fromMap(m)).toList();
  }
  Future<Map<String, List<String>>> getFullSnapshot() async {
    final tasks = await getTasks();
    return {'tasks': tasks.map((t) => t.title).toList()};
  }

  // ── EVENTS ──
  Future<void> insertEvent(CalendarEvent e) async {
    final db = await database;
    await db.insert('events', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<void> deleteEvent(String id) async {
    final db = await database;
    await db.delete('events', where: 'id = ?', whereArgs: [id]);
  }
  Future<List<CalendarEvent>> getEvents({DateTime? from, DateTime? to}) async {
    final db = await database;
    final res = await db.query('events');
    return res.map((m) => CalendarEvent.fromMap(m)).toList();
  }
  Future<List<CalendarEvent>> getUpcomingEvents({int hours = 24}) async {
    final db = await database;
    final res = await db.query('events');
    return res.map((m) => CalendarEvent.fromMap(m)).toList();
  }

  // ── STUDY ──
  Future<void> insertStudySession(StudySession s) async {
    final db = await database;
    await db.insert('study_sessions', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<StudySession>> getStudySessions({int days = 7}) async {
    final db = await database;
    final res = await db.query('study_sessions');
    return res.map((m) => StudySession.fromMap(m)).toList();
  }
  Future<int> getStudyStreak() async => 0;
  Future<int> getTotalStudyMinutesToday() async => 0;
  Future<bool> hasStudiedToday() async => false;

  // ── ASSIGNMENTS ──
  Future<void> insertAssignment(Assignment a) async {
    final db = await database;
    await db.insert('assignments', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<Assignment>> getAssignments({String? status}) async {
    final db = await database;
    final res = status != null ? await db.query('assignments', where: 'status = ?', whereArgs: [status]) : await db.query('assignments');
    return res.map((m) => Assignment.fromMap(m)).toList();
  }
  Future<void> updateAssignmentGrade(String id, double g) async {
    final db = await database;
    await db.update('assignments', {'grade': g}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> deleteAssignment(String id) async {
    final db = await database;
    await db.delete('assignments', where: 'id = ?', whereArgs: [id]);
  }
  Future<double> calculateGPA() async => 0.0;

  // ── READING ──
  Future<void> insertReadingItem(ReadingItem i) async {
    final db = await database;
    await db.insert('reading_items', i.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<ReadingItem>> getReadingItems({String? status}) async {
    final db = await database;
    final res = status != null ? await db.query('reading_items', where: 'status = ?', whereArgs: [status]) : await db.query('reading_items');
    return res.map((m) => ReadingItem.fromMap(m)).toList();
  }
  Future<void> updateReadingStatus(String id, String status) async {
    final db = await database;
    await db.update('reading_items', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  // ── FINANCE ──
  Future<void> insertExpense(Expense e) async {
    final db = await database;
    await db.insert('expenses', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<void> deleteExpense(String id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }
  Future<List<Expense>> getExpenses({int days = 30}) async {
    final db = await database;
    final res = await db.query('expenses');
    return res.map((m) => Expense.fromMap(m)).toList();
  }
  Future<Map<String, double>> getExpensesByCategory({int days = 30}) async => {};
  Future<double> getTotalExpenses({int days = 30}) async => 0.0;

  // ── MOOD ──
  Future<void> insertMood(MoodEntry e) async {
    final db = await database;
    await db.insert('mood_entries', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<MoodEntry>> getMoodHistory({int days = 30}) async {
    final db = await database;
    final res = await db.query('mood_entries');
    return res.map((m) => MoodEntry.fromMap(m)).toList();
  }
  Future<MoodEntry?> getTodaysMood() async => null;
  Future<double> getAverageEnergy({int days = 7}) async => 0.0;

  // ── STARTUP ──
  Future<void> insertStartupMetrics(StartupMetrics m) async {
    final db = await database;
    await db.insert('startup_metrics', m.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<StartupMetrics?> getLatestStartupMetrics() async {
    final db = await database;
    final res = await db.query('startup_metrics', orderBy: 'date DESC', limit: 1);
    return res.isNotEmpty ? StartupMetrics.fromMap(res.first) : null;
  }
  Future<void> insertInvestor(Investor i) async {
    final db = await database;
    await db.insert('investors', i.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<Investor>> getInvestors() async {
    final db = await database;
    final res = await db.query('investors');
    return res.map((m) => Investor.fromMap(m)).toList();
  }

  // ── AUTH ──
  Future<Map<String, dynamic>?> getUserByUsername(String u) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final usersJson = prefs.getString('zen_users_web') ?? '[]';
        final List<dynamic> list = jsonDecode(usersJson);
        final found = list.firstWhere((user) => user['username'] == u, orElse: () => null);
        return found != null ? Map<String, dynamic>.from(found) : null;
      } catch (e) {
        debugPrint('[ZenDB] Web GetUser Error: $e');
        return null;
      }
    }
    final db = await database;
    final res = await db.query('users', where: 'username = ?', whereArgs: [u]);
    return res.isNotEmpty ? res.first : null;
  }
  Future<void> insertUser(Map<String, dynamic> u) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final usersJson = prefs.getString('zen_users_web') ?? '[]';
        final List<dynamic> list = jsonDecode(usersJson);
        list.add(u);
        await prefs.setString('zen_users_web', jsonEncode(list));
        debugPrint('[ZenDB] Web User Saved: ${u['username']}');
      } catch (e) {
        debugPrint('[ZenDB] Web InsertUser Error: $e');
      }
      return;
    }
    final db = await database;
    await db.insert('users', u, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<Map<String, dynamic>?> authenticateUser(String u, String p) async {
    if (kIsWeb) {
      final user = await getUserByUsername(u);
      if (user != null && user['passphrase_hash'] == p) return user;
      return null;
    }
    final db = await database;
    final res = await db.query('users', where: 'username = ? AND passphrase_hash = ?', whereArgs: [u, p]);
    return res.isNotEmpty ? res.first : null;
  }

  // ── DASHBOARD & WIDGETS ──
  Future<List<Map<String, dynamic>>> getDashboardTiles() async {
    final db = await database;
    return await db.query('dashboard_tiles');
  }
  Future<void> insertDashboardTile(Map<String, dynamic> t) async {
    final db = await database;
    await db.insert('dashboard_tiles', t, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<void> updateDashboardTileData(String id, String d) async {
    final db = await database;
    await db.update('dashboard_tiles', {'data': d}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> deleteDashboardTile(String id) async {
    final db = await database;
    await db.delete('dashboard_tiles', where: 'id = ?', whereArgs: [id]);
  }
  Future<List<WidgetItem>> getHomeWidgets({String? userId}) async {
    final db = await database;
    final res = userId != null ? await db.query('home_widgets', where: 'user_id = ?', whereArgs: [userId]) : await db.query('home_widgets');
    return res.map((m) => WidgetItem.fromMap(m)).toList();
  }
  Future<void> saveHomeWidget(WidgetItem w) async {
    final db = await database;
    await db.insert('home_widgets', w.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
