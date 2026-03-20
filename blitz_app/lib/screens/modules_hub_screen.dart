import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import 'modules/calendar_screen.dart';
import 'modules/study_screen.dart';
import 'modules/assignments_screen.dart';
import 'modules/reading_screen.dart';
import 'modules/startup_screen.dart';
import 'modules/finance_screen.dart';
import 'modules/mood_screen.dart';
import 'modules/canvas_screen.dart';
import 'modules/forge_screen.dart';
import 'modules/notes_screen.dart';
import 'modules/research_screen.dart';
import 'modules/memories_screen.dart';
import 'modules/focus_screen.dart';
import 'insights_screen.dart';

class ModulesHubScreen extends StatefulWidget {
  const ModulesHubScreen({super.key});
  @override
  State<ModulesHubScreen> createState() => _ModulesHubScreenState();
}

class _ModulesHubScreenState extends State<ModulesHubScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  static final List<Map<String, dynamic>> _moduleData = [
    {
      'title': 'Focus Engine',
      'subtitle': 'Block apps & study',
      'icon': Icons.remove_red_eye_rounded,
      'color': ZenTheme.error,
      'emoji': '🚧',
      'screen': const FocusModeScreen(),
    },
    {
      'title': 'Calendar',
      'subtitle': 'Events & Briefings',
      'icon': Icons.calendar_month_rounded,
      'color': Colors.blueAccent,
      'emoji': '📅',
      'screen': const CalendarModuleScreen(),
    },
    {
      'title': 'Pomodoro Timer',
      'subtitle': 'Pomodoro & Streaks',
      'icon': Icons.school_rounded,
      'color': Colors.amberAccent,
      'emoji': '📚',
      'screen': const StudyModuleScreen(),
    },
    {
      'title': 'Assignments',
      'subtitle': 'GPA & Deadlines',
      'icon': Icons.assignment_rounded,
      'color': ZenTheme.accent,
      'emoji': '📝',
      'screen': const AssignmentsModuleScreen(),
    },
    {
      'title': 'Quick Notes',
      'subtitle': 'Thoughts & Ideas',
      'icon': Icons.notes_rounded,
      'color': BlitzTheme.blue,
      'emoji': '🗒️',
      'screen': const NotesModuleScreen(),
    },
    {
      'title': 'Reading',
      'subtitle': 'Queue & Summaries',
      'icon': Icons.menu_book_rounded,
      'color': BlitzTheme.green,
      'emoji': '📖',
      'screen': const ReadingModuleScreen(),
    },
    {
      'title': 'Startup HQ',
      'subtitle': 'MRR, Burn & Investors',
      'icon': Icons.rocket_launch_rounded,
      'color': const Color(0xFFF59E0B),
      'emoji': '🚀',
      'screen': const StartupModuleScreen(),
    },
    {
      'title': 'Finance',
      'subtitle': 'Expenses & Net Worth',
      'icon': Icons.account_balance_rounded,
      'color': BlitzTheme.accent,
      'emoji': '💰',
      'screen': const FinanceModuleScreen(),
    },
    {
      'title': 'Mood',
      'subtitle': 'Energy & Check-ins',
      'icon': Icons.mood_rounded,
      'color': BlitzTheme.red,
      'emoji': '🧠',
      'screen': const MoodModuleScreen(),
    },
    {
      'title': 'Canvas',
      'subtitle': 'Draw & Write',
      'icon': Icons.draw_rounded,
      'color': BlitzTheme.accent,
      'emoji': '🖌️',
      'screen': const CanvasModuleScreen(),
    },
    {
      'title': 'The Forge',
      'subtitle': 'Code & Execute',
      'icon': Icons.code_rounded,
      'color': const Color(0xFFFDBA74),
      'emoji': '🔥',
      'screen': const ForgeModuleScreen(),
    },
    {
      'title': 'Memory Vault',
      'subtitle': 'Persistent AI Context',
      'icon': Icons.memory_rounded,
      'color': BlitzTheme.cyan,
      'emoji': '🧠',
      'screen': const MemoriesScreen(),
    },
    {
      'title': 'Deep Research',
      'subtitle': 'Autonomous Agent',
      'icon': Icons.hub_rounded,
      'color': BlitzTheme.cyan,
      'emoji': '🕵️',
      'screen': const ResearchScreen(),
    },
    {
      'title': 'Study Insights',
      'subtitle': 'Analytics & Progress',
      'icon': Icons.insights_rounded,
      'color': Colors.purpleAccent,
      'emoji': '📊',
      'screen': const InsightsScreen(),
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _moduleData.where((m) => 
      m['title'].toString().toLowerCase().contains(_query.toLowerCase()) ||
      m['subtitle'].toString().toLowerCase().contains(_query.toLowerCase())
    ).toList();

    return Container(
      decoration: const BoxDecoration(gradient: BlitzTheme.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(filtered.length),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  style: GoogleFonts.dmSans(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search modules...',
                    hintStyle: GoogleFonts.dmSans(color: Colors.white24, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white24, size: 18),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWeb = constraints.maxWidth > 800;
                    final crossAxisCount = isWeb ? 4 : 2;
                    final itemsPerPage = crossAxisCount * 3;
                    final pageCount = (filtered.length / itemsPerPage).ceil();

                    return PageView.builder(
                      itemCount: pageCount,
                      controller: PageController(),
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, pageIndex) {
                        final start = pageIndex * itemsPerPage;
                        final end = (start + itemsPerPage < filtered.length) ? start + itemsPerPage : filtered.length;
                        final pageItems = filtered.sublist(start, end);

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: isWeb ? 1.4 : 1.1,
                            ),
                            itemCount: pageItems.length,
                            itemBuilder: (context, index) {
                              final data = pageItems[index];
                              return _ModuleCard(
                                title: data['title'],
                                subtitle: data['subtitle'],
                                icon: data['icon'],
                                color: data['color'],
                                emoji: data['emoji'],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => data['screen'] as Widget),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          const Icon(Icons.widgets_rounded, size: 20, color: BlitzTheme.accent),
          const SizedBox(width: 10),
          Text(
            'MODULES',
            style: GoogleFonts.syne(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: ZenTheme.text,
            ),
          ),
          const Spacer(),
          Text(
            '${_query.isNotEmpty ? "MATCHED " : ""}$count ACTIVE',
            style: GoogleFonts.spaceMono(
              fontSize: 9,
              color: ZenTheme.success,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String emoji;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.emoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.06),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: color.withValues(alpha: 0.1),
                  ),
                  child:
                      Icon(Icons.arrow_forward_rounded, size: 14, color: color),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: GoogleFonts.syne(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ZenTheme.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.spaceMono(
                fontSize: 9,
                color: ZenTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
