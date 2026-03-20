import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../core/database.dart';
import '../../core/zen_brain.dart';
import '../../models/startup_metrics.dart';
import '../../models/investor.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/shared_widgets.dart';

class StartupModuleScreen extends StatefulWidget {
  const StartupModuleScreen({super.key});
  @override
  State<StartupModuleScreen> createState() => _StartupModuleScreenState();
}

class _StartupModuleScreenState extends State<StartupModuleScreen> {
  final _db = ZenDatabase();
  final _brain = ZenBrain();
  StartupMetrics? _metrics;
  List<Investor> _investors = [];
  Map<String, dynamic>? _defaultAlive;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final metrics = await _db.getLatestStartupMetrics();
    final investors = await _db.getInvestors();
    final alive = await _brain.defaultAliveCalculation();
    if (mounted) {
      setState(() {
        _metrics = metrics;
        _investors = investors;
        _defaultAlive = alive;
        _loading = false;
      });
    }
  }

  Future<void> _updateMetrics() async {
    final mrrCtrl = TextEditingController(text: _metrics?.mrr.toString() ?? '0');
    final burnCtrl = TextEditingController(text: _metrics?.burnRate.toString() ?? '0');
    final usersCtrl = TextEditingController(text: _metrics?.totalUsers.toString() ?? '0');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BlitzTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: BlitzTheme.textMuted.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Update Metrics', style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.w800, color: BlitzTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: mrrCtrl,
              keyboardType: TextInputType.number,
              style: GoogleFonts.syne(color: BlitzTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'MRR (\$)', prefixText: '\$ '),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: burnCtrl,
              keyboardType: TextInputType.number,
              style: GoogleFonts.syne(color: BlitzTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Monthly Burn (\$)', prefixText: '\$ '),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: usersCtrl,
              keyboardType: TextInputType.number,
              style: GoogleFonts.syne(color: BlitzTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Total Users'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final mrr = double.tryParse(mrrCtrl.text) ?? 0;
                  final burn = double.tryParse(burnCtrl.text) ?? 0;
                  final users = int.tryParse(usersCtrl.text) ?? 0;
                  final runway = burn > 0 ? (mrr / burn) * 12 : 0.0;
                  await _db.insertStartupMetrics(StartupMetrics(
                    mrr: mrr, burnRate: burn, totalUsers: users, runwayMonths: runway,
                  ));
                  if (c.mounted) Navigator.pop(c);
                  _loadData();
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addInvestor() async {
    final nameCtrl = TextEditingController();
    final firmCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BlitzTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: BlitzTheme.textMuted.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Add Investor', style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.w800, color: BlitzTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: GoogleFonts.syne(color: BlitzTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Investor name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: firmCtrl,
              style: GoogleFonts.syne(color: BlitzTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Firm (optional)'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  await _db.insertInvestor(Investor(
                    name: nameCtrl.text.trim(), firm: firmCtrl.text.trim(),
                  ));
                  if (c.mounted) Navigator.pop(c);
                  _loadData();
                },
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlitzTheme.bg,
      appBar: AppBar(
        title: Text('Startup HQ', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: _updateMetrics),
          IconButton(icon: const Icon(Icons.person_add), onPressed: _addInvestor),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BlitzTheme.accent))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: BlitzTheme.accent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Default alive card
                    if (_defaultAlive != null && _defaultAlive!['alive'] != null)
                      _buildAliveCard(),
                    // Metrics
                    Row(children: [
                      Expanded(child: MetricCard(
                        label: 'MRR', value: '\$${_metrics?.mrr.toStringAsFixed(0) ?? '0'}',
                        icon: Icons.trending_up, color: BlitzTheme.green,
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: MetricCard(
                        label: 'BURN', value: '\$${_metrics?.burnRate.toStringAsFixed(0) ?? '0'}/mo',
                        icon: Icons.local_fire_department, color: BlitzTheme.red,
                      )),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: MetricCard(
                        label: 'RUNWAY', value: '${_metrics?.runwayMonths.toStringAsFixed(1) ?? '0'} mo',
                        icon: Icons.flight_takeoff, color: BlitzTheme.gold,
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: MetricCard(
                        label: 'USERS', value: '${_metrics?.totalUsers ?? 0}',
                        icon: Icons.people, color: BlitzTheme.blue,
                      )),
                    ]),
                    const SizedBox(height: 16),
                    // Investor pipeline
                    const SectionHeader(title: 'INVESTOR PIPELINE', icon: Icons.business_center, color: Color(0xFFF59E0B)),
                    if (_investors.isEmpty)
                      const EmptyState(
                        icon: Icons.person_add, title: 'No Investors',
                        subtitle: 'Track your fundraising pipeline',
                        color: Color(0xFFF59E0B),
                      )
                    else
                      ..._investors.map((inv) => _buildInvestorCard(inv)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAliveCard() {
    final isAlive = _defaultAlive!['alive'] as bool;
    final color = isAlive ? BlitzTheme.green : BlitzTheme.red;
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: color.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(isAlive ? '✅' : '🔴', style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Text(
              isAlive ? 'DEFAULT ALIVE' : 'DEFAULT DEAD',
              style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800, color: color),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            _defaultAlive!['message'] as String,
            style: GoogleFonts.syne(fontSize: 12, color: BlitzTheme.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildInvestorCard(Investor inv) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: BlitzTheme.border),
      ),
      child: Row(children: [
        Text(inv.stageEmoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(inv.name, style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700, color: BlitzTheme.textPrimary)),
            if (inv.firm.isNotEmpty)
              Text(inv.firm, style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.textMuted)),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: BlitzTheme.accent.withValues(alpha: 0.12),
          ),
          child: Text(
            inv.stage.toUpperCase(),
            style: GoogleFonts.spaceMono(fontSize: 8, fontWeight: FontWeight.w700, color: BlitzTheme.accent),
          ),
        ),
      ]),
    );
  }
}
