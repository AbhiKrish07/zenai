import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../core/theme_manager.dart';
import '../core/database.dart';
import '../core/session.dart';
import '../models/task.dart';
import '../models/event.dart';
import '../services/focus_service.dart';
import '../theme.dart';
import 'tasks_screen.dart';

// Screens
import 'chat_screen.dart';
import 'settings_screen.dart';

// Modules
import 'modules/notes_screen.dart';
import 'modules/calendar_screen.dart';
import 'modules/finance_screen.dart';
import 'modules/focus_screen.dart';
import 'modules/mood_screen.dart';
import 'modules/startup_screen.dart';
import 'modules/reading_screen.dart';
import 'modules/memories_screen.dart';
import 'modules/research_screen.dart';
import 'modules/study_screen.dart';
import 'modules/forge_screen.dart';
import 'modules/canvas_screen.dart';

/// ═══════════════════════════════════════════════════════
///   Zen OS — Home Screen (Unified Visual Grid)
///   Page 0: Custom Dashboard, 1: AI, 2: Tasks, 3: Modules
/// ═══════════════════════════════════════════════════════

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({super.key});
  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> with SingleTickerProviderStateMixin {
  final _db = ZenDatabase();
  static const _focusChannel = MethodChannel('com.zen/focus');
  final PageController _pageController = PageController();
  
  // ── State ──
  int _currentPage = 0;
  List<Task> _tasks = [];
  CalendarEvent? _nextEvent;
  String _weather = "--°C";
  String _location = "LOADING";
  String _time = "";
  late Timer _timer;
  String _userName = 'Zen Guest';
  String? _wallpaperPath;
  Color _accentColor = ZenTheme.accent; // Cyan Accent

  // Nav Animation
  bool _isNavVisible = false;
  late AnimationController _navCtrl;
  late Animation<Offset> _navSlide;

  // Configuration
  List<Map<String, dynamic>> _sortedModules = [];
  List<Map<String, dynamic>> _dashboardTiles = [];
  bool _isRearranging = false;

  @override
  void initState() {
    super.initState();
    _time = DateFormat('HH:mm').format(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateFormat('HH:mm').format(DateTime.now());
      if (now != _time) setState(() => _time = now);
    });
    
    _navCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _navSlide = Tween<Offset>(begin: const Offset(1.5, 0), end: Offset.zero).animate(CurvedAnimation(parent: _navCtrl, curve: Curves.easeOutExpo));

    _setSystemUI();
    _loadAllData();
    _fetchWeather();
    _loadModuleOrder();
    _loadDashboardTiles();
    FocusService().onUpdate.listen((_) { if (mounted) setState(() {}); });
  }

  void _setSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final accentHex = prefs.getInt('theme_color'); // Unified with ThemeManager
    final tasksData = await _db.getTasks(includeCompleted: true);
    final upcoming = await _db.getUpcomingEvents(hours: 48);
    await ZenSession().ensureInitialized();

    if (mounted) {
      setState(() {
        if (accentHex != null) _accentColor = Color(accentHex);
        _tasks = tasksData;
        if (upcoming.isNotEmpty) _nextEvent = upcoming.first;
        _userName = ZenSession().activeUserName ?? 'Zen Guest';
      });
      _loadDashboardTiles();
    }
  }

  Future<void> _loadModuleOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final orderJson = prefs.getString('zen_modules_v3');
    final List<Map<String, dynamic>> defaultModules = [
      {'label': 'Quick Notes', 'icon': Icons.sticky_note_2_outlined, 'type': 'notes'},
      {'label': 'Forge IDE', 'icon': Icons.code_rounded, 'type': 'forge'},
      {'label': 'Zen Canvas', 'icon': Icons.brush_rounded, 'type': 'canvas'},
      {'label': 'Calendar', 'icon': Icons.calendar_today_rounded, 'type': 'calendar'},
      {'label': 'Deep Research', 'icon': Icons.science_rounded, 'type': 'research'},
      {'label': 'Tasks', 'icon': Icons.checklist_rounded, 'type': 'tasks'},
      {'label': 'Study Timer', 'icon': Icons.timer_rounded, 'type': 'study'},
      {'label': 'Finance Flow', 'icon': Icons.account_balance_wallet_rounded, 'type': 'finance'},
      {'label': 'Reading List', 'icon': Icons.menu_book_rounded, 'type': 'reading'},
      {'label': 'Startup HQ', 'icon': Icons.rocket_launch_rounded, 'type': 'startup'},
      {'label': 'Mood Map', 'icon': Icons.mood_rounded, 'type': 'mood'},
      {'label': 'Memories', 'icon': Icons.psychology_rounded, 'type': 'memory'},
      {'label': 'Focus Mode', 'icon': Icons.visibility_off_rounded, 'type': 'focus'},
    ];
    if (orderJson != null) {
      try {
        final List<dynamic> saved = json.decode(orderJson);
        final List<Map<String, dynamic>> ordered = [];
        for (var s in saved) {
          if (s is Map && s['isApp'] == true) {
            ordered.add({
              'label': s['label'],
              'type': s['type'],
              'isApp': true,
              'icon': Icons.apps_rounded,
            });
          } else {
            final m = defaultModules.firstWhere((element) => element['type'] == s, orElse: () => {});
            if (m.isNotEmpty) ordered.add(m);
          }
        }
        for (var d in defaultModules) { if (!ordered.any((e) => e['type'] == d['type'])) ordered.add(d); }
        setState(() => _sortedModules = ordered);
      } catch (_) { setState(() => _sortedModules = defaultModules); }
    } else { setState(() => _sortedModules = defaultModules); }
  }

  Future<void> _loadDashboardTiles() async {
    final tiles = await _db.getDashboardTiles();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dashboardTiles = List<Map<String, dynamic>>.from(tiles);
      _wallpaperPath = prefs.getString('zen_wallpaper');
    });
  }

  Future<void> _saveModuleOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final order = _sortedModules.map((e) {
      if (e['isApp'] == true) {
        return {'label': e['label'], 'type': e['type'], 'isApp': true};
      }
      return e['type'];
    }).toList();
    await prefs.setString('zen_modules_v3', json.encode(order));
  }

  Future<void> _fetchWeather() async {
    try {
      final locRes = await http.get(Uri.parse('http://ip-api.com/json')).timeout(const Duration(seconds: 3));
      if (locRes.statusCode == 200) {
        final locData = json.decode(locRes.body);
        final lat = locData['lat'];
        final lon = locData['lon'];
        final city = locData['city'] ?? 'ZEN MODE';
        
        final res = await http.get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true'));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          setState(() {
            _weather = "${data['current_weather']['temperature'].round()}°C";
            _location = city.toUpperCase();
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    _navCtrl.dispose();
    super.dispose();
  }

  void _toggleNav({bool? visible}) {
    setState(() {
      _isNavVisible = visible ?? !_isNavVisible;
      if (_isNavVisible) { _navCtrl.forward(); HapticFeedback.mediumImpact(); }
      else { _navCtrl.reverse(); }
    });
  }

  void _navigateToModule(String type) {
    HapticFeedback.selectionClick();
    Widget? screen;
    switch (type) {
      case 'notes': screen = const NotesModuleScreen(); break;
      case 'tasks': screen = const TasksScreen(); break;
      case 'calendar': screen = const CalendarModuleScreen(); break;
      case 'finance': screen = const FinanceModuleScreen(); break;
      case 'focus': screen = const FocusModeScreen(); break;
      case 'mood': screen = const MoodModuleScreen(); break;
      case 'startup': screen = const StartupModuleScreen(); break;
      case 'reading': screen = const ReadingModuleScreen(); break;
      case 'memory': screen = const MemoriesScreen(); break;
      case 'research': screen = const ResearchScreen(); break;
      case 'study': screen = const StudyModuleScreen(); break;
      case 'forge': screen = const ForgeModuleScreen(); break;
      case 'canvas': screen = const CanvasModuleScreen(); break;
      case 'settings': screen = const SettingsScreen(); break;
      default:
        _launchApp(type);
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen!)).then((_) => _loadAllData());
  }

  Future<void> _launchApp(String data) async {
    if (data.contains('://') || data.startsWith('http')) {
      try {
        final uri = Uri.parse(data);
        if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.externalApplication); }
        else { _showError('Could not launch. Check link or scheme.'); }
      } catch (_) { _showError('Invalid App Link'); }
    } else {
      // Use platform channel for direct package launch
      try {
        await _focusChannel.invokeMethod('openApp', {'package': data});
      } catch (e) {
        _showError('Could not launch app: $data');
      }
    }
  }

  void _showError(String m) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.redAccent)); }
  
  void _showAppDrawer() async {
    final List<dynamic>? apps = await _focusChannel.invokeMethod('getInstalledApps');
    if (apps == null || !mounted) return;
    
    final List<Map<String, dynamic>> appList = apps.map((a) => {
      'name': a['name'].toString(),
      'package': a['package'].toString(),
      'icon': a['icon'],
    }).toList();
    
    if (mounted) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'AppDrawer',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, anim1, anim2) => _ZenAppDrawer(apps: appList, onLaunch: _launchApp),
      );
    }
  }

  void _showAddDashTileSheet() {
    final labelCtrl = TextEditingController();
    final dataCtrl = TextEditingController();
    String type = 'system';
    String selectedModule = 'notes';
    List<Map<String, String>> folderItems = [];
    final apps = {
      'Spotify': 'spotify://',
      'YouTube': 'https://youtube.com',
      'Instagram': 'https://instagram.com',
      'X': 'https://x.com',
      'TikTok': 'https://tiktok.com',
    };
    final modules = [
      'notes', 'forge', 'canvas', 'calendar', 'research', 'assignments', 'study', 'finance', 'reading', 'startup', 'mood', 'memory', 'focus'
    ];

    void selectAppDialog(Function(String, String) onSelected) {
       _selectAppUnified(onSelected);
    }

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(color: Color(0xFF1C1C1E), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Quick Access Focus', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            Row(children: [
              _ChoiceChip(label: 'OS Module', active: type == 'system', onTap: () => setSheetState(() => type = 'system')),
              const SizedBox(width: 8),
              _ChoiceChip(label: 'External App', active: type == 'app', onTap: () => setSheetState(() => type = 'app')),
              const SizedBox(width: 8),
              _ChoiceChip(label: 'Folder', active: type == 'folder', onTap: () => setSheetState(() => type = 'folder')),
            ]),
            const SizedBox(height: 20),
            if (type == 'system') ...[
              DropdownButtonFormField<String>(
                value: selectedModule,
                  items: modules.map((m) => DropdownMenuItem(value: m, child: Text(m.toUpperCase(), style: GoogleFonts.spaceMono(color: Colors.white)))).toList(),
                  decoration: InputDecoration(filled: true, fillColor: Colors.white.withValues(alpha: 0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                  dropdownColor: const Color(0xFF1C1C1E),
                  onChanged: (v) { if (v != null) { setSheetState(() => selectedModule = v); } },
                ),
              const SizedBox(height: 12),
              TextField(controller: labelCtrl, style: GoogleFonts.dmSans(color: Colors.white), decoration: InputDecoration(hintText: 'Display Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), filled: true, fillColor: Colors.white.withValues(alpha: 0.05))),
            ] else if (type == 'app') ...[
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: () => selectAppDialog((name, pkg) => setSheetState(() { labelCtrl.text = name; dataCtrl.text = pkg; })),
                icon: const Icon(Icons.apps_rounded, size: 18),
                label: Text('Select From Installed Apps', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white10), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              )),
              const SizedBox(height: 16),
              Wrap(spacing: 8, children: apps.keys.map((a) => ActionChip(label: Text(a), backgroundColor: Colors.white.withValues(alpha: 0.05), onPressed: () => setSheetState(() { labelCtrl.text = a; dataCtrl.text = apps[a]!; }))).toList()),
              const SizedBox(height: 12),
              TextField(controller: labelCtrl, style: GoogleFonts.dmSans(color: Colors.white), decoration: InputDecoration(hintText: 'App Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), filled: true, fillColor: Colors.white.withValues(alpha: 0.05))),
              const SizedBox(height: 12),
              TextField(controller: dataCtrl, style: GoogleFonts.dmSans(color: Colors.white), decoration: InputDecoration(hintText: 'Package (e.g. com.spotify.music)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), filled: true, fillColor: Colors.white.withValues(alpha: 0.05))),
            ] else if (type == 'folder') ...[
              Text('Items in Folder: ${folderItems.length}', style: GoogleFonts.dmSans(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton(onPressed: () => selectAppDialog((n, p) => setSheetState(() => folderItems.add({'label': n, 'type': 'app', 'data': p}))), child: Text('Add App', style: GoogleFonts.dmSans(fontSize: 12))),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  hint: Text('Add Module', style: GoogleFonts.dmSans(color: Colors.white24, fontSize: 12)),
                  items: modules.map((m) => DropdownMenuItem(value: m, child: Text(m.toUpperCase(), style: GoogleFonts.spaceMono(color: Colors.black, fontSize: 12)))).toList(),
                  onChanged: (v) => setSheetState(() => folderItems.add({'label': v!, 'type': 'system', 'data': v})),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: labelCtrl, style: GoogleFonts.dmSans(color: Colors.white), decoration: InputDecoration(hintText: 'Folder Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), filled: true, fillColor: Colors.white.withValues(alpha: 0.05))),
            ],
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
              onPressed: () async {
                if (labelCtrl.text.isNotEmpty) {
                  String data = type == 'system' ? selectedModule : type == 'app' ? dataCtrl.text.trim() : jsonEncode(folderItems);
                  await _db.insertDashboardTile({'id': const Uuid().v4(), 'label': labelCtrl.text.trim(), 'type': type, 'data': data});
                  if (!context.mounted) return;
                  _loadDashboardTiles(); 
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text('Add to Dash', style: GoogleFonts.dmSans(fontWeight: FontWeight.bold, color: Colors.black)),
            )),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  void _showEditTaskSheet(Task task) {
    final TextEditingController titleCtrl = TextEditingController(text: task.title);
    final TextEditingController descCtrl = TextEditingController(text: task.description);
    String p = task.priority;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(color: Color(0xFF1C1C1E), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.id.isEmpty ? 'New Assignment' : 'Edit Assignment', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            TextField(controller: titleCtrl, style: GoogleFonts.dmSans(color: Colors.white, fontSize: 16), decoration: InputDecoration(hintText: 'Task Title', border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), filled: true, fillColor: Colors.white.withValues(alpha: 0.05))),
            const SizedBox(height: 12),
            TextField(controller: descCtrl, maxLines: 2, style: GoogleFonts.dmSans(color: Colors.white, fontSize: 14), decoration: InputDecoration(hintText: 'Description', border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), filled: true, fillColor: Colors.white.withValues(alpha: 0.05))),
            const SizedBox(height: 16),
            Row(children: [_PriorityChip(label: 'Low', active: p == 'low', color: Colors.blueGrey, onTap: () => setSheetState(() => p = 'low')), const SizedBox(width: 8), _PriorityChip(label: 'Mid', active: p == 'medium', color: Colors.amber, onTap: () => setSheetState(() => p = 'medium')), const SizedBox(width: 8), _PriorityChip(label: 'High', active: p == 'high', color: const Color(0xFFFF4500), onTap: () => setSheetState(() => p = 'high'))]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: GoogleFonts.dmSans(color: const Color(0xFF888888)))),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: () async {
                  if (titleCtrl.text.trim().isNotEmpty) {
                    try {
                      debugPrint('[Zen] Starting task assign process...');
                      final newTask = Task(title: titleCtrl.text.trim(), description: descCtrl.text.trim(), priority: p);
                      if (task.id.isEmpty) { 
                        await _db.insertTask(newTask); 
                        debugPrint('[Zen] Task inserted: ${newTask.id}');
                      } else { 
                        await _db.updateTask(task.copyWith(title: titleCtrl.text.trim(), description: descCtrl.text.trim(), priority: p)); 
                        debugPrint('[Zen] Task updated: ${task.id}');
                      }
                      
                      // Show feedback
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(task.id.isEmpty ? 'Task Assigned Successfully' : 'Task Updated'), backgroundColor: Colors.green.withValues(alpha: 0.2), behavior: SnackBarBehavior.floating));
                      }

                      await _loadAllData();
                      debugPrint('[Zen] Post-assign data reloaded. Total tasks: ${_tasks.length}');
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      debugPrint('[Zen] Assign Error: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.withValues(alpha: 0.2)));
                      }
                    }
                  }
                }, style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(task.id.isEmpty ? 'Assign' : 'Update', style: GoogleFonts.dmSans(fontWeight: FontWeight.bold, color: Colors.black))),
            ]),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        if (_currentPage != 0) {
          _pageController.animateToPage(0, duration: const Duration(milliseconds: 600), curve: Curves.easeOutExpo);
          HapticFeedback.lightImpact();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_wallpaperPath != null && !kIsWeb)
              Positioned.fill(child: Opacity(opacity: 0.4, child: Image.file(File(_wallpaperPath!), fit: BoxFit.cover))),
            if (kIsWeb && _wallpaperPath != null)
              Positioned.fill(child: Opacity(opacity: 0.4, child: Image.network(_wallpaperPath!, fit: BoxFit.cover))),

            // ── RESPONSIVE LAYOUT ──
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                
                if (isWide) {
                  return Row(
                    children: [
                      // Side Navigation
                      _ZenSideNav(
                        accentColor: _accentColor,
                        currentPage: _currentPage,
                        onPageTap: (i) {
                          setState(() => _currentPage = i);
                          _pageController.jumpToPage(i);
                        },
                      ),
                      
                      // Content Area
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: _buildPage(_currentPage),
                        ),
                      ),
                    ],
                  );
                }

                // Mobile Swipable PageView
                return GestureDetector(
                  onHorizontalDragEnd: (details) { if (details.primaryVelocity! < -300) _toggleNav(visible: true); },
                  child: PageView(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (i) => setState(() => _currentPage = i) ,
                    children: [
                      _Page1Focus(userName: _userName, onTap: _navigateToModule, onLaunchApp: _launchApp, onAddTile: _showAddDashTileSheet, onRefresh: _loadAllData, dashboardTiles: _dashboardTiles, nextEvent: _nextEvent, tasks: _tasks, accentColor: _accentColor, onSelectApp: _selectAppUnified),
                      _Page2ZenAI(onRefresh: _loadAllData),
                      _Page3Tasks(tasks: _tasks, db: _db, accentColor: _accentColor, onRefresh: _loadAllData, onEdit: _showEditTaskSheet, onAdd: () => _showEditTaskSheet(Task(id: '', title: '', priority: 'medium', createdAt: DateTime.now(), updatedAt: DateTime.now()))),
                      _Page4Modules(modules: _sortedModules, isRearranging: _isRearranging, onToggleRearrange: () => setState(() => _isRearranging = !_isRearranging), onReorder: (old, newVal) {
                        setState(() { if (newVal > old) newVal -= 1; final m = _sortedModules.removeAt(old); _sortedModules.insert(newVal, m); });
                        _saveModuleOrder();
                      }, onTap: (t) => _isRearranging ? null : _navigateToModule(t), accentColor: _accentColor, onAddApp: _addAppModule),
                    ],
                  ),
                );
              },
            ),

            // ── STATUS BAR ──
            Positioned(top: 0, left: 0, right: 0, child: _ZenStatusBar(time: _time, weather: _weather, location: _location, onSettings: () => _navigateToModule('settings'), onAppDrawer: _showAppDrawer, focusMinutes: FocusService().isRunning ? (FocusService().secondsRemaining ~/ 60) : null)),

            // ── EDGE TRIGGER ──
            Positioned(right: 0, top: 0, bottom: 0, width: 30, child: GestureDetector(onHorizontalDragUpdate: (d) { if (d.delta.dx < -10) _toggleNav(visible: true); }, child: Container(color: Colors.transparent))),

            // ── SAMSUNG DRAWER ──
            if (_isNavVisible) Positioned.fill(child: GestureDetector(onTap: () => _toggleNav(visible: false), child: Container(color: Colors.black26))),
            SlideTransition(
              position: _navSlide,
              child: Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(right: 20), child: _ZenVerticalNav(accentColor: _accentColor, currentPage: _currentPage, onPageTap: (i) { _pageController.animateToPage(i, duration: const Duration(milliseconds: 600), curve: Curves.easeOutExpo); _toggleNav(visible: false); }))),
            ),
          ],
        ),
      ),
    );
  }

  void _selectAppUnified(Function(String, String) onSelected) async {
    final List<dynamic>? apps = await _focusChannel.invokeMethod('getInstalledApps');
    if (apps == null || !mounted) return;
    final List<Map<String, dynamic>> appList = apps.map((a) => {
      'name': a['name'].toString(),
      'package': a['package'].toString(),
      'icon': a['icon'],
    }).toList();
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (c) => _DashboardAppSelector(apps: appList),
      ).then((selected) {
        if (selected != null && mounted) onSelected(selected['name']!, selected['package']!);
      });
    }
  }

  void _addAppModule() {
    _selectAppUnified((name, package) {
      setState(() {
        _sortedModules.insert(0, {
          'label': name,
          'type': package,
          'icon': Icons.apps_rounded,
          'isApp': true,
        });
      });
      _saveModuleOrder();
    });
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0: return _Page1Focus(userName: _userName, onTap: _navigateToModule, onLaunchApp: _launchApp, onAddTile: _showAddDashTileSheet, onRefresh: _loadAllData, dashboardTiles: _dashboardTiles, nextEvent: _nextEvent, tasks: _tasks, accentColor: _accentColor, onSelectApp: _selectAppUnified);
      case 1: return _Page2ZenAI(onRefresh: _loadAllData);
      case 2: return _Page3Tasks(key: ValueKey('tasks_page_${_tasks.length}_${_currentPage}'), tasks: _tasks, db: _db, accentColor: _accentColor, onRefresh: _loadAllData, onEdit: _showEditTaskSheet, onAdd: () => _showEditTaskSheet(Task(id: '', title: '', priority: 'medium', createdAt: DateTime.now(), updatedAt: DateTime.now())));
      case 3: return _Page4Modules(modules: _sortedModules, isRearranging: _isRearranging, onToggleRearrange: () => setState(() => _isRearranging = !_isRearranging), onReorder: (old, newVal) {
        setState(() { if (newVal > old) newVal -= 1; final m = _sortedModules.removeAt(old); _sortedModules.insert(newVal, m); });
        _saveModuleOrder();
      }, onTap: (t) => _isRearranging ? null : _navigateToModule(t), accentColor: _accentColor, onAddApp: _addAppModule);
      default: return const SizedBox();
    }
  }
}

class _ZenSideNav extends StatelessWidget {
  final Color accentColor;
  final int currentPage;
  final Function(int) onPageTap;

  const _ZenSideNav({required this.accentColor, required this.currentPage, required this.onPageTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E).withValues(alpha: 0.5),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('ZEN AI', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: accentColor, letterSpacing: 2)),
          ),
          const SizedBox(height: 100),
          _ZenSideNavItem(icon: Icons.grid_view_rounded, active: currentPage == 0, accent: accentColor, label: 'FOCUS', onTap: () => onPageTap(0)),
          const SizedBox(height: 16),
          _ZenSideNavItem(icon: Icons.auto_awesome_rounded, active: currentPage == 1, accent: accentColor, label: 'ZEN AI', onTap: () => onPageTap(1)),
          const SizedBox(height: 16),
          _ZenSideNavItem(icon: Icons.checklist_rounded, active: currentPage == 2, accent: accentColor, label: 'TASKS', onTap: () => onPageTap(2)),
          const SizedBox(height: 16),
          _ZenSideNavItem(icon: Icons.auto_awesome_mosaic_rounded, active: currentPage == 3, accent: accentColor, label: 'HUB', onTap: () => onPageTap(3)),
          const Spacer(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _ZenSideNavItem extends StatelessWidget {
  final IconData icon; final bool active; final Color accent; final String label; final VoidCallback onTap;
  const _ZenSideNavItem({required this.icon, required this.active, required this.accent, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: active ? accent : Colors.white24, size: 20),
              const SizedBox(width: 16),
              Text(label, style: GoogleFonts.ibmPlexMono(fontSize: 11, fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.white24, letterSpacing: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZenStatusBar extends StatelessWidget {
  final String time; final String weather; final String location; final VoidCallback onSettings; final VoidCallback onAppDrawer; final int? focusMinutes;
  const _ZenStatusBar({required this.time, required this.weather, required this.location, required this.onSettings, required this.onAppDrawer, this.focusMinutes});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.fromLTRB(20, 54, 20, 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Text(time, style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(width: 8),
          Container(width: 3, height: 3, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(weather, style: GoogleFonts.spaceGrotesk(fontSize: 14, color: const Color(0xFF888888))),
          const SizedBox(width: 8),
          Container(width: 3, height: 3, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(location, style: GoogleFonts.spaceGrotesk(fontSize: 14, color: const Color(0xFF888888))),
          if (focusMinutes != null) ...[
            const SizedBox(width: 12),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: ZenTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: ZenTheme.accent.withValues(alpha: 0.3))), child: Row(children: [
              const Icon(Icons.timer_rounded, size: 10, color: ZenTheme.accent),
              const SizedBox(width: 6),
              Text('${focusMinutes}M', style: GoogleFonts.spaceMono(fontSize: 9, fontWeight: FontWeight.bold, color: ZenTheme.accent)),
            ])),
          ],
        ]),
        Row(children: [
          IconButton(onPressed: onAppDrawer, icon: const Icon(Icons.grid_view_rounded, color: Colors.white38, size: 20)),
          const SizedBox(width: 12),
          IconButton(onPressed: onSettings, icon: const Icon(Icons.settings_outlined, color: Color(0xFF888888), size: 22)),
        ]),
    ]));
  }
}

// ─── VERTICAL NAVIGATION ─────────────────────────────────────────────────────
class _ZenVerticalNav extends StatelessWidget {
  final Color accentColor; final int currentPage; final Function(int) onPageTap;
  const _ZenVerticalNav({required this.accentColor, required this.currentPage, required this.onPageTap});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 10), decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.95), borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.white.withValues(alpha: 0.08)), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40, spreadRadius: 10)]), child: Column(mainAxisSize: MainAxisSize.min, children: [
      _NavIconVertical(icon: Icons.grid_view_rounded, active: currentPage == 0, accent: accentColor, onTap: () => onPageTap(0)),
      const SizedBox(height: 28),
      _NavIconVertical(icon: Icons.auto_awesome_rounded, active: currentPage == 1, accent: accentColor, onTap: () => onPageTap(1)),
      const SizedBox(height: 28),
      _NavIconVertical(icon: Icons.checklist_rounded, active: currentPage == 2, accent: accentColor, onTap: () => onPageTap(2)),
      const SizedBox(height: 28),
      _NavIconVertical(icon: Icons.auto_awesome_mosaic_rounded, active: currentPage == 3, accent: accentColor, onTap: () => onPageTap(3)),
    ]));
  }
}

class _NavIconVertical extends StatelessWidget {
  final IconData icon; final bool active; final Color accent; final VoidCallback onTap;
  const _NavIconVertical({required this.icon, required this.active, required this.accent, required this.onTap});
  @override
  Widget build(BuildContext context) { return GestureDetector(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 300), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: active ? accent.withValues(alpha: 0.12) : Colors.transparent, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: active ? accent : const Color(0xFF666666), size: 26))); }
}




// ─── PAGE 0: DASHBOARD ───────────────────────────────────────────────────────
class _Page1Focus extends StatelessWidget {
  final Function(String) onTap; final Function(String) onLaunchApp; final VoidCallback onAddTile; final RefreshCallback onRefresh; final List<Map<String, dynamic>> dashboardTiles; final CalendarEvent? nextEvent; final List<Task> tasks; final Color accentColor; final String userName; final Function(Function(String, String)) onSelectApp;
  const _Page1Focus({required this.onTap, required this.onLaunchApp, required this.onAddTile, required this.onRefresh, required this.dashboardTiles, this.nextEvent, required this.tasks, required this.accentColor, required this.userName, required this.onSelectApp});

  @override
  Widget build(BuildContext context) {
    final folders = dashboardTiles.where((t) => t['type'] == 'folder').toList();
    final nonFolders = dashboardTiles.where((t) => t['type'] != 'folder').toList();

    return RefreshIndicator(
      color: accentColor, backgroundColor: const Color(0xFF1C1C1E), onRefresh: onRefresh,
      child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 80, 20, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hi, ${userName.split('@')[0]}', style: GoogleFonts.syne(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.5)),
        Text('Ready for your deep session?', style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white38)),
        const SizedBox(height: 24),
        SizedBox(
          height: 120,
          child: Row(children: [
            Expanded(child: _NextEventSnippet(event: nextEvent, accentColor: accentColor, onTap: () => onTap('calendar'))),
            const SizedBox(width: 16),
            Expanded(child: _TaskPrioritySnippet(tasks: tasks, accentColor: accentColor, onTap: () => onTap('tasks'))),
          ]),
        ),
        const SizedBox(height: 24),
        if (folders.isNotEmpty) ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.2),
            itemCount: folders.length,
            itemBuilder: (context, i) {
              final f = folders[i];
              return _FolderTileInteractive(id: f['id'], label: f['label'], data: f['data'], onUpdate: onRefresh, onTap: onTap, onLaunch: onLaunchApp, onSelectApp: onSelectApp);
            },
          ),
          const SizedBox(height: 20),
        ],
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(nonFolders.isEmpty ? '' : 'APP SHORTCUTS', style: GoogleFonts.spaceMono(fontSize: 10, color: Colors.white12, letterSpacing: 1.5)),
          IconButton(onPressed: onAddTile, icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white12, size: 18))
        ]),
        Expanded(child: ListView(physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()), children: [
          ...nonFolders.map((t) => _FocusTileInteractive(id: t['id'], label: t['label'], type: t['type'], data: t['data'], onTap: onTap, onLaunch: onLaunchApp, onUpdate: onRefresh)),
          if (dashboardTiles.isEmpty) ...[
            _FocusTile(label: 'Notes', type: 'notes', onTap: onTap),
            _FocusTile(label: 'Forge', type: 'forge', onTap: onTap),
            _FocusTile(label: 'Canvas', type: 'canvas', onTap: onTap),
            _FocusTile(label: 'Research', type: 'research', onTap: onTap),
          ]
        ])),
      ]))),
    );
  }
}

class _FolderTileInteractive extends StatelessWidget {
  final String id; final String label; final String? data; final VoidCallback onUpdate; final Function(String) onTap; final Function(String) onLaunch; final Function(Function(String, String)) onSelectApp;
  const _FolderTileInteractive({required this.id, required this.label, this.data, required this.onUpdate, required this.onTap, required this.onLaunch, required this.onSelectApp});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showFolderItems(context, id, label, data ?? '[]', onTap, onLaunch, onUpdate, onSelectApp),
      onLongPress: () => _showTileManagementSheet(context, id, label, onUpdate),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.folder_rounded, color: Colors.white30, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFF0F0F0)))),
        ]),
      ),
    );
  }

  void _showFolderItems(BuildContext context, String id, String folderName, String jsonData, Function(String) onTap, Function(String) onLaunch, VoidCallback onUpdate, Function(Function(String, String)) onSelectApp) {
    _showFolderModal(context, id, folderName, jsonData, onTap, onLaunch, onUpdate, onSelectApp);
  }
}

void _showFolderModal(BuildContext context, String id, String folderName, String jsonData, Function(String) onTap, Function(String) onLaunch, VoidCallback onUpdate, Function(Function(String, String)) onSelectApp) {
  final db = ZenDatabase();
  final List<dynamic> items = jsonDecode(jsonData);

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (c) => StatefulBuilder(builder: (context, setModalState) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(folderName.toUpperCase(), style: GoogleFonts.spaceMono(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
              IconButton(onPressed: () => _addItemToExistingFolder(context, id, items, (newItems) {
                setModalState(() { items.clear(); items.addAll(newItems); });
                onUpdate();
              }, onSelectApp), icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFFFF4500), size: 24)),
            ]),
            const SizedBox(height: 20),
            ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final it = items[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(it['type'] == 'system' ? Icons.settings_input_component_rounded : Icons.apps_rounded, color: Colors.white24, size: 20),
                  title: Text(it['label'], style: GoogleFonts.dmSans(color: Colors.white, fontSize: 16)),
                  trailing: IconButton(icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white10, size: 18), onPressed: () async {
                    items.removeAt(i);
                    await db.updateDashboardTileData(id, jsonEncode(items));
                    setModalState(() {});
                    onUpdate();
                  }),
                  onTap: () {
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    if (it['type'] == 'system') { onTap(it['data']); } else { onLaunch(it['data']); }
                  },
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    }),
  );
}

void _addItemToExistingFolder(BuildContext context, String folderId, List<dynamic> currentItems, Function(List<dynamic>) onComplete, Function(Function(String, String)) onSelectApp) {
  final modules = ['notes', 'forge', 'canvas', 'calendar', 'research', 'assignments', 'study', 'finance', 'reading', 'startup', 'mood', 'memory', 'focus'];
  final db = ZenDatabase();
  
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    builder: (c) => Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ADD TO FOLDER', style: GoogleFonts.spaceMono(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            hint: const Text('Select System Module', style: TextStyle(color: Colors.white30)),
            dropdownColor: const Color(0xFF1C1C1E),
            items: modules.map((m) => DropdownMenuItem(value: m, child: Text(m.toUpperCase(), style: const TextStyle(color: Colors.white)))).toList(),
            onChanged: (v) async {
              if (v != null) {
                currentItems.add({'label': v, 'type': 'system', 'data': v});
                await db.updateDashboardTileData(folderId, jsonEncode(currentItems));
                if (c.mounted) Navigator.pop(c);
                onComplete(currentItems);
              }
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => onSelectApp((name, package) async {
                currentItems.add({'label': name, 'type': 'app', 'data': package});
                await db.updateDashboardTileData(folderId, jsonEncode(currentItems));
                if (c.mounted) Navigator.pop(c);
                onComplete(currentItems);
              }),
              icon: const Icon(Icons.apps_rounded, size: 18),
              label: Text('Select From Installed Apps', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white10),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FocusTileInteractive extends StatelessWidget {
  final String id; final String label; final String type; final String? data; final Function(String) onTap; final Function(String) onLaunch; final VoidCallback onUpdate;
  const _FocusTileInteractive({required this.id, required this.label, required this.type, this.data, required this.onTap, required this.onLaunch, required this.onUpdate});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (type == 'system') {
          onTap(data ?? '');
        } else {
          onLaunch(data ?? '');
        }
      },
      onLongPress: () => _showTileManagementSheet(context, id, label, onUpdate),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Row(children: [
          Text(label, style: GoogleFonts.dmSans(fontSize: 32, fontWeight: FontWeight.normal, color: const Color(0xFFF0F0F0), letterSpacing: -1)),
          const Spacer(),
          if (type == 'app') const Icon(Icons.open_in_new_rounded, color: Colors.white10, size: 16),
      ])),
    );
  }
}

void _showTileManagementSheet(BuildContext context, String id, String currentLabel, VoidCallback onUpdate) {
  final db = ZenDatabase();
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    builder: (c) => Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('MANAGE TILE', style: GoogleFonts.spaceMono(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          ListTile(leading: const Icon(Icons.edit_rounded, color: Colors.white54), title: const Text('Rename', style: TextStyle(color: Colors.white)), onTap: () {
            Navigator.pop(c);
            _showRenameTileDialog(context, id, currentLabel, onUpdate);
          }),
          ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), title: const Text('Delete', style: TextStyle(color: Colors.redAccent)), onTap: () async {
            await db.deleteDashboardTile(id);
            if (!context.mounted) return;
            Navigator.pop(c);
            onUpdate();
          }),
        ],
      ),
    ),
  );
}

void _showRenameTileDialog(BuildContext context, String id, String currentLabel, VoidCallback onUpdate) {
  final ctrl = TextEditingController(text: currentLabel);
  final db = ZenDatabase();
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      title: Text('RENAME TILE', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
      content: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'New Label', hintStyle: TextStyle(color: Colors.white24))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCEL')),
        ElevatedButton(onPressed: () async {
          final tiles = await db.getDashboardTiles();
          final tile = tiles.firstWhere((t) => t['id'] == id);
          final newTile = Map<String, dynamic>.from(tile);
          newTile['label'] = ctrl.text.trim();
          await db.insertDashboardTile(newTile);
          if (!context.mounted) return;
          Navigator.pop(c);
          onUpdate();
        }, child: const Text('SAVE')),
      ],
    ),
  );
}

// ─── PAGE 1: ZEN AI (FULL SCREEN) ───────────────────────────────────────────
class _Page2ZenAI extends StatefulWidget {
  final VoidCallback onRefresh;
  const _Page2ZenAI({required this.onRefresh});
  @override
  State<_Page2ZenAI> createState() => _Page2ZenAIState();
}
class _Page2ZenAIState extends State<_Page2ZenAI> {
  @override
  Widget build(BuildContext context) { return Container(padding: const EdgeInsets.only(top: 80), child: ChatScreen(onStateChanged: widget.onRefresh)); }
}

// ─── PAGE 2: ASSIGNMENTS (FULL PAGE) ─────────────────────────────────────────
class _Page3Tasks extends StatefulWidget {
  final List<Task> tasks; final ZenDatabase db; final Color accentColor; final VoidCallback onRefresh; final Function(Task) onEdit; final VoidCallback onAdd;
  const _Page3Tasks({super.key, required this.tasks, required this.db, required this.accentColor, required this.onRefresh, required this.onEdit, required this.onAdd});
  @override State<_Page3Tasks> createState() => _Page3TasksState();
}
class _Page3TasksState extends State<_Page3Tasks> {
  String _filter = 'pending';
  String _priorityFilter = 'all';
  bool _sortByPriority = false;

  int _pScore(String p) => p == 'high' ? 3 : (p == 'medium' ? 2 : 1);

  @override
  Widget build(BuildContext context) {
    final filtered = widget.tasks.where((t) { 
      if (_filter == 'pending' && t.completed) return false;
      if (_filter == 'completed' && !t.completed) return false;
      if (_priorityFilter != 'all' && t.priority != _priorityFilter) return false;
      return true;
    }).toList();

    if (_sortByPriority) {
      filtered.sort((a,b) {
        int c = _pScore(b.priority).compareTo(_pScore(a.priority));
        if (c != 0) return c;
        return b.createdAt.compareTo(a.createdAt);
      });
    } else {
      filtered.sort((a,b) {
        int c = b.aiScore.compareTo(a.aiScore);
        if (c != 0) return c;
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Widget - Clean and minimal
          Container(
            padding: const EdgeInsets.fromLTRB(28, 80, 24, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tasks', style: GoogleFonts.dmSans(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5)),
                    Text('${filtered.length} tasks synced', style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white38)),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () { 
                        HapticFeedback.mediumImpact(); 
                        widget.onRefresh(); 
                      }, 
                      icon: Icon(Icons.sync_rounded, color: widget.accentColor.withValues(alpha: 0.6), size: 22)
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () => setState(() => _sortByPriority = !_sortByPriority), 
                      icon: Icon(_sortByPriority ? Icons.sort_rounded : Icons.auto_awesome_rounded, color: _sortByPriority ? widget.accentColor : Colors.white24, size: 22)
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: widget.onAdd, 
                      icon: Icon(Icons.add_circle_outline_rounded, color: widget.accentColor, size: 28)
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Filters - Horizontal scrollable
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _FilterChip(label: 'Pending', active: _filter == 'pending', onTap: () => setState(() => _filter = 'pending')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Done', active: _filter == 'completed', onTap: () => setState(() => _filter = 'completed')),
                  const SizedBox(width: 16),
                  Container(width: 1, height: 16, color: Colors.white10),
                  const SizedBox(width: 16),
                  _FilterChip(label: 'All', active: _priorityFilter == 'all', onTap: () => setState(() => _priorityFilter = 'all')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'High', active: _priorityFilter == 'high', color: const Color(0xFFFF4500), onTap: () => setState(() => _priorityFilter = 'high')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Med', active: _priorityFilter == 'medium', color: Colors.amber, onTap: () => setState(() => _priorityFilter = 'medium')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Low', active: _priorityFilter == 'low', color: Colors.blueAccent, onTap: () => setState(() => _priorityFilter = 'low')),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // List Area
          Expanded(
            child: RefreshIndicator(
              color: widget.accentColor,
              backgroundColor: const Color(0xFF1C1C1E),
              onRefresh: () async { widget.onRefresh(); },
              child: filtered.isEmpty 
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Container(
                      height: MediaQuery.of(context).size.height * 0.5,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.checklist_rounded, size: 64, color: widget.accentColor.withValues(alpha: 0.1)),
                          const SizedBox(height: 16),
                          Text('No Tasks Here', style: GoogleFonts.dmSans(color: Colors.white38, fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            _filter == 'pending' ? 'Everything caught up! Time to relax.' : 'No completed tasks found.', 
                            textAlign: TextAlign.center,
                            style: GoogleFonts.dmSans(color: Colors.white12, fontSize: 13)
                          ),
                          if (_filter == 'pending') ...[
                            const SizedBox(height: 32),
                            InkWell(
                              onTap: widget.onAdd,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
                                  borderRadius: BorderRadius.circular(16)
                                ),
                                child: Text('Add New Task', style: GoogleFonts.dmSans(color: widget.accentColor, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final t = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Dismissible(
                          key: Key(t.id),
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20),
                            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                            child: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 24)
                          ),
                          secondaryBackground: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                            child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24)
                          ),
                          onDismissed: (dir) async {
                            if (dir == DismissDirection.endToStart) {
                              await widget.db.deleteTask(t.id);
                            } else {
                              if (t.completed) {
                                await widget.db.uncompleteTask(t.id);
                              } else {
                                await widget.db.completeTask(t.id);
                              }
                            }
                            HapticFeedback.mediumImpact();
                            widget.onRefresh();
                          },
                          child: _TaskRowV6(
                            task: t,
                            onEdit: () => widget.onEdit(t),
                            onToggle: () async {
                              HapticFeedback.lightImpact();
                              if (t.completed) {
                                await widget.db.uncompleteTask(t.id);
                              } else {
                                await widget.db.completeTask(t.id);
                              }
                              widget.onRefresh();
                            }
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── PAGE 3: MODULES GRID (FULL PAGE) ────────────────────────────────────────
class _Page4Modules extends StatelessWidget {
  final List<Map<String, dynamic>> modules; final bool isRearranging; final VoidCallback onToggleRearrange; final Function(int, int) onReorder; final Function(String) onTap; final Color accentColor; final VoidCallback onAddApp;
  const _Page4Modules({required this.modules, required this.isRearranging, required this.onToggleRearrange, required this.onReorder, required this.onTap, required this.accentColor, required this.onAddApp});
  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(28, 80, 28, 40), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Module Hub', style: GoogleFonts.dmSans(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          Row(children: [
            IconButton(onPressed: onAddApp, icon: const Icon(Icons.add_box_outlined, color: Colors.white24, size: 24)),
            IconButton(onPressed: onToggleRearrange, icon: Icon(isRearranging ? Icons.check_circle_rounded : Icons.reorder_rounded, color: isRearranging ? Colors.green : Colors.white24)),
          ]),
        ]),
        const SizedBox(height: 24),
        Expanded(child: isRearranging ? ReorderableListView.builder(itemCount: modules.length, onReorder: onReorder, itemBuilder: (context, i) => ListTile(key: Key(modules[i]['type']), leading: Icon(modules[i]['icon'], color: accentColor.withValues(alpha: 0.5)), title: Text(modules[i]['label'], style: const TextStyle(color: Colors.white)), trailing: const Icon(Icons.drag_handle, color: Colors.white12))) : GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: MediaQuery.of(context).size.width > 900 ? 5 : (MediaQuery.of(context).size.width > 600 ? 3 : 2), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.0), itemCount: modules.length, itemBuilder: (context, i) => _ModuleCard(label: modules[i]['label'], icon: modules[i]['icon'], type: modules[i]['type'], onTap: onTap, accentColor: accentColor)))
    ])));
  }
}

// ─── SHARED COMPONENTS ───────────────────────────────────────────────────────
class _TaskRowV6 extends StatelessWidget {
  final Task task; final VoidCallback onEdit; final VoidCallback onToggle;
  const _TaskRowV6({required this.task, required this.onEdit, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    Color pCol = Colors.white10; if (task.priority == 'high') { pCol = const Color(0xFFFF4500); } else if (task.priority == 'medium') { pCol = Colors.amber.withValues(alpha: 0.6); }
    return InkWell(onTap: onEdit, onLongPress: onToggle, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8), child: Row(children: [
        GestureDetector(onTap: onToggle, child: Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: task.completed ? Colors.green : pCol, width: 2), color: task.completed ? Colors.green : Colors.transparent), child: task.completed ? const Icon(Icons.check, size: 12, color: Colors.black) : null)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(task.title, style: GoogleFonts.dmSans(fontSize: 16, color: task.completed ? const Color(0xFF444444) : Colors.white, decoration: task.completed ? TextDecoration.lineThrough : null)), if (task.description.isNotEmpty) Text(task.description, style: GoogleFonts.dmSans(fontSize: 11, color: const Color(0xFF555555)))]))
        ,if (!task.completed) Text(task.priority.toUpperCase(), style: GoogleFonts.spaceMono(fontSize: 9, color: pCol, fontWeight: FontWeight.bold, letterSpacing: 1)),
    ])));
  }
}

class _ModuleCard extends StatelessWidget {
  final String label; final IconData icon; final String type; final Function(String) onTap; final Color accentColor;
  const _ModuleCard({required this.label, required this.icon, required this.type, required this.onTap, required this.accentColor});
  @override
  Widget build(BuildContext context) { return GestureDetector(onTap: () => onTap(type), child: Container(decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.04))), padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: accentColor.withValues(alpha: 0.4), size: 24), Text(label, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))]))); }
}

class _NextEventSnippet extends StatelessWidget {
  final CalendarEvent? event; final Color accentColor; final VoidCallback onTap;
  const _NextEventSnippet({this.event, required this.accentColor, required this.onTap});
  @override
  Widget build(BuildContext context) { return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(Icons.calendar_today_rounded, color: accentColor, size: 18)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Next Event', style: GoogleFonts.dmSans(fontSize: 11, color: const Color(0xFF888888), letterSpacing: 0.5)), const SizedBox(height: 2), Text(event?.title ?? 'None Scheduled', overflow: TextOverflow.ellipsis, maxLines: 1, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))]))]))); }
}

class _TaskPrioritySnippet extends StatelessWidget {
  final List<Task> tasks; final Color accentColor; final VoidCallback onTap;
  const _TaskPrioritySnippet({required this.tasks, required this.accentColor, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))), child: Row(children: [
        GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(Icons.checklist_rounded, color: accentColor, size: 18))),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tasks', style: GoogleFonts.dmSans(fontSize: 11, color: const Color(0xFF888888), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          if (tasks.where((t) => !t.completed).isEmpty) Text('Clear!', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white24))
          else Column(crossAxisAlignment: CrossAxisAlignment.start, children: () {
            final all = List<Task>.from(tasks);
            all.sort((a, b) {
              if (!a.completed && b.completed) return -1;
              if (a.completed && !b.completed) return 1;
              int pA = a.priority == 'high' ? 3 : (a.priority == 'medium' ? 2 : 1);
              int pB = b.priority == 'high' ? 3 : (b.priority == 'medium' ? 2 : 1);
              return pB.compareTo(pA);
            });
            return all.take(2).map((t) => GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                final db = ZenDatabase();
                if (t.completed) { await db.uncompleteTask(t.id); }
                else { await db.completeTask(t.id); }
                onTap();
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: t.completed ? Colors.white24 : Colors.white.withValues(alpha: 0.9), decoration: t.completed ? TextDecoration.lineThrough : null)),
              ),
            )).toList();
          }()),
        ]))
    ]));
  }
}

class _FocusTile extends StatelessWidget {
  final String label; final String type; final Function(String) onTap;
  const _FocusTile({required this.label, required this.type, required this.onTap});
  @override
  Widget build(BuildContext context) { return InkWell(onTap: () => onTap(type), child: Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text(label, style: GoogleFonts.dmSans(fontSize: 32, fontWeight: FontWeight.normal, color: const Color(0xFFF0F0F0), letterSpacing: -1)))); }
}

class _ChoiceChip extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _ChoiceChip({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) { return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: active ? Colors.white : Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20)), child: Text(label, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.w400, color: active ? Colors.black : const Color(0xFF888888))))); }
}

class _FilterChip extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap; final Color color;
  const _FilterChip({required this.label, required this.active, required this.onTap, this.color = const Color(0xFFFF4500)});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? color.withValues(alpha: 0.5) : Colors.transparent, width: 1),
        ),
        child: Text(label.toUpperCase(), style: GoogleFonts.spaceMono(fontSize: 10, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? color : Colors.white24, letterSpacing: 1)),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final String label; final bool active; final Color color; final VoidCallback onTap;
  const _PriorityChip({required this.label, required this.active, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) { return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: active ? color.withValues(alpha: 0.2) : Colors.transparent, borderRadius: BorderRadius.circular(10), border: Border.all(color: active ? color : Colors.white10)), child: Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: active ? color : Colors.white24, fontWeight: active ? FontWeight.bold : FontWeight.normal)))); }
}

class _DashboardAppSelector extends StatefulWidget {
  final List<Map<String, dynamic>> apps;
  const _DashboardAppSelector({required this.apps});
  @override State<_DashboardAppSelector> createState() => _DashboardAppSelectorState();
}
class _DashboardAppSelectorState extends State<_DashboardAppSelector> {
  late List<Map<String, dynamic>> _filtered; final _searchCtrl = TextEditingController();
  @override void initState() { super.initState(); _filtered = widget.apps; }
  void _filter(String q) { setState(() { _filtered = widget.apps.where((a) => a['name']!.toLowerCase().contains(q.toLowerCase())).toList(); }); }
  @override Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Select App', style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.bold)),
      content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [
        TextField(controller: _searchCtrl, onChanged: _filter, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Search...', hintStyle: const TextStyle(color: Colors.white24), prefixIcon: const Icon(Icons.search, color: Colors.white54), filled: true, fillColor: Colors.white.withValues(alpha: 0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        const SizedBox(height: 16),
        Expanded(child: ListView.builder(itemCount: _filtered.length, itemBuilder: (context, i) => ListTile(
          leading: _filtered[i]['icon'] != null ? Container(width: 32, height: 32, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: MemoryImage(_filtered[i]['icon'] as Uint8List)))) : const Icon(Icons.apps_rounded, color: Colors.white24),
          title: Text(_filtered[i]['name']!, style: const TextStyle(color: Colors.white, fontSize: 13)), subtitle: Text(_filtered[i]['package']!, style: const TextStyle(color: Colors.white38, fontSize: 9)), onTap: () => Navigator.pop(context, _filtered[i]))))
      ])),
    );
  }
}

class _ZenAppDrawer extends StatefulWidget {
  final List<Map<String, dynamic>> apps; final Function(String) onLaunch;
  const _ZenAppDrawer({required this.apps, required this.onLaunch});
  @override State<_ZenAppDrawer> createState() => _ZenAppDrawerState();
}
class _ZenAppDrawerState extends State<_ZenAppDrawer> {
  late List<Map<String, dynamic>> _filtered; final _searchCtrl = TextEditingController();
  @override void initState() { super.initState(); _filtered = widget.apps; }
  void _filter(String q) { setState(() { _filtered = widget.apps.where((a) => a['name']!.toLowerCase().contains(q.toLowerCase())).toList(); }); }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      body: SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Applications', style: GoogleFonts.syne(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white54))]),
        const SizedBox(height: 24),
        TextField(controller: _searchCtrl, autofocus: true, onChanged: _filter, style: GoogleFonts.dmSans(color: Colors.white), decoration: InputDecoration(hintText: 'Type to search...', hintStyle: const TextStyle(color: Colors.white24), prefixIcon: const Icon(Icons.search, color: Colors.white54), filled: true, fillColor: Colors.white.withValues(alpha: 0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none))),
        const SizedBox(height: 32),
        Expanded(child: GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 16, mainAxisSpacing: 24, childAspectRatio: 0.8), itemCount: _filtered.length, itemBuilder: (context, i) {
          final app = _filtered[i];
          return GestureDetector(onTap: () { Navigator.pop(context); widget.onLaunch(app['package']!); }, child: Column(children: [
              Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)), child: app['icon'] != null ? Image.memory(app['icon'] as Uint8List, width: 48, height: 48, filterQuality: FilterQuality.medium) : const Icon(Icons.apps_rounded, color: Colors.white24, size: 40)),
              const SizedBox(height: 10),
              Text(app['name']!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: GoogleFonts.dmSans(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.normal)),
          ]));
        }))
      ]))),
    );
  }
}
