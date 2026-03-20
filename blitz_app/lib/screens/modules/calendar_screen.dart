import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';
import '../../core/database.dart';
import '../../services/zen_notifier.dart';
import '../../models/event.dart';
import '../../widgets/shared_widgets.dart';

class CalendarModuleScreen extends StatefulWidget {
  const CalendarModuleScreen({super.key});
  @override
  State<CalendarModuleScreen> createState() => _CalendarModuleScreenState();
}

class _CalendarModuleScreenState extends State<CalendarModuleScreen> {
  final _db = ZenDatabase();
  List<CalendarEvent> _events = [];
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final end = start.add(const Duration(days: 1));
    final events = await _db.getEvents(from: start, to: end);
    if (mounted) setState(() { _events = events; _loading = false; });
  }

  Future<void> _addEvent() async {
    final titleCtrl = TextEditingController();
    String eventType = 'general';
    TimeOfDay startTime = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 11, minute: 0);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BlitzTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: BlitzTheme.textMuted.withValues(alpha: 0.3)))),
              const SizedBox(height: 20),
              Text('New Event', style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.w800, color: BlitzTheme.textPrimary)),
              const SizedBox(height: 16),
              TextField(controller: titleCtrl, autofocus: true, style: GoogleFonts.syne(color: BlitzTheme.textPrimary, fontSize: 16), decoration: const InputDecoration(hintText: 'Event title')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: ['general', 'meeting', 'class', 'deadline', 'social'].map((t) {
                  final sel = eventType == t;
                  return GestureDetector(
                    onTap: () => setModalState(() => eventType = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: sel ? BlitzTheme.accent.withValues(alpha: 0.12) : Colors.transparent,
                        border: Border.all(color: sel ? BlitzTheme.accent : BlitzTheme.border),
                      ),
                      child: Text(t.toUpperCase(), style: GoogleFonts.spaceMono(fontSize: 8, fontWeight: FontWeight.w700, color: sel ? BlitzTheme.accent : BlitzTheme.textMuted)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: startTime);
                        if (t != null) setModalState(() => startTime = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: BlitzTheme.border)),
                        child: Text('Start: ${startTime.format(context)}', style: GoogleFonts.syne(fontSize: 13, color: BlitzTheme.textPrimary)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: endTime);
                        if (t != null) setModalState(() => endTime = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: BlitzTheme.border)),
                        child: Text('End: ${endTime.format(context)}', style: GoogleFonts.syne(fontSize: 13, color: BlitzTheme.textPrimary)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    final event = CalendarEvent(
                      title: titleCtrl.text.trim(),
                      eventType: eventType,
                      startTime: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, startTime.hour, startTime.minute),
                      endTime: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, endTime.hour, endTime.minute),
                    );
                    await _db.insertEvent(event);
                    await ZenNotifier().scheduleEventReminder(event);
                    if (context.mounted) Navigator.pop(context);
                    _loadEvents();
                  },
                  child: const Text('Add Event'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlitzTheme.bg,
      appBar: AppBar(
        title: Text('Calendar', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _addEvent)],
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: BlitzTheme.accent))
                : _events.isEmpty
                    ? EmptyState(icon: Icons.calendar_today, title: 'No Events', subtitle: 'Nothing scheduled for ${DateFormat('MMM d').format(_selectedDate)}', color: BlitzTheme.blue)
                    : _buildTimelineView(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineView() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: 24,
      itemBuilder: (context, hour) {
        final hourEvents = _events.where((e) => e.startTime.hour == hour).toList();
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Time label
              SizedBox(
                width: 50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              // Vertical divider line
              Container(width: 1, color: BlitzTheme.border.withValues(alpha: 0.5)),
              const SizedBox(width: 12),
              // Events for this hour
              Expanded(
                child: Column(
                  children: hourEvents.map((e) => _buildEventTimelineCard(e)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEventTimelineCard(CalendarEvent event) {
    final typeColors = {'meeting': BlitzTheme.blue, 'class': BlitzTheme.green, 'deadline': BlitzTheme.red, 'social': BlitzTheme.gold};
    final color = typeColors[event.eventType] ?? BlitzTheme.accent;
    
    return GestureDetector(
      onTap: () => _showEventOptions(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, top: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.02)],
          ),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(event.title, style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w800, color: BlitzTheme.textPrimary))),
                Text(event.eventType.toUpperCase(), style: GoogleFonts.spaceMono(fontSize: 7, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 10, color: color.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text(
                  '${DateFormat('HH:mm').format(event.startTime)} – ${DateFormat('HH:mm').format(event.endTime)}',
                  style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.textMuted),
                ),
                if (event.location.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.location_on_rounded, size: 10, color: BlitzTheme.textMuted),
                  const SizedBox(width: 2),
                  Text(event.location, style: GoogleFonts.syne(fontSize: 9, color: BlitzTheme.textMuted)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEventOptions(CalendarEvent event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: BlitzTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(event.title, style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text('${DateFormat('HH:mm').format(event.startTime)} - ${DateFormat('HH:mm').format(event.endTime)}', style: GoogleFonts.spaceMono(fontSize: 12, color: BlitzTheme.textMuted)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () { 
                      Navigator.pop(c);
                      _editEvent(event);
                    },
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                    style: ElevatedButton.styleFrom(backgroundColor: BlitzTheme.accent, foregroundColor: Colors.black),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(c);
                      await _db.deleteEvent(event.id);
                      await ZenNotifier().cancelReminder(event.id);
                      _loadEvents();
                    },
                    icon: const Icon(Icons.delete_rounded, size: 16),
                    label: const Text('Remove'),
                    style: ElevatedButton.styleFrom(backgroundColor: BlitzTheme.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _editEvent(CalendarEvent event) async {
    final titleCtrl = TextEditingController(text: event.title);
    String type = event.eventType;
    TimeOfDay start = TimeOfDay.fromDateTime(event.startTime);
    TimeOfDay end = TimeOfDay.fromDateTime(event.endTime);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BlitzTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               Text('Edit Event', style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.w800)),
               const SizedBox(height: 16),
               TextField(controller: titleCtrl, style: GoogleFonts.syne(color: Colors.white)),
               const SizedBox(height: 20),
               // Repeat logic from _addEvent basically
               SizedBox(
                 width: double.infinity,
                 child: ElevatedButton(
                   onPressed: () async {
                     final updated = CalendarEvent(
                       id: event.id,
                       title: titleCtrl.text.trim(),
                       eventType: type,
                       startTime: DateTime(event.startTime.year, event.startTime.month, event.startTime.day, start.hour, start.minute),
                       endTime: DateTime(event.endTime.year, event.endTime.month, event.endTime.day, end.hour, end.minute),
                     );
                     await _db.insertEvent(updated);
                     if (context.mounted) Navigator.pop(context);
                     _loadEvents();
                   },
                   child: const Text('Save Changes'),
                 ),
               ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 14,
        itemBuilder: (_, i) {
          final date = DateTime.now().add(Duration(days: i - 2));
          final sel = date.day == _selectedDate.day && date.month == _selectedDate.month;
          return GestureDetector(
            onTap: () { setState(() => _selectedDate = date); _loadEvents(); },
            child: Container(
              width: 48, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: sel ? BlitzTheme.accent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                border: Border.all(color: sel ? BlitzTheme.accent : BlitzTheme.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('EEE').format(date).toUpperCase(), style: GoogleFonts.spaceMono(fontSize: 8, color: sel ? BlitzTheme.accent : BlitzTheme.textMuted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${date.day}', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800, color: sel ? BlitzTheme.accent : BlitzTheme.textPrimary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
