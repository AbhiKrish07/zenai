import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/database.dart';
import '../models/study_session.dart';
import '../theme.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  String _timeframe = 'Month';
  final _db = ZenDatabase();
  List<StudySession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final days = _timeframe == 'Week' ? 7 : (_timeframe == 'Month' ? 30 : (_timeframe == 'Year' ? 365 : 1000));
    final sessions = await _db.getStudySessions(days: days);
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading 
          ? const Center(child: CircularProgressIndicator(color: ZenTheme.accent))
          : CustomScrollView(
              slivers: [
                _buildAppBar(),
                SliverToBoxAdapter(child: _buildTimeframeSelector()),
                SliverToBoxAdapter(child: _buildSummarySection()),
                SliverToBoxAdapter(child: _buildTimeSpentChart()),
                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
              ],
            ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      sliver: SliverToBoxAdapter(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Insights', style: GoogleFonts.syne(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
                Text(DateFormat('MMMM yyyy').format(DateTime.now()), style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white38, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.sell_outlined, color: Colors.white38),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeframeSelector() {
    final options = ['Week', 'Month', 'Year', 'All Time'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(32)),
        child: Row(
          children: options.map((opt) => Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _timeframe = opt);
                _loadData();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _timeframe == opt ? const Color(0xFF2C2C2E) : Colors.transparent,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Center(
                  child: Text(opt, style: GoogleFonts.dmSans(fontSize: 12, color: _timeframe == opt ? Colors.white : Colors.white38, fontWeight: _timeframe == opt ? FontWeight.bold : FontWeight.normal)),
                ),
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildSummarySection() {
    final totalMin = _sessions.fold(0, (sum, s) => sum + s.durationMinutes);
    final avgMin = _sessions.isEmpty ? 0 : (totalMin / _sessions.length).round();
    final perDay = _sessions.isEmpty ? 0 : (totalMin / 30).toStringAsFixed(1); // Rough Month avg

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Summary', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              const Icon(Icons.fingerprint, color: Colors.white38, size: 16),
              const SizedBox(width: 8),
              const Icon(Icons.cake, color: Colors.white38, size: 16),
              const SizedBox(width: 8),
              const Icon(Icons.car_repair, color: Colors.white38, size: 16),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _buildStatCard('Duration', '${totalMin ~/ 60}h', 'Time Focused', Icons.access_time_rounded),
              _buildStatCard('Amount', '${_sessions.length}', 'Focus Sessions', Icons.tag),
              _buildStatCard('Average Duration', '${avgMin}m', 'Per Session', Icons.history_rounded),
              _buildStatCard('Average Amount', '$perDay', 'Per Day', Icons.bar_chart_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String val, String sub, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 12, color: Colors.white38), const SizedBox(width: 6), Text(title, style: GoogleFonts.dmSans(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.w600))]),
          const Spacer(),
          Text(val, style: GoogleFonts.syne(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(sub, style: GoogleFonts.dmSans(fontSize: 10, color: Colors.white24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTimeSpentChart() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Time Spent', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const Row(
                children: [
                  Icon(Icons.touch_app_outlined, color: Colors.white38, size: 16),
                  SizedBox(width: 12),
                  Icon(Icons.grid_view_rounded, color: Colors.white38, size: 16),
                ],
              ),
            ],
          ),
          Text('Change Metric', style: GoogleFonts.dmSans(fontSize: 10, color: Colors.white24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Container(
            height: 200,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(24)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(24, (i) {
                final height = (i % 7 == 0 ? 0.2 : (i % 3 == 0 ? 0.8 : 0.4)) * 140; // Simulated
                return Container(
                  width: 4,
                  height: height,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
