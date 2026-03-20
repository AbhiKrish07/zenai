import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';
import '../../core/database.dart';
import '../../models/assignment.dart';
import '../../widgets/shared_widgets.dart';

class AssignmentsModuleScreen extends StatefulWidget {
  const AssignmentsModuleScreen({super.key});
  @override
  State<AssignmentsModuleScreen> createState() => _AssignmentsModuleScreenState();
}

class _AssignmentsModuleScreenState extends State<AssignmentsModuleScreen> {
  final _db = ZenDatabase();
  List<Assignment> _assignments = [];
  double _gpa = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final assignments = await _db.getAssignments();
    final gpa = await _db.calculateGPA();
    if (mounted) setState(() { _assignments = assignments; _gpa = gpa; _loading = false; });
  }

  Future<void> _addAssignment() async {
    final titleCtrl = TextEditingController();
    final courseCtrl = TextEditingController();
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: BlitzTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, ss) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: BlitzTheme.textMuted.withValues(alpha: 0.3)))),
            const SizedBox(height: 20),
            Text('New Assignment', style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.w800, color: BlitzTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(controller: titleCtrl, autofocus: true, style: GoogleFonts.syne(color: BlitzTheme.textPrimary), decoration: const InputDecoration(hintText: 'Assignment title')),
            const SizedBox(height: 8),
            TextField(controller: courseCtrl, style: GoogleFonts.syne(color: BlitzTheme.textPrimary), decoration: const InputDecoration(hintText: 'Course name')),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: dueDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) ss(() => dueDate = d);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: BlitzTheme.border)),
                child: Row(children: [
                  const Icon(Icons.calendar_today, size: 16, color: BlitzTheme.textMuted), const SizedBox(width: 10),
                  Text('Due: ${DateFormat('MMM d, y').format(dueDate)}', style: GoogleFonts.syne(fontSize: 13, color: BlitzTheme.textPrimary)),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.isEmpty || courseCtrl.text.isEmpty) return;
                await _db.insertAssignment(Assignment(title: titleCtrl.text.trim(), course: courseCtrl.text.trim(), dueDate: dueDate));
                if (context.mounted) Navigator.pop(context);
                _loadData();
              },
              child: const Text('Add Assignment'),
            )),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlitzTheme.bg,
      appBar: AppBar(title: Text('Assignments', style: GoogleFonts.syne(fontWeight: FontWeight.w800)), actions: [IconButton(icon: const Icon(Icons.add), onPressed: _addAssignment)]),
      body: _loading ? const Center(child: CircularProgressIndicator(color: BlitzTheme.accent)) : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // GPA card
          GlassContainer(margin: EdgeInsets.zero, borderColor: BlitzTheme.cyan.withValues(alpha: 0.2), child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('GPA', style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted, letterSpacing: 1.5)),
              Text(_gpa.toStringAsFixed(2), style: GoogleFonts.syne(fontSize: 36, fontWeight: FontWeight.w800, color: BlitzTheme.cyan)),
            ]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: (_gpa >= 3.5 ? BlitzTheme.green : _gpa >= 3.0 ? BlitzTheme.gold : BlitzTheme.red).withValues(alpha: 0.12)),
              child: Text(_gpa >= 3.5 ? 'Excellent' : _gpa >= 3.0 ? 'Good' : 'Needs Work', style: GoogleFonts.spaceMono(fontSize: 9, fontWeight: FontWeight.w700, color: _gpa >= 3.5 ? BlitzTheme.green : _gpa >= 3.0 ? BlitzTheme.gold : BlitzTheme.red)),
            ),
          ])),
          const SizedBox(height: 16),
          if (_assignments.isEmpty)
            const EmptyState(icon: Icons.assignment, title: 'No Assignments', subtitle: 'Track your coursework and grades', color: BlitzTheme.cyan)
          else
            ..._assignments.map((a) {
              final daysLeft = a.timeUntilDue.inDays;
              final urgencyColor = a.isOverdue ? BlitzTheme.red : daysLeft <= 3 ? BlitzTheme.gold : BlitzTheme.green;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white.withValues(alpha: 0.04), border: Border.all(color: urgencyColor.withValues(alpha: 0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(a.title, style: GoogleFonts.syne(fontSize: 14, fontWeight: FontWeight.w700, color: BlitzTheme.textPrimary))),
                    if (a.grade != null) Text('${a.percentage.toStringAsFixed(0)}%', style: GoogleFonts.spaceMono(fontSize: 12, fontWeight: FontWeight.w700, color: BlitzTheme.cyan)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(a.course, style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.accent)),
                    const Spacer(),
                    Text(a.isOverdue ? 'OVERDUE' : '${daysLeft}d left', style: GoogleFonts.spaceMono(fontSize: 9, fontWeight: FontWeight.w700, color: urgencyColor)),
                  ]),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}
